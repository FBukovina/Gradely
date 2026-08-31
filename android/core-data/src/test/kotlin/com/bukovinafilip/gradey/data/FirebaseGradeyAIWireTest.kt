package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyAIErrorClassifier
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.model.GradeyAIContextSection
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAILessonChangeKind
import com.bukovinafilip.gradey.model.GradeyAILessonContext
import com.bukovinafilip.gradey.model.GradeyAIMessageRole
import com.bukovinafilip.gradey.model.GradeyAIMessageStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class FirebaseGradeyAIWireTest {
    @Test
    fun `conversation list accepts flexible keys times and map containers`() {
        val conversations = FirebaseGradeyAIWire.decodeConversations(
            mapOf(
                "chats" to mapOf(
                    "older" to mapOf(
                        "id" to "older",
                        "school_scope" to "school",
                        "title" to "Older",
                        "created_at" to 1_700_000_000,
                        "updated_at" to "2023-11-14T22:13:21Z",
                    ),
                    "newer" to mapOf(
                        "chatId" to "newer",
                        "schoolScope" to "school",
                        "title" to "Newer",
                        "createdAt" to 1_700_000_000_000,
                        "updatedAt" to 1_700_000_002_000,
                        "lastMessageAt" to mapOf("_seconds" to 1_700_000_003, "_nanoseconds" to 0),
                    ),
                ),
            ),
        )

        assertThat(conversations.map { it.id }).containsExactly("newer", "older").inOrder()
        assertThat(conversations.first().createdAtEpochMillis).isEqualTo(1_700_000_000_000)
        assertThat(conversations.first().lastMessageAtEpochMillis).isEqualTo(1_700_000_003_000)
        assertThat(conversations.last().updatedAtEpochMillis).isEqualTo(1_700_000_001_000)
    }

    @Test
    fun `conversation list without a collection is malformed instead of empty`() {
        val error = assertThrows(GradeyAIException::class.java) {
            FirebaseGradeyAIWire.decodeConversations(mapOf("status" to emptyMap<String, Any>()))
        }

        assertThat(error.kind).isEqualTo(GradeyAIErrorKind.MALFORMED_RESPONSE)
    }

    @Test
    fun `mutations require an explicit successful confirmation`() {
        FirebaseGradeyAIWire.requireSuccessfulMutation(mapOf("success" to true), "consent revocation")

        listOf<Any?>(null, "invalid", emptyMap<String, Any>(), mapOf("success" to false)).forEach { payload ->
            val error = assertThrows(GradeyAIException::class.java) {
                FirebaseGradeyAIWire.requireSuccessfulMutation(payload, "consent revocation")
            }
            assertThat(error.kind).isEqualTo(GradeyAIErrorKind.MALFORMED_RESPONSE)
        }
    }

    @Test
    fun `detail decodes aliases statuses and sorts messages`() {
        val detail = FirebaseGradeyAIWire.decodeConversationDetail(
            payload = mapOf(
                "conversation" to mapOf(
                    "id" to "chat",
                    "schoolScope" to "scope",
                    "title" to "Math",
                    "createdAt" to 1_000,
                    "updatedAt" to 2_000,
                ),
                "history" to mapOf(
                    "assistant" to mapOf(
                        "id" to "assistant",
                        "chat_id" to "chat",
                        "role" to "assistant",
                        "text" to "Answer",
                        "state" to "completed",
                        "created_at" to 4_000,
                    ),
                    "user" to mapOf(
                        "id" to "user",
                        "client_message_id" to "user",
                        "role" to "user",
                        "content" to "Question",
                        "status" to "pending",
                        "created_at" to 3_000,
                    ),
                ),
            ),
            fallbackConversationID = "chat",
        )

        assertThat(detail.conversation.id).isEqualTo("chat")
        assertThat(detail.messages.map { it.id }).containsExactly("user", "assistant").inOrder()
        assertThat(detail.messages.first().conversationID).isEqualTo("chat")
        assertThat(detail.messages.first().role).isEqualTo(GradeyAIMessageRole.USER)
        assertThat(detail.messages.first().status).isEqualTo(GradeyAIMessageStatus.STREAMING)
        assertThat(detail.messages.last().status).isEqualTo(GradeyAIMessageStatus.COMPLETE)
    }

    @Test
    fun `stream decoder covers start delta done and failed contracts`() {
        val start = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf(
                "type" to "started",
                "assistantMessageID" to "assistant",
                "status" to mapOf("remaining" to 4),
            ),
            "chat",
        )
        val delta = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf("type" to "delta", "text" to "Hello"),
            "chat",
        )
        val done = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf(
                "type" to "completed",
                "status" to mapOf("remaining" to 3),
                "usage" to mapOf("inputTokens" to 11, "outputTokens" to 7),
                "message" to mapOf(
                    "id" to "assistant",
                    "chatID" to "chat",
                    "role" to "assistant",
                    "content" to "Hello",
                    "status" to "complete",
                    "createdAt" to 5_000,
                ),
            ),
            "chat",
        )
        val failed = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf(
                "type" to "failed",
                "code" to "over_limit",
                "message" to "Daily limit reached",
                "retryable" to false,
                "status" to mapOf("remaining" to 0),
            ),
            "chat",
        )

        assertThat(start).isEqualTo(GradeyAIStreamEvent.Start("assistant", 4))
        assertThat(delta).isEqualTo(GradeyAIStreamEvent.Delta("Hello"))
        assertThat((done as GradeyAIStreamEvent.Done).remaining).isEqualTo(3)
        assertThat(done.inputTokens).isEqualTo(11)
        assertThat(done.persistedMessage?.content).isEqualTo("Hello")
        assertThat(failed).isEqualTo(
            GradeyAIStreamEvent.Error("over_limit", "Daily limit reached", false, 0),
        )
    }

    @Test
    fun `malformed terminal event is classified rather than silently accepted`() {
        val error = assertThrows(GradeyAIException::class.java) {
            FirebaseGradeyAIWire.decodeStreamEvent(
                mapOf("type" to "completed", "status" to emptyMap<String, Any>()),
                "chat",
            )
        }

        assertThat(error.kind).isEqualTo(GradeyAIErrorKind.MALFORMED_RESPONSE)
        assertThat(error.retryable).isFalse()
    }

    @Test
    fun `completed stream ignores malformed optional persisted message so deltas remain usable`() {
        val delta = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf("type" to "delta", "text" to "Streamed answer"),
            "chat",
        )
        val done = FirebaseGradeyAIWire.decodeStreamEvent(
            mapOf(
                "type" to "completed",
                "status" to mapOf("remaining" to 2),
                "usage" to mapOf("inputTokens" to 5, "outputTokens" to 3),
                "message" to mapOf(
                    "conversationID" to "chat",
                    "role" to "assistant",
                    "content" to "Malformed because the identifier is missing",
                ),
            ),
            "chat",
        )

        assertThat(delta).isEqualTo(GradeyAIStreamEvent.Delta("Streamed answer"))
        assertThat(done).isEqualTo(
            GradeyAIStreamEvent.Done(
                finishReason = "stop",
                remaining = 2,
                inputTokens = 5,
                outputTokens = 3,
                persistedMessage = null,
            ),
        )
    }

    @Test
    fun `stream request trims prompt preserves identity and stays within limits`() {
        val payload = FirebaseGradeyAIRequestBuilder.streamPayload(
            conversationID = "chat",
            clientMessageID = "client",
            text = "  Explain this  ",
            locale = "cs-CZ",
            context = context(lessons = 3),
            gradeyAccountID = "account",
        )

        assertThat(payload["chatID"]).isEqualTo("chat")
        assertThat(payload["clientMessageID"]).isEqualTo("client")
        assertThat(payload["text"]).isEqualTo("Explain this")
        assertThat(payload["locale"]).isEqualTo("cs-CZ")
        assertThat(payload["schoolScope"]).isEqualTo("scope")
        assertThat(payload["gradey_account_id"]).isEqualTo("account")
        assertThat(FirebaseGradeyAIRequestBuilder.encodedSize(payload))
            .isAtMost(FirebaseGradeyAIRequestBuilder.MaximumRequestBytes)
    }

    @Test
    fun `context minimizer drops lessons before core metadata`() {
        val minimized = FirebaseGradeyAIRequestBuilder.constrainedContext(
            snapshot = context(lessons = 20, descriptionSize = 1_000),
            maximumBytes = 2_000,
        )

        assertThat(FirebaseGradeyAIRequestBuilder.encodedSize(minimized)).isAtMost(2_000)
        assertThat(minimized["schoolScope"]).isEqualTo("scope")
        assertThat(minimized["generatedAt"]).isEqualTo(1_700_000_000_000.0)
        assertThat((minimized["timetable"] as List<*>).size).isLessThan(20)
    }

    @Test
    fun `invalid and oversized prompts have explicit classifications`() {
        val blank = assertThrows(GradeyAIException::class.java) {
            FirebaseGradeyAIRequestBuilder.streamPayload("chat", "client", "  ", "en", context(), null)
        }
        val long = assertThrows(GradeyAIException::class.java) {
            FirebaseGradeyAIRequestBuilder.streamPayload(
                "chat",
                "client",
                "x".repeat(FirebaseGradeyAIRequestBuilder.MaximumPromptLength + 1),
                "en",
                context(),
                null,
            )
        }

        assertThat(blank.kind).isEqualTo(GradeyAIErrorKind.INVALID_PROMPT)
        assertThat(long.kind).isEqualTo(GradeyAIErrorKind.INVALID_PROMPT)
    }

    @Test
    fun `server classifier distinguishes auth context limit and oversize failures`() {
        assertThat(GradeyAIErrorClassifier.server("unauthenticated", "No session", true).kind)
            .isEqualTo(GradeyAIErrorKind.UNAUTHENTICATED)
        assertThat(GradeyAIErrorClassifier.server("no_context", "Missing", false).kind)
            .isEqualTo(GradeyAIErrorKind.NO_CONTEXT)
        assertThat(GradeyAIErrorClassifier.server("over_limit", "Limit", false).kind)
            .isEqualTo(GradeyAIErrorKind.LIMIT_REACHED)
        assertThat(GradeyAIErrorClassifier.server("invalid_argument", "Context too large", false).kind)
            .isEqualTo(GradeyAIErrorKind.REQUEST_TOO_LARGE)
        assertThat(GradeyAIErrorClassifier.server("unavailable", "Down", true).kind)
            .isEqualTo(GradeyAIErrorKind.SERVER)
    }

    @Test
    fun `generic Firebase resource exhaustion stays retryable unless daily limit code is explicit`() {
        val generic = GradeyAIErrorClassifier.server(
            code = "resource_exhausted",
            message = "Daily limit reached",
            retryable = true,
        )

        assertThat(generic.kind).isEqualTo(GradeyAIErrorKind.SERVER)
        assertThat(generic.retryable).isTrue()
        listOf("over_limit", "daily_limit", "limit_reached").forEach { code ->
            val dailyLimit = GradeyAIErrorClassifier.server(
                code = code,
                message = "Daily limit reached",
                retryable = false,
            )
            assertThat(dailyLimit.kind).isEqualTo(GradeyAIErrorKind.LIMIT_REACHED)
            assertThat(dailyLimit.retryable).isFalse()
        }
    }

    private fun context(
        lessons: Int = 0,
        descriptionSize: Int = 0,
    ) = GradeyAIContextSnapshot(
        schoolScope = "scope",
        generatedAtEpochMillis = 1_700_000_000_000,
        isStale = lessons == 0,
        unavailableSections = if (lessons == 0) listOf(GradeyAIContextSection.TIMETABLE) else emptyList(),
        subjects = emptyList(),
        trends = emptyList(),
        timetable = (0 until lessons).map { index ->
            GradeyAILessonContext(
                id = "lesson-$index",
                date = "2026-09-01",
                subject = "Mathematics",
                subjectAbbreviation = "M",
                beginsAt = "08:00",
                endsAt = "08:45",
                teacher = "Teacher",
                room = "101",
                groups = listOf("A"),
                changeKind = GradeyAILessonChangeKind.NONE,
                changeDescription = "x".repeat(descriptionSize),
            )
        },
    )
}
