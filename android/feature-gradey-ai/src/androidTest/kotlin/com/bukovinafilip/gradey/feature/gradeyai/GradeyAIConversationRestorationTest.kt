package com.bukovinafilip.gradey.feature.gradeyai

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.text.AnnotatedString
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyAIConversationRestorationTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun activityStopAndStartDeliverOneAuthoritativeForegroundBootstrap() {
        val repository = RestorationRepository()
        val contextBuilder = RestorationContextBuilder()
        composeRule.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }

        waitForText(ConversationTitle)
        composeRule.runOnIdle {
            assertEquals(1, repository.statusCalls.get())
        }

        composeRule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        assertEquals(1, repository.statusCalls.get())

        composeRule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        composeRule.waitUntil(timeoutMillis = 10_000) {
            repository.statusCalls.get() == 2
        }
        assertEquals(2, repository.statusCalls.get())
    }

    @Test
    fun openConversationAndUnsentDraftSurviveStateRestorationWithoutSending() {
        val repository = RestorationRepository()
        val contextBuilder = RestorationContextBuilder()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }

        waitForText(ConversationTitle)
        composeRule.onNodeWithText(ConversationTitle).performClick()
        waitForComposer()
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
            .performTextReplacement(UnsentDraft)
        val loadsBeforeRestore = repository.loadedConversationCalls.get()

        restorationTester.emulateSavedInstanceStateRestore()

        waitForComposer()
        composeRule.onNodeWithText(ConversationTitle).assertIsDisplayed()
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG).assert(
            SemanticsMatcher.expectValue(
                SemanticsProperties.EditableText,
                AnnotatedString(UnsentDraft),
            ),
        )
        composeRule.runOnIdle {
            assertEquals(loadsBeforeRestore + 1, repository.loadedConversationCalls.get())
            assertEquals(0, repository.streamCalls.get())
        }
    }

    @Test
    fun restoredTitleAndDraftStayHiddenUntilScopeValidationSucceeds() {
        val repository = RestorationRepository()
        val contextBuilder = RestorationContextBuilder()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }
        waitForText(ConversationTitle)
        composeRule.onNodeWithText(ConversationTitle).performClick()
        waitForComposer()
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
            .performTextReplacement(UnsentDraft)
        val loadsBeforeRestore = repository.loadedConversationCalls.get()
        composeRule.runOnIdle {
            contextBuilder.scopeFailure = GradeyAIContextException(GradeyAIContextError.NO_SCHOOL_ACCOUNT)
        }

        restorationTester.emulateSavedInstanceStateRestore()

        waitForText(retryLabel)
        composeRule.onNodeWithText(ConversationTitle).assertDoesNotExist()
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG).assertDoesNotExist()
        composeRule.runOnIdle {
            assertEquals(loadsBeforeRestore, repository.loadedConversationCalls.get())
            contextBuilder.scopeFailure = null
        }
        composeRule.onNodeWithText(retryLabel).performClick()

        waitForComposer()
        composeRule.onNodeWithText(ConversationTitle).assertIsDisplayed()
        assertComposerText(UnsentDraft)
        composeRule.runOnIdle {
            assertEquals(loadsBeforeRestore + 1, repository.loadedConversationCalls.get())
        }
    }

    @Test
    fun repositoryOnlyAndContextOnlyReplacementEachCreateAFreshController() {
        val firstRepository = RestorationRepository()
        val firstBuilder = RestorationContextBuilder()
        val secondConversation = Conversation.copy(
            id = "second-conversation",
            title = "Second repository conversation",
        )
        val secondRepository = RestorationRepository(secondConversation)
        val secondBuilder = RestorationContextBuilder()
        val repositoryState = mutableStateOf<GradeyAIRepository>(firstRepository)
        val builderState = mutableStateOf<GradeyAIContextBuilding>(firstBuilder)
        composeRule.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repositoryState.value,
                    contextBuilder = builderState.value,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }
        waitForText(ConversationTitle)

        composeRule.runOnIdle {
            repositoryState.value = secondRepository
        }

        waitForText(secondConversation.title)
        composeRule.onNodeWithText(ConversationTitle).assertDoesNotExist()
        composeRule.runOnIdle {
            assertEquals(1, firstRepository.statusCalls.get())
            assertEquals(1, secondRepository.statusCalls.get())
            builderState.value = secondBuilder
        }
        composeRule.waitUntil(timeoutMillis = 10_000) {
            secondRepository.statusCalls.get() == 2
        }
        composeRule.runOnIdle {
            assertEquals(1, firstRepository.statusCalls.get())
            assertEquals(2, secondRepository.statusCalls.get())
        }
    }

    @Test
    fun oversizedLiveDraftIsPreservedAndItsRestoredCopyIsBounded() {
        val repository = RestorationRepository()
        val contextBuilder = RestorationContextBuilder()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }
        waitForText(ConversationTitle)
        composeRule.onNodeWithText(ConversationTitle).performClick()
        waitForComposer()
        val oversized = "x".repeat(GRADEY_AI_MAXIMUM_PROMPT_LENGTH + 500)
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
            .performTextReplacement(oversized)
        assertComposerText(oversized)

        restorationTester.emulateSavedInstanceStateRestore()

        waitForComposer()
        assertComposerText("x".repeat(GRADEY_AI_MAXIMUM_PROMPT_LENGTH))
    }

    @Test
    fun suspendedDraftChatCreateRoundTripsPendingPromptThroughTheSaver() {
        val repository = RestorationRepository(conversation = null, suspendCreate = true)
        val contextBuilder = RestorationContextBuilder()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }
        waitForText(newChatLabel)
        composeRule.onNodeWithText(newChatLabel).performClick()
        waitForComposer()
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
            .performTextReplacement(PendingCreatePrompt)
        composeRule.onNodeWithContentDescription(sendLabel).performClick()
        composeRule.waitUntil(timeoutMillis = 10_000) {
            repository.createCalls.get() == 1
        }

        restorationTester.emulateSavedInstanceStateRestore()

        waitForComposer()
        assertComposerText(PendingCreatePrompt)
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
            .performTextReplacement(EditedPendingCreatePrompt)

        restorationTester.emulateSavedInstanceStateRestore()

        waitForComposer()
        assertComposerText(EditedPendingCreatePrompt)
        composeRule.runOnIdle {
            assertEquals(1, repository.createCalls.get())
            assertEquals(0, repository.streamCalls.get())
        }
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForComposer() {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithTag(GRADEY_AI_COMPOSER_TEST_TAG)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    private fun assertComposerText(expected: String) {
        composeRule.onNodeWithTag(GRADEY_AI_COMPOSER_TEST_TAG).assert(
            SemanticsMatcher.expectValue(
                SemanticsProperties.EditableText,
                AnnotatedString(expected),
            ),
        )
    }

    private val retryLabel: String
        get() = InstrumentationRegistry.getInstrumentation().targetContext.getString(R.string.gradey_ai_retry)

    private val newChatLabel: String
        get() = InstrumentationRegistry.getInstrumentation().targetContext.getString(R.string.gradey_ai_new_chat)

    private val sendLabel: String
        get() = InstrumentationRegistry.getInstrumentation().targetContext.getString(R.string.gradey_ai_send)

    private class RestorationRepository(
        private val conversation: GradeyAIConversation? = Conversation,
        private val suspendCreate: Boolean = false,
    ) : GradeyAIRepository {
        override val isConfigured = true
        val loadedConversationCalls = AtomicInteger(0)
        val streamCalls = AtomicInteger(0)
        val statusCalls = AtomicInteger(0)
        val createCalls = AtomicInteger(0)

        override suspend fun loadStatus(): GradeyAIStatus {
            statusCalls.incrementAndGet()
            return Status
        }

        override suspend fun acceptConsent(): GradeyAIConsent = unexpectedCall()

        override suspend fun revokeConsent(): Unit = unexpectedCall()

        override suspend fun listConversations(schoolScope: String): List<GradeyAIConversation> =
            listOfNotNull(conversation).filter { it.schoolScope == schoolScope }

        override suspend fun createConversation(
            schoolScope: String,
            title: String?,
        ): GradeyAIConversation {
            createCalls.incrementAndGet()
            if (suspendCreate) awaitCancellation()
            return unexpectedCall()
        }

        override suspend fun loadConversation(id: String): GradeyAIConversationDetail {
            loadedConversationCalls.incrementAndGet()
            val selected = checkNotNull(conversation)
            check(id == selected.id)
            return GradeyAIConversationDetail(selected, emptyList())
        }

        override suspend fun deleteConversation(id: String): Unit = unexpectedCall()

        override suspend fun deleteAllConversations(schoolScope: String): Unit = unexpectedCall()

        override fun streamReply(
            conversationID: String,
            clientMessageID: String,
            text: String,
            context: GradeyAIContextSnapshot,
            locale: String,
        ): Flow<GradeyAIStreamEvent> {
            streamCalls.incrementAndGet()
            error("State restoration must not send the draft")
        }

        private fun unexpectedCall(): Nothing = error("Unexpected destructive Gradey AI call")
    }

    private class RestorationContextBuilder(
        private val schoolScope: String = SchoolScope,
    ) : GradeyAIContextBuilding {
        var scopeFailure: Throwable? = null

        override suspend fun currentSchoolScope(): String {
            scopeFailure?.let { throw it }
            return schoolScope
        }

        override suspend fun cachedContext(): GradeyAIContextSnapshot = Context.copy(schoolScope = schoolScope)

        override suspend fun refreshContext(): GradeyAIContextSnapshot = Context.copy(schoolScope = schoolScope)
    }

    private companion object {
        const val SchoolScope = "school-scope"
        const val ConversationTitle = "Existing conversation"
        const val UnsentDraft = "Keep this exact unsent draft"
        const val PendingCreatePrompt = "Pending prompt through saver"
        const val EditedPendingCreatePrompt = "Latest edited pending prompt"
        val Conversation = GradeyAIConversation(
            id = "conversation-id",
            schoolScope = SchoolScope,
            title = ConversationTitle,
            createdAtEpochMillis = 1_700_000_000_000,
            updatedAtEpochMillis = 1_700_000_001_000,
        )
        val Status = GradeyAIStatus(
            enabled = true,
            consentRequired = false,
            termsVersion = "1",
            dailyLimit = 5,
            dailyUsed = 1,
            remaining = 4,
        )
        val Context = GradeyAIContextSnapshot(
            schoolScope = SchoolScope,
            generatedAtEpochMillis = 1_700_000_000_000,
            isStale = false,
            unavailableSections = emptyList(),
            subjects = emptyList(),
            trends = emptyList(),
            timetable = emptyList(),
        )
    }
}
