package com.bukovinafilip.gradey.feature.gradeyai

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.Flow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyAIConversationActionsInteractionTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun rowDeleteCancelAndConfirmNeverOpenTheConversation() {
        val repository = ActionsRepository(listOf(FirstConversation))
        setScreen(repository)
        waitForText(FirstConversation.title)

        composeRule.onNodeWithContentDescription(deleteChatAction).performClick()
        assertDeleteChatDialog()
        composeRule.onNodeWithText(cancelAction).performClick()
        waitForTextToDisappear(deleteChatTitle)

        composeRule.runOnIdle {
            assertEquals(0, repository.loadConversationCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(0, repository.revokeCalls.get())
        }
        composeRule.onNodeWithText(FirstConversation.title).assertIsDisplayed()

        composeRule.onNodeWithContentDescription(deleteChatAction).performClick()
        composeRule.onNodeWithText(deleteChatAction).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            repository.deletedConversationIDs.size == 1
        }

        composeRule.runOnIdle {
            assertEquals(listOf(FirstConversation.id), repository.deletedConversationIDs)
            assertEquals(0, repository.loadConversationCalls.get())
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(0, repository.revokeCalls.get())
        }
        waitForTextToDisappear(FirstConversation.title)
        composeRule.onNodeWithText(emptyTitle).assertIsDisplayed()
    }

    @Test
    fun conversationBackReturnsToHistoryWithoutClosingTheScreen() {
        val repository = ActionsRepository(listOf(FirstConversation))
        val closeCalls = AtomicInteger(0)
        setScreen(repository, onClose = closeCalls::incrementAndGet)
        waitForText(FirstConversation.title)

        composeRule.onNodeWithText(FirstConversation.title).performClick()
        waitForContentDescription(backAction)
        composeRule.onNodeWithContentDescription(backAction).performClick()

        waitForText(FirstConversation.title)
        composeRule.onNodeWithContentDescription(backAction).assertDoesNotExist()
        composeRule.onNodeWithContentDescription(deleteChatAction).assertIsDisplayed()
        composeRule.runOnIdle {
            assertEquals(1, repository.loadConversationCalls.get())
            assertEquals(0, closeCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
        }
    }

    @Test
    fun currentConversationDeleteUsesTheExactIDAndReturnsToTheEmptyHistory() {
        val repository = ActionsRepository(listOf(FirstConversation))
        setScreen(repository)
        waitForText(FirstConversation.title)
        composeRule.onNodeWithText(FirstConversation.title).performClick()
        waitForContentDescription(backAction)

        composeRule.onNodeWithContentDescription(optionsAction).performClick()
        composeRule.onNodeWithText(deleteChatAction).performClick()
        assertDeleteChatDialog()
        composeRule.onNodeWithText(deleteChatAction).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            repository.deletedConversationIDs.size == 1
        }

        waitForText(emptyTitle)
        composeRule.runOnIdle {
            assertEquals(listOf(FirstConversation.id), repository.deletedConversationIDs)
            assertEquals(1, repository.loadConversationCalls.get())
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(0, repository.revokeCalls.get())
        }
        composeRule.onNodeWithContentDescription(backAction).assertDoesNotExist()
    }

    @Test
    fun deleteAllIsDisabledForEmptyHistory() {
        val repository = ActionsRepository(emptyList())
        setScreen(repository)
        waitForText(emptyTitle)

        composeRule.onNodeWithContentDescription(optionsAction).performClick()
        composeRule.onNodeWithText(deleteAllAction)
            .assertIsNotEnabled()
            .performClick()

        composeRule.onNodeWithText(deleteAllTitle).assertDoesNotExist()
        composeRule.runOnIdle {
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
            assertEquals(0, repository.revokeCalls.get())
        }
    }

    @Test
    fun deleteAllCancelThenConfirmDeletesOnlyTheCurrentSchoolScope() {
        val repository = ActionsRepository(listOf(FirstConversation, SecondConversation))
        setScreen(repository)
        waitForText(FirstConversation.title)
        waitForText(SecondConversation.title)

        openOptionsAction(deleteAllAction)
        assertDangerousDialog(deleteAllTitle, deleteAllMessage)
        composeRule.onNodeWithText(cancelAction).performClick()
        waitForTextToDisappear(deleteAllTitle)
        composeRule.runOnIdle {
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
            assertEquals(0, repository.revokeCalls.get())
        }

        openOptionsAction(deleteAllAction)
        composeRule.onNodeWithText(deleteAllAction).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            repository.deleteAllCalls.get() == 1
        }

        waitForText(emptyTitle)
        composeRule.runOnIdle {
            assertEquals(listOf(SchoolScope), repository.deletedAllScopes)
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
            assertEquals(0, repository.revokeCalls.get())
        }
        composeRule.onNodeWithText(FirstConversation.title).assertDoesNotExist()
        composeRule.onNodeWithText(SecondConversation.title).assertDoesNotExist()
    }

    @Test
    fun revokeCancelThenConfirmClearsChatsWithoutCallingDeleteEndpoints() {
        val repository = ActionsRepository(listOf(FirstConversation, SecondConversation))
        setScreen(repository)
        waitForText(FirstConversation.title)

        openOptionsAction(revokeAction)
        assertDangerousDialog(revokeTitle, revokeMessage)
        composeRule.onNodeWithText(cancelAction).performClick()
        waitForTextToDisappear(revokeTitle)
        composeRule.runOnIdle {
            assertEquals(0, repository.revokeCalls.get())
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
        }
        composeRule.onNodeWithText(FirstConversation.title).assertIsDisplayed()

        openOptionsAction(revokeAction)
        composeRule.onNodeWithText(revokeAction).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            repository.revokeCalls.get() == 1
        }

        waitForText(consentTitle)
        composeRule.runOnIdle {
            assertEquals(1, repository.revokeCalls.get())
            assertEquals(0, repository.deleteAllCalls.get())
            assertEquals(emptyList<String>(), repository.deletedConversationIDs)
            assertEquals(emptyList<String>(), repository.deletedAllScopes)
        }
        composeRule.onNodeWithText(FirstConversation.title).assertDoesNotExist()
        composeRule.onNodeWithText(SecondConversation.title).assertDoesNotExist()
    }

    private fun setScreen(
        repository: ActionsRepository,
        onClose: () -> Unit = {},
    ) {
        composeRule.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = ActionsContextBuilder,
                    isGradeyCloudConfigured = true,
                    hasGradeyAccount = true,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = onClose,
                )
            }
        }
    }

    private fun openOptionsAction(action: String) {
        composeRule.onNodeWithContentDescription(optionsAction).performClick()
        composeRule.onNodeWithText(action).performClick()
    }

    private fun assertDeleteChatDialog() {
        assertDangerousDialog(deleteChatTitle, deleteChatMessage)
        composeRule.onNodeWithText(deleteChatAction).assertIsDisplayed()
        composeRule.onNodeWithText(cancelAction).assertIsDisplayed()
    }

    private fun assertDangerousDialog(title: String, message: String) {
        composeRule.onNodeWithText(title).assertIsDisplayed()
        composeRule.onNodeWithText(message).assertIsDisplayed()
        composeRule.onNodeWithText(cancelAction).assertIsDisplayed()
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForContentDescription(description: String) {
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            composeRule.onAllNodesWithContentDescription(description)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    private fun waitForTextToDisappear(text: String) {
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isEmpty()
        }
    }

    private val targetContext
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val deleteChatAction get() = targetContext.getString(R.string.gradey_ai_delete_chat_action)
    private val deleteChatTitle get() = targetContext.getString(R.string.gradey_ai_delete_chat_title)
    private val deleteChatMessage get() = targetContext.getString(R.string.gradey_ai_delete_chat_message)
    private val deleteAllAction get() = targetContext.getString(R.string.gradey_ai_delete_all_action)
    private val deleteAllTitle get() = targetContext.getString(R.string.gradey_ai_delete_all_title)
    private val deleteAllMessage get() = targetContext.getString(R.string.gradey_ai_delete_all_message)
    private val revokeAction get() = targetContext.getString(R.string.gradey_ai_revoke_action)
    private val revokeTitle get() = targetContext.getString(R.string.gradey_ai_revoke_title)
    private val revokeMessage get() = targetContext.getString(R.string.gradey_ai_revoke_message)
    private val cancelAction get() = targetContext.getString(R.string.gradey_ai_cancel)
    private val optionsAction get() = targetContext.getString(R.string.gradey_ai_options)
    private val backAction get() = targetContext.getString(R.string.gradey_ai_back)
    private val emptyTitle get() = targetContext.getString(R.string.gradey_ai_empty_title)
    private val consentTitle get() = targetContext.getString(R.string.gradey_ai_consent_title)

    private class ActionsRepository(
        conversations: List<GradeyAIConversation>,
    ) : GradeyAIRepository {
        override val isConfigured = true
        private val conversations = CopyOnWriteArrayList(conversations)
        val loadConversationCalls = AtomicInteger(0)
        val deletedConversationIDs = CopyOnWriteArrayList<String>()
        val deleteAllCalls = AtomicInteger(0)
        val deletedAllScopes = CopyOnWriteArrayList<String>()
        val revokeCalls = AtomicInteger(0)
        private var status = Status

        override suspend fun loadStatus(): GradeyAIStatus = status

        override suspend fun acceptConsent(): GradeyAIConsent = unexpectedCall()

        override suspend fun revokeConsent() {
            revokeCalls.incrementAndGet()
            conversations.clear()
            status = status.copy(consentRequired = true)
        }

        override suspend fun listConversations(schoolScope: String): List<GradeyAIConversation> =
            conversations.filter { it.schoolScope == schoolScope }

        override suspend fun createConversation(
            schoolScope: String,
            title: String?,
        ): GradeyAIConversation = unexpectedCall()

        override suspend fun loadConversation(id: String): GradeyAIConversationDetail {
            loadConversationCalls.incrementAndGet()
            val conversation = conversations.single { it.id == id }
            return GradeyAIConversationDetail(conversation, emptyList())
        }

        override suspend fun deleteConversation(id: String) {
            deletedConversationIDs += id
            conversations.removeAll { it.id == id }
        }

        override suspend fun deleteAllConversations(schoolScope: String) {
            deleteAllCalls.incrementAndGet()
            deletedAllScopes += schoolScope
            conversations.removeAll { it.schoolScope == schoolScope }
        }

        override fun streamReply(
            conversationID: String,
            clientMessageID: String,
            text: String,
            context: GradeyAIContextSnapshot,
            locale: String,
        ): Flow<GradeyAIStreamEvent> = unexpectedCall()

        private fun unexpectedCall(): Nothing = error("Unexpected Gradey AI action")
    }

    private object ActionsContextBuilder : GradeyAIContextBuilding {
        override suspend fun currentSchoolScope(): String = SchoolScope

        override suspend fun cachedContext(): GradeyAIContextSnapshot = Context

        override suspend fun refreshContext(): GradeyAIContextSnapshot = Context
    }

    private companion object {
        const val TimeoutMillis = 10_000L
        const val SchoolScope = "school-scope"
        val FirstConversation = conversation("first-conversation", "First conversation")
        val SecondConversation = conversation("second-conversation", "Second conversation")
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

        fun conversation(id: String, title: String) = GradeyAIConversation(
            id = id,
            schoolScope = SchoolScope,
            title = title,
            createdAtEpochMillis = 1_700_000_000_000,
            updatedAtEpochMillis = 1_700_000_001_000,
        )
    }
}
