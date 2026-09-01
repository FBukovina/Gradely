package com.bukovinafilip.gradey.feature.gradeyai

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.Flow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyAIEntryGateTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun localOnlyMissingAccountRendersUnavailableWithoutCallingService() {
        verifyBlockedEntry(
            isGradeyCloudConfigured = false,
            expectedTitle = context.getString(R.string.gradey_ai_not_configured_title),
        )
    }

    @Test
    fun configuredCloudMissingAccountRequiresSignInWithoutCallingService() {
        verifyBlockedEntry(
            isGradeyCloudConfigured = true,
            expectedTitle = context.getString(R.string.gradey_ai_sign_in_title),
        )
    }

    private fun verifyBlockedEntry(
        isGradeyCloudConfigured: Boolean,
        expectedTitle: String,
    ) {
        val repository = NoCallRepository()
        val contextBuilder = NoCallContextBuilder()

        composeRule.setContent {
            GradeyTheme {
                GradeyAIScreen(
                    repository = repository,
                    contextBuilder = contextBuilder,
                    isGradeyCloudConfigured = isGradeyCloudConfigured,
                    hasGradeyAccount = false,
                    isGuestMode = false,
                    onOpenAccount = {},
                    onClose = {},
                )
            }
        }

        composeRule.onNodeWithText(expectedTitle).assertIsDisplayed()
        composeRule.runOnIdle {
            assertEquals(0, repository.calls.get())
            assertEquals(0, contextBuilder.calls.get())
        }
    }

    private class NoCallRepository : GradeyAIRepository {
        override val isConfigured = true
        val calls = AtomicInteger(0)

        override suspend fun loadStatus(): GradeyAIStatus = unexpectedCall()
        override suspend fun acceptConsent(): GradeyAIConsent = unexpectedCall()
        override suspend fun revokeConsent(): Unit = unexpectedCall()
        override suspend fun listConversations(schoolScope: String): List<GradeyAIConversation> = unexpectedCall()
        override suspend fun createConversation(schoolScope: String, title: String?): GradeyAIConversation =
            unexpectedCall()
        override suspend fun loadConversation(id: String): GradeyAIConversationDetail = unexpectedCall()
        override suspend fun deleteConversation(id: String): Unit = unexpectedCall()
        override suspend fun deleteAllConversations(schoolScope: String): Unit = unexpectedCall()
        override fun streamReply(
            conversationID: String,
            clientMessageID: String,
            text: String,
            context: GradeyAIContextSnapshot,
            locale: String,
        ): Flow<GradeyAIStreamEvent> = unexpectedCall()

        private fun unexpectedCall(): Nothing {
            calls.incrementAndGet()
            error("Blocked Gradey AI entry called the live repository")
        }
    }

    private class NoCallContextBuilder : GradeyAIContextBuilding {
        val calls = AtomicInteger(0)

        override suspend fun currentSchoolScope(): String = unexpectedCall()
        override suspend fun cachedContext(): GradeyAIContextSnapshot? = unexpectedCall()
        override suspend fun refreshContext(): GradeyAIContextSnapshot = unexpectedCall()

        private fun unexpectedCall(): Nothing {
            calls.incrementAndGet()
            error("Blocked Gradey AI entry built school context")
        }
    }
}
