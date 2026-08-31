package com.bukovinafilip.gradey.feature.gradeyai

import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIMessage
import com.bukovinafilip.gradey.model.GradeyAIMessageRole
import com.bukovinafilip.gradey.model.GradeyAIMessageStatus
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.google.common.truth.Truth.assertThat
import java.util.ArrayDeque
import java.util.Locale
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class GradeyAIControllerTest {
    @Test
    fun `controller initialized below started blocks bootstrap until foregrounded`() = runTest {
        val repository = FakeRepository()
        val controller = controller(
            repository = repository,
            scope = this,
            initiallyForegrounded = false,
        )

        controller.bootstrap()

        assertThat(controller.isAppForegrounded).isFalse()
        assertThat(controller.status).isNull()
        assertThat(repository.statusLoadCalls).isEqualTo(0)
        assertThat(controller.onAppForegrounded()).isTrue()
        controller.bootstrap()
        assertThat(repository.statusLoadCalls).isEqualTo(1)
    }

    @Test
    fun `bootstrap loads scoped conversations context and support-adjusted limits`() = runTest {
        val conversation = conversation("existing", "Existing chat")
        val repository = FakeRepository(conversations = mutableListOf(conversation))
        val controller = controller(repository = repository)
        controller.applySupportTier(GradeySupportTier.STANDARD)

        controller.bootstrap()

        assertThat(controller.status?.dailyLimit).isEqualTo(10)
        assertThat(controller.status?.remaining).isEqualTo(8)
        assertThat(controller.conversations).containsExactly(conversation)
        assertThat(controller.contextSnapshot?.schoolScope).isEqualTo("scope")
        assertThat(repository.listScopes).containsExactly("scope")
        assertThat(controller.failure).isNull()
    }

    @Test
    fun `unresolved free support state preserves the server reported limit`() = runTest {
        val repository = FakeRepository(
            status = status().copy(dailyLimit = 25, dailyUsed = 4, remaining = 21),
        )
        val controller = controller(repository = repository)
        controller.applySupportTier(GradeySupportTier.NONE)

        controller.bootstrap()

        assertThat(controller.status?.dailyLimit).isEqualTo(25)
        assertThat(controller.status?.remaining).isEqualTo(21)
    }

    @Test
    fun `send creates chat streams deltas persists assistant and updates remaining`() = runTest {
        val persisted = message(
            id = "assistant",
            role = GradeyAIMessageRole.ASSISTANT,
            content = "A clear answer",
            status = GradeyAIMessageStatus.COMPLETE,
        )
        val repository = FakeRepository().apply {
            streams += flowOf(
                GradeyAIStreamEvent.Start("assistant", 2),
                GradeyAIStreamEvent.Delta("A clear"),
                GradeyAIStreamEvent.Delta(" answer"),
                GradeyAIStreamEvent.Done("stop", 2, 10, 4, persisted),
            )
        }
        val controller = controller(repository = repository)
        controller.bootstrap()

        controller.send("  Explain my marks  ")

        assertThat(repository.createdTitles).containsExactly("Explain my marks")
        assertThat(repository.streamRequests.single().text).isEqualTo("Explain my marks")
        assertThat(repository.streamRequests.single().context.schoolScope).isEqualTo("scope")
        assertThat(controller.messages.map { it.role })
            .containsExactly(GradeyAIMessageRole.USER, GradeyAIMessageRole.ASSISTANT).inOrder()
        assertThat(controller.messages.last()).isEqualTo(persisted)
        assertThat(controller.status?.remaining).isEqualTo(2)
        assertThat(controller.isStreaming).isFalse()
    }

    @Test
    fun `retry replaces retryable failed response with successful reply`() = runTest {
        val repository = FakeRepository().apply {
            streams += flowOf(
                GradeyAIStreamEvent.Start("failed-assistant", 3),
                GradeyAIStreamEvent.Error(
                    "unavailable",
                    "Internal backend detail that must never reach the UI",
                    true,
                    3,
                ),
            )
            streams += flowOf(
                GradeyAIStreamEvent.Start("retried-assistant", 2),
                GradeyAIStreamEvent.Delta("Recovered"),
                GradeyAIStreamEvent.Done("stop", 2, null, null, null),
            )
        }
        val controller = controller(repository = repository)
        controller.bootstrap()
        controller.send("Help")
        val failed = controller.messages.last()

        assertThat(failed.status).isEqualTo(GradeyAIMessageStatus.FAILED)
        assertThat(controller.canRetry(failed)).isTrue()
        assertThat(controller.failure)
            .isEqualTo(GradeyAIFailure(GradeyAIErrorKind.SERVER, retryable = true))
        assertThat(failureMessageResource(controller.failure!!.kind))
            .isEqualTo(R.string.gradey_ai_unavailable_message)

        controller.retry()

        assertThat(repository.streamRequests).hasSize(2)
        assertThat(repository.streamRequests[1].clientMessageID)
            .isEqualTo(repository.streamRequests[0].clientMessageID)
        assertThat(controller.messages.none { it.status == GradeyAIMessageStatus.FAILED }).isTrue()
        assertThat(controller.messages.last().content).isEqualTo("Recovered")
        assertThat(controller.messages.last().status).isEqualTo(GradeyAIMessageStatus.COMPLETE)
    }

    @Test
    fun `every failure kind resolves to product owned copy`() {
        val resources = GradeyAIErrorKind.entries.associateWith(::failureMessageResource)

        assertThat(resources.keys).containsExactlyElementsIn(GradeyAIErrorKind.entries)
        assertThat(resources[GradeyAIErrorKind.SERVER])
            .isEqualTo(R.string.gradey_ai_unavailable_message)
        assertThat(resources.values).doesNotContain(0)
    }

    @Test
    fun `stop cancels active stream and marks partial assistant response cancelled`() = runTest {
        val repository = FakeRepository().apply {
            streams += flow {
                emit(GradeyAIStreamEvent.Start("assistant", 3))
                emit(GradeyAIStreamEvent.Delta("Partial"))
                awaitCancellation()
            }
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val sendJob = launch { controller.send("Help") }
        runCurrent()

        assertThat(controller.isStreaming).isTrue()
        controller.stop()
        runCurrent()

        assertThat(controller.isStreaming).isFalse()
        assertThat(controller.messages.last().content).isEqualTo("Partial")
        assertThat(controller.messages.last().status).isEqualTo(GradeyAIMessageStatus.CANCELLED)
        sendJob.join()
        advanceUntilIdle()
    }

    @Test
    fun `manual stop during chat creation restores prompt without an orphan bubble`() = runTest {
        val repository = FakeRepository().apply { holdCreate = true }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.beginDraftChat("New chat")
        val send = launch { controller.send("Keep this prompt") }
        runCurrent()

        controller.stop()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Keep this prompt")
        repository.releaseCreate()
        advanceUntilIdle()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Keep this prompt")
        assertThat(repository.streamRequests).isEmpty()
        send.join()
    }

    @Test
    fun `manual stop before stream start reloads history and restores missing prompt`() = runTest {
        var beforeStart: Continuation<Unit>? = null
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            streams += flow {
                suspendCoroutine { beforeStart = it }
                emit(GradeyAIStreamEvent.Start("assistant", 2))
                emit(GradeyAIStreamEvent.Done("stop", 2, null, null, null))
            }
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.open(existing)
        val send = launch { controller.send("Restore after stop") }
        runCurrent()

        controller.stop()
        runCurrent()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Restore after stop")
        assertThat(repository.loadedIDs).containsExactly("existing", "existing")
        beforeStart?.resume(Unit)
        advanceUntilIdle()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Restore after stop")
        send.join()
    }

    @Test
    fun `background cancels a stream and late events cannot repopulate foreground state`() = runTest {
        var lateStreamContinuation: Continuation<Unit>? = null
        val repository = FakeRepository().apply {
            streams += flow {
                emit(GradeyAIStreamEvent.Start("assistant", 3))
                emit(GradeyAIStreamEvent.Delta("Visible"))
                suspendCoroutine { lateStreamContinuation = it }
                emit(GradeyAIStreamEvent.Delta(" stale"))
                emit(GradeyAIStreamEvent.Done("stop", 2, null, null, null))
            }
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val send = launch { controller.send("Help") }
        runCurrent()

        assertThat(controller.isStreaming).isTrue()
        controller.onAppBackgrounded()

        assertThat(controller.isAppForegrounded).isFalse()
        assertThat(controller.isStreaming).isFalse()
        assertThat(controller.isSending).isFalse()
        assertThat(controller.messages.last().content).isEqualTo("Visible")
        assertThat(controller.messages.last().status).isEqualTo(GradeyAIMessageStatus.CANCELLED)
        assertThat(controller.canStartNewChat).isFalse()
        controller.send("Must stay blocked")
        assertThat(repository.streamRequests).hasSize(1)
        assertThat(controller.onAppForegrounded()).isTrue()
        assertThat(controller.onAppForegrounded()).isFalse()

        lateStreamContinuation?.resume(Unit)
        advanceUntilIdle()

        assertThat(controller.messages.last().content).isEqualTo("Visible")
        assertThat(controller.messages.last().status).isEqualTo(GradeyAIMessageStatus.CANCELLED)
        send.join()
    }

    @Test
    fun `background during chat creation restores the prompt without an orphan bubble`() = runTest {
        val repository = FakeRepository().apply { holdCreate = true }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.beginDraftChat("New chat")
        val send = launch { controller.send("Help me") }
        runCurrent()

        assertThat(controller.messages.single().content).isEqualTo("Help me")
        controller.onAppBackgrounded()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Help me")
        assertThat(controller.onAppForegrounded()).isTrue()
        controller.bootstrap()
        repository.releaseCreate()
        advanceUntilIdle()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Help me")
        assertThat(repository.streamRequests).isEmpty()
        send.join()
    }

    @Test
    fun `background before stream start reloads persisted prompt instead of duplicating it`() = runTest {
        var beforeStart: Continuation<Unit>? = null
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            streams += flow {
                suspendCoroutine { beforeStart = it }
                emit(GradeyAIStreamEvent.Start("assistant", 2))
                emit(GradeyAIStreamEvent.Done("stop", 2, null, null, null))
            }
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.open(existing)
        val send = launch { controller.send("Persist once") }
        runCurrent()
        val request = repository.streamRequests.single()
        repository.loadedMessagesByID[existing.id] = listOf(
            GradeyAIMessage(
                id = "persisted-user",
                conversationID = existing.id,
                clientMessageID = request.clientMessageID,
                role = GradeyAIMessageRole.USER,
                content = request.text,
                status = GradeyAIMessageStatus.COMPLETE,
                createdAtEpochMillis = 1_700_000_000_000,
            ),
        )

        controller.onAppBackgrounded()
        assertThat(controller.messages).isEmpty()
        assertThat(controller.onAppForegrounded()).isTrue()
        controller.bootstrap()

        assertThat(controller.messages.single().id).isEqualTo("persisted-user")
        assertThat(controller.draft).isEmpty()
        assertThat(repository.loadedIDs).containsExactly("existing", "existing")
        beforeStart?.resume(Unit)
        advanceUntilIdle()

        assertThat(controller.messages.single().id).isEqualTo("persisted-user")
        send.join()
    }

    @Test
    fun `background before stream start restores prompt when server history is unchanged`() = runTest {
        var beforeStart: Continuation<Unit>? = null
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            streams += flow {
                suspendCoroutine { beforeStart = it }
                emit(GradeyAIStreamEvent.Start("assistant", 2))
                emit(GradeyAIStreamEvent.Done("stop", 2, null, null, null))
            }
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.open(existing)
        val send = launch { controller.send("Try again safely") }
        runCurrent()

        controller.onAppBackgrounded()
        assertThat(controller.onAppForegrounded()).isTrue()
        controller.bootstrap()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Try again safely")
        beforeStart?.resume(Unit)
        advanceUntilIdle()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.draft).isEqualTo("Try again safely")
        send.join()
    }

    @Test
    fun `draft title remains localized and CRUD operations stay school scoped`() = runTest {
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing))
        val controller = controller(repository = repository)
        controller.bootstrap()

        controller.beginDraftChat("Nový chat")
        assertThat(controller.currentConversation?.title).isEqualTo("Nový chat")
        val draft = controller.currentConversation!!
        controller.delete(draft)
        assertThat(repository.deletedIDs).isEmpty()
        assertThat(controller.currentConversation).isNull()

        controller.open(existing)
        assertThat(repository.loadedIDs).containsExactly("existing")
        controller.delete(existing)
        assertThat(repository.deletedIDs).containsExactly("existing")

        controller.deleteAll()
        assertThat(repository.deleteAllScopes).containsExactly("scope")
        assertThat(controller.conversations).isEmpty()
    }

    @Test
    fun `missing context is explicit and prevents sending`() = runTest {
        val contextBuilder = FakeContextBuilder().apply {
            refreshFailure = GradeyAIContextException(GradeyAIContextError.NO_CONTEXT_AVAILABLE)
        }
        val repository = FakeRepository()
        val controller = controller(repository = repository, contextBuilder = contextBuilder)

        controller.bootstrap()
        controller.send("Help")

        assertThat(controller.contextSnapshot).isNull()
        assertThat(controller.contextFailure?.kind)
            .isEqualTo(com.bukovinafilip.gradey.domain.GradeyAIErrorKind.NO_CONTEXT)
        assertThat(controller.failure?.kind)
            .isEqualTo(com.bukovinafilip.gradey.domain.GradeyAIErrorKind.NO_CONTEXT)
        assertThat(repository.streamRequests).isEmpty()
    }

    @Test
    fun `starter prompt descriptors contain context without hard coded locale copy`() = runTest {
        val snapshot = context().copy(
            trends = listOf(
                com.bukovinafilip.gradey.model.GradeyAITrendContext(
                    subjectID = "math",
                    subjectName = "Mathematics",
                    averageDelta = 0.4,
                    firstMarkCount = 1,
                    latestMarkCount = 2,
                ),
            ),
            timetable = listOf(
                com.bukovinafilip.gradey.model.GradeyAILessonContext(
                    id = "lesson",
                    date = "2026-09-01",
                    subject = "Physics",
                    beginsAt = "08:00",
                    endsAt = "08:45",
                    groups = emptyList(),
                    changeKind = com.bukovinafilip.gradey.model.GradeyAILessonChangeKind.NONE,
                ),
            ),
        )
        val controller = controller(contextBuilder = FakeContextBuilder(snapshot))
        controller.bootstrap()

        assertThat(controller.starterPrompts()).containsExactly(
            GradeyAIStarterPrompt(GradeyAIStarterPromptKind.IMPROVE_SUBJECT, "Mathematics"),
            GradeyAIStarterPrompt(GradeyAIStarterPromptKind.PREPARE_SUBJECT, "Physics"),
            GradeyAIStarterPrompt(GradeyAIStarterPromptKind.SUMMARIZE_MARKS),
        ).inOrder()
    }

    @Test
    fun `closing during a non cooperative create never reopens or streams the chat`() = runTest {
        val repository = FakeRepository().apply { holdCreate = true }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        controller.beginDraftChat("New chat")
        val send = launch { controller.send("Help") }
        runCurrent()

        assertThat(controller.isSending).isTrue()
        assertThat(repository.createdTitles).containsExactly("Help")

        controller.closeConversation()
        repository.releaseCreate()
        advanceUntilIdle()

        assertThat(controller.currentConversation).isNull()
        assertThat(controller.messages).isEmpty()
        assertThat(repository.streamRequests).isEmpty()
        assertThat(controller.failure).isNull()
        send.join()
    }

    @Test
    fun `concurrent sends share one controller owned create and stream`() = runTest {
        val repository = FakeRepository().apply { holdCreate = true }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val first = launch { controller.send("First") }
        runCurrent()

        controller.send("Second")

        assertThat(repository.createdTitles).containsExactly("First")
        repository.releaseCreate()
        advanceUntilIdle()

        assertThat(repository.streamRequests).hasSize(1)
        assertThat(repository.streamRequests.single().text).isEqualTo("First")
        first.join()
    }

    @Test
    fun `open ignores stale out of order results and close invalidates a pending load`() = runTest {
        val first = conversation("first", "First")
        val second = conversation("second", "Second")
        val repository = FakeRepository(conversations = mutableListOf(first, second)).apply {
            holdLoad("first")
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val firstOpen = launch { controller.open(first) }
        runCurrent()

        controller.open(second)
        repository.releaseLoad("first")
        advanceUntilIdle()

        assertThat(controller.currentConversation?.id).isEqualTo("second")
        firstOpen.join()

        repository.holdLoad("first")
        val closingOpen = launch { controller.open(first) }
        runCurrent()
        controller.closeConversation()
        repository.releaseLoad("first")
        advanceUntilIdle()

        assertThat(controller.currentConversation).isNull()
        assertThat(controller.messages).isEmpty()
        closingOpen.join()
    }

    @Test
    fun `foreground bootstrap reloads a conversation whose opening was interrupted`() = runTest {
        val existing = conversation("existing", "Existing")
        val staleMessage = message(
            id = "stale",
            role = GradeyAIMessageRole.ASSISTANT,
            content = "Stale detail",
            status = GradeyAIMessageStatus.COMPLETE,
        )
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            holdLoad("existing")
            loadedMessagesByID["existing"] = listOf(staleMessage)
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val opening = launch { controller.open(existing) }
        runCurrent()

        assertThat(controller.isOpeningConversation).isTrue()
        controller.onAppBackgrounded()
        repository.releaseLoad("existing")
        advanceUntilIdle()

        assertThat(controller.messages).isEmpty()
        assertThat(controller.onAppForegrounded()).isTrue()
        controller.bootstrap()

        assertThat(controller.isOpeningConversation).isFalse()
        assertThat(controller.currentConversation?.id).isEqualTo("existing")
        assertThat(controller.messages).containsExactly(staleMessage)
        assertThat(repository.loadedIDs).containsExactly("existing", "existing")
        opening.join()
    }

    @Test
    fun `caller subtree cancellation does not cancel controller owned open`() = runTest {
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            holdLoad("existing")
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val caller = launch { controller.open(existing) }
        runCurrent()

        caller.cancel()
        repository.releaseLoad("existing")
        advanceUntilIdle()

        assertThat(controller.currentConversation?.id).isEqualTo("existing")
        assertThat(controller.isOpeningConversation).isFalse()
    }

    @Test
    fun `send is blocked while existing conversation history is opening`() = runTest {
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            holdLoad("existing")
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val opening = launch { controller.open(existing) }
        runCurrent()
        controller.draft = "Do not send yet"

        controller.send()

        assertThat(controller.canSend).isFalse()
        assertThat(repository.streamRequests).isEmpty()
        repository.releaseLoad("existing")
        advanceUntilIdle()
        opening.join()
    }

    @Test
    fun `caller subtree cancellation does not cancel controller owned send`() = runTest {
        val repository = FakeRepository().apply { holdCreate = true }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val caller = launch { controller.send("Starter prompt") }
        runCurrent()

        caller.cancel()
        repository.releaseCreate()
        advanceUntilIdle()

        assertThat(repository.streamRequests).hasSize(1)
        assertThat(controller.messages.map { it.role })
            .containsExactly(GradeyAIMessageRole.USER, GradeyAIMessageRole.ASSISTANT).inOrder()
        assertThat(controller.isSending).isFalse()
    }

    @Test
    fun `a non retryable retry clears the previous retry affordance`() = runTest {
        val repository = FakeRepository().apply {
            streams += flowOf(
                GradeyAIStreamEvent.Start("first-failure", 3),
                GradeyAIStreamEvent.Error("unavailable", "Try later", true, 3),
            )
            streams += flowOf(
                GradeyAIStreamEvent.Start("second-failure", 3),
                GradeyAIStreamEvent.Error("invalid_request", "Cannot retry", false, 3),
            )
        }
        val controller = controller(repository = repository)
        controller.bootstrap()
        controller.send("Help")
        controller.retry()

        val latestFailure = controller.messages.last()
        assertThat(latestFailure.status).isEqualTo(GradeyAIMessageStatus.FAILED)
        assertThat(controller.canRetry(latestFailure)).isFalse()
    }

    @Test
    fun `partial context remains usable without a false no context warning`() = runTest {
        val partial = context().copy(
            isStale = true,
            unavailableSections = listOf(com.bukovinafilip.gradey.model.GradeyAIContextSection.TIMETABLE),
        )
        val controller = controller(contextBuilder = FakeContextBuilder(partial))
        controller.bootstrap()
        controller.draft = "Help"

        assertThat(controller.contextSnapshot?.isPartial).isTrue()
        assertThat(controller.contextFailure).isNull()
        assertThat(controller.canSend).isTrue()
    }

    @Test
    fun `background invalidates an in flight context refresh`() = runTest {
        val initial = context()
        val contextBuilder = FakeContextBuilder(initial)
        val controller = controller(contextBuilder = contextBuilder, scope = this)
        controller.bootstrap()
        contextBuilder.snapshot = initial.copy(generatedAtEpochMillis = 1_800_000_000_000)
        contextBuilder.holdRefresh = true
        val refresh = launch { controller.refreshContext() }
        runCurrent()

        assertThat(controller.isRefreshingContext).isTrue()
        controller.onAppBackgrounded()
        assertThat(controller.isRefreshingContext).isFalse()
        assertThat(controller.onAppForegrounded()).isTrue()
        contextBuilder.releaseRefresh()
        advanceUntilIdle()

        assertThat(controller.contextSnapshot?.generatedAtEpochMillis)
            .isEqualTo(initial.generatedAtEpochMillis)
        refresh.join()
    }

    @Test
    fun `held consent acceptance reconciles after a stale foreground bootstrap`() = runTest {
        val repository = FakeRepository(
            status = status().copy(consentRequired = true),
        ).apply {
            holdAccept = true
        }
        val contextBuilder = FakeContextBuilder()
        val controller = controller(
            repository = repository,
            contextBuilder = contextBuilder,
            scope = this,
        )
        controller.bootstrap()
        val accept = launch { controller.acceptConsent() }
        runCurrent()

        assertThat(controller.isAcceptingConsent).isTrue()
        controller.onAppBackgrounded()
        assertThat(controller.onAppForegrounded()).isTrue()
        contextBuilder.holdRefresh = true
        val staleBootstrap = launch { controller.bootstrap() }
        runCurrent()
        assertThat(controller.status?.consentRequired).isTrue()

        repository.releaseAccept()
        runCurrent()

        assertThat(controller.status?.consentRequired).isFalse()
        assertThat(controller.isAcceptingConsent).isFalse()
        assertThat(repository.acceptCalls).isEqualTo(1)
        assertThat(repository.statusLoadCalls).isAtLeast(3)
        contextBuilder.releaseRefresh()
        advanceUntilIdle()

        assertThat(controller.status?.consentRequired).isFalse()
        accept.join()
        staleBootstrap.join()
    }

    @Test
    fun `consent revocation blocks new AI work and leaves cleared state`() = runTest {
        val existing = conversation("existing", "Existing")
        val repository = FakeRepository(conversations = mutableListOf(existing)).apply {
            holdRevoke = true
        }
        val controller = controller(repository = repository, scope = this)
        controller.bootstrap()
        val revoke = launch { controller.revokeConsent() }
        runCurrent()

        assertThat(controller.isPerformingDestructiveOperation).isTrue()
        controller.beginDraftChat("New chat")
        controller.send("Blocked prompt")
        controller.open(existing)

        assertThat(repository.createdTitles).isEmpty()
        assertThat(repository.streamRequests).isEmpty()
        assertThat(repository.loadedIDs).isEmpty()

        controller.onAppBackgrounded()
        assertThat(controller.isPerformingDestructiveOperation).isTrue()
        assertThat(controller.onAppForegrounded()).isTrue()

        repository.releaseRevoke()
        advanceUntilIdle()

        assertThat(controller.status?.consentRequired).isTrue()
        assertThat(controller.conversations).isEmpty()
        assertThat(controller.currentConversation).isNull()
        assertThat(controller.messages).isEmpty()
        assertThat(controller.isPerformingDestructiveOperation).isFalse()
        revoke.join()
    }

    private fun controller(
        repository: FakeRepository = FakeRepository(),
        contextBuilder: FakeContextBuilder = FakeContextBuilder(),
        scope: kotlinx.coroutines.CoroutineScope? = null,
        initiallyForegrounded: Boolean = true,
    ): GradeyAIController {
        var nextID = 0
        val resolvedScope = scope ?: kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined)
        return GradeyAIController(
            repository = repository,
            contextBuilder = contextBuilder,
            scope = resolvedScope,
            nowEpochMillis = { 1_700_000_000_000 + nextID },
            idProvider = { "id-${nextID++}" },
            localeProvider = { Locale.US },
            initiallyForegrounded = initiallyForegrounded,
        )
    }

    private class FakeContextBuilder(
        var snapshot: GradeyAIContextSnapshot = context(),
    ) : GradeyAIContextBuilding {
        var refreshFailure: Throwable? = null
        var holdRefresh = false
        private var refreshContinuation: Continuation<Unit>? = null

        fun releaseRefresh() {
            holdRefresh = false
            refreshContinuation?.resume(Unit)
            refreshContinuation = null
        }

        override suspend fun currentSchoolScope(): String = snapshot.schoolScope
        override suspend fun cachedContext(): GradeyAIContextSnapshot? = null
        override suspend fun refreshContext(): GradeyAIContextSnapshot {
            refreshFailure?.let { throw it }
            if (holdRefresh) suspendCoroutine { refreshContinuation = it }
            return snapshot
        }
    }

    private class FakeRepository(
        var status: GradeyAIStatus = status(),
        val conversations: MutableList<GradeyAIConversation> = mutableListOf(),
    ) : GradeyAIRepository {
        override val isConfigured = true
        val listScopes = mutableListOf<String>()
        val createdTitles = mutableListOf<String?>()
        val loadedIDs = mutableListOf<String>()
        val deletedIDs = mutableListOf<String>()
        val deleteAllScopes = mutableListOf<String>()
        val streamRequests = mutableListOf<StreamRequest>()
        val streams = ArrayDeque<Flow<GradeyAIStreamEvent>>()
        val loadedMessagesByID = mutableMapOf<String, List<GradeyAIMessage>>()
        var statusLoadCalls = 0
        var acceptCalls = 0
        var holdAccept = false
        private var acceptContinuation: Continuation<Unit>? = null
        var holdCreate = false
        private var createContinuation: Continuation<Unit>? = null
        var holdRevoke = false
        private var revokeContinuation: Continuation<Unit>? = null
        private val heldLoadIDs = mutableSetOf<String>()
        private val loadContinuations = mutableMapOf<String, Continuation<Unit>>()

        fun releaseCreate() {
            holdCreate = false
            createContinuation?.resume(Unit)
            createContinuation = null
        }

        fun releaseAccept() {
            holdAccept = false
            acceptContinuation?.resume(Unit)
            acceptContinuation = null
        }

        fun holdLoad(id: String) {
            heldLoadIDs += id
        }

        fun releaseLoad(id: String) {
            heldLoadIDs -= id
            loadContinuations.remove(id)?.resume(Unit)
        }

        fun releaseRevoke() {
            holdRevoke = false
            revokeContinuation?.resume(Unit)
            revokeContinuation = null
        }

        override suspend fun loadStatus(): GradeyAIStatus {
            statusLoadCalls += 1
            return status
        }
        override suspend fun acceptConsent(): GradeyAIConsent {
            acceptCalls += 1
            if (holdAccept) suspendCoroutine { acceptContinuation = it }
            status = status.copy(consentRequired = false)
            return GradeyAIConsent(true, status.termsVersion)
        }
        override suspend fun revokeConsent() {
            if (holdRevoke) suspendCoroutine { revokeContinuation = it }
            status = status.copy(consentRequired = true)
            conversations.clear()
        }
        override suspend fun listConversations(schoolScope: String): List<GradeyAIConversation> {
            listScopes += schoolScope
            return conversations.filter { it.schoolScope == schoolScope }
        }
        override suspend fun createConversation(schoolScope: String, title: String?): GradeyAIConversation {
            createdTitles += title
            if (holdCreate) suspendCoroutine { createContinuation = it }
            return conversation("created", title.orEmpty()).also(conversations::add)
        }
        override suspend fun loadConversation(id: String): GradeyAIConversationDetail {
            loadedIDs += id
            if (id in heldLoadIDs) suspendCoroutine { loadContinuations[id] = it }
            val value = conversations.first { it.id == id }
            return GradeyAIConversationDetail(value, loadedMessagesByID[id].orEmpty())
        }
        override suspend fun deleteConversation(id: String) {
            deletedIDs += id
            conversations.removeAll { it.id == id }
        }
        override suspend fun deleteAllConversations(schoolScope: String) {
            deleteAllScopes += schoolScope
            conversations.removeAll { it.schoolScope == schoolScope }
        }
        override fun streamReply(
            conversationID: String,
            clientMessageID: String,
            text: String,
            context: GradeyAIContextSnapshot,
            locale: String,
        ): Flow<GradeyAIStreamEvent> {
            streamRequests += StreamRequest(conversationID, clientMessageID, text, context, locale)
            return (if (streams.isEmpty()) null else streams.removeFirst()) ?: flowOf(
                GradeyAIStreamEvent.Start("assistant", status.remaining - 1),
                GradeyAIStreamEvent.Done("stop", status.remaining - 1, null, null, null),
            )
        }
    }

    private data class StreamRequest(
        val conversationID: String,
        val clientMessageID: String,
        val text: String,
        val context: GradeyAIContextSnapshot,
        val locale: String,
    )

    private companion object {
        fun status() = GradeyAIStatus(
            enabled = true,
            consentRequired = false,
            termsVersion = "1",
            dailyLimit = 5,
            dailyUsed = 2,
            remaining = 3,
        )

        fun context() = GradeyAIContextSnapshot(
            schoolScope = "scope",
            generatedAtEpochMillis = 1_700_000_000_000,
            isStale = false,
            unavailableSections = emptyList(),
            subjects = emptyList(),
            trends = emptyList(),
            timetable = emptyList(),
        )

        fun conversation(id: String, title: String) = GradeyAIConversation(
            id = id,
            schoolScope = "scope",
            title = title,
            createdAtEpochMillis = 1_700_000_000_000,
            updatedAtEpochMillis = 1_700_000_000_000,
        )

        fun message(
            id: String,
            role: GradeyAIMessageRole,
            content: String,
            status: GradeyAIMessageStatus,
        ) = GradeyAIMessage(
            id = id,
            conversationID = "created",
            role = role,
            content = content,
            status = status,
            createdAtEpochMillis = 1_700_000_000_000,
        )
    }
}
