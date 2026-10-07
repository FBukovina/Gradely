package com.bukovinafilip.gradey.feature.stravacz

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StravaCZFirstMenuLoadInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun initialMenuLoadShowsLoadingWithoutRetry() {
        val retries = AtomicInteger(0)
        setScreen(
            isLoading = true,
            errorMessage = null,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.stravacz_loading)).assertIsDisplayed()
        retryNode().assertDoesNotExist()
        composeRule.runOnIdle { assertEquals(0, retries.get()) }
    }

    @Test
    fun firstMenuErrorShowsSuppliedMessageAndRetriesExactlyOnce() {
        val retries = AtomicInteger(0)
        val errorMessage = "offline"
        setScreen(
            isLoading = false,
            errorMessage = errorMessage,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(errorMessage).assertIsDisplayed()
        assertRetryButtonAndClick()
        composeRule.runOnIdle { assertEquals(1, retries.get()) }
    }

    @Test
    fun firstMenuErrorWithoutMessageShowsFallbackAndRetriesExactlyOnce() {
        val retries = AtomicInteger(0)
        setScreen(
            isLoading = false,
            errorMessage = null,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.stravacz_empty_message))
            .assertIsDisplayed()
        assertRetryButtonAndClick()
        composeRule.runOnIdle { assertEquals(1, retries.get()) }
    }

    private fun setScreen(
        isLoading: Boolean,
        errorMessage: String?,
        onRetry: () -> Unit,
    ) {
        composeRule.setContent {
            GradeyTheme {
                StravaCZScreen(
                    session = TestSession,
                    menu = null,
                    isLoading = isLoading,
                    isRefreshing = false,
                    submittingMealID = null,
                    errorMessage = errorMessage,
                    onConnect = { _, _, _ -> },
                    onRefresh = onRetry,
                    onSetMeal = { _, _ -> },
                    onDisconnect = {},
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }
    }

    private fun assertRetryButtonAndClick() {
        retryNode()
            .assertIsDisplayed()
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertIsEnabled()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()
    }

    private fun retryNode() = composeRule.onNodeWithText(context.getString(R.string.stravacz_retry))

    private companion object {
        val TestSession = StravaCZStoredSession(
            sessionID = "session",
            serviceURL = "https://example.test",
            canteenNumber = "1234",
            username = "student",
        )
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
