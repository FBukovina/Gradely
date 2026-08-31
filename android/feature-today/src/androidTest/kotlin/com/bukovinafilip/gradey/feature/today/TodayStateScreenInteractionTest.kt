package com.bukovinafilip.gradey.feature.today

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
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TodayStateScreenInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun initialLoadingShowsLoadingCopyWithoutRetry() {
        val retries = AtomicInteger(0)
        setScreen(
            state = TodayPresentationState.INITIAL_LOADING,
            errorMessage = null,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.today_loading)).assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.today_loading_subtitle)).assertIsDisplayed()
        retryNode().assertDoesNotExist()
        composeRule.runOnIdle { assertEquals(0, retries.get()) }
    }

    @Test
    fun firstLoadErrorShowsSuppliedMessageAndRetriesExactlyOnce() {
        val retries = AtomicInteger(0)
        val errorMessage = "offline"
        setScreen(
            state = TodayPresentationState.FIRST_LOAD_ERROR,
            errorMessage = errorMessage,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.today_load_failed)).assertIsDisplayed()
        composeRule.onNodeWithText(errorMessage).assertIsDisplayed()
        assertRetryButtonAndClick()
        composeRule.runOnIdle { assertEquals(1, retries.get()) }
    }

    @Test
    fun firstLoadErrorWithoutMessageShowsNoDataFallbackAndRetriesExactlyOnce() {
        val retries = AtomicInteger(0)
        setScreen(
            state = TodayPresentationState.FIRST_LOAD_ERROR,
            errorMessage = null,
            onRetry = { retries.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.today_no_data)).assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.today_no_data_subtitle)).assertIsDisplayed()
        assertRetryButtonAndClick()
        composeRule.runOnIdle { assertEquals(1, retries.get()) }
    }

    private fun setScreen(
        state: TodayPresentationState,
        errorMessage: String?,
        onRetry: () -> Unit,
    ) {
        composeRule.setContent {
            GradeyTheme {
                TodayStateScreen(
                    state = state,
                    errorMessage = errorMessage,
                    onRetry = onRetry,
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

    private fun retryNode() = composeRule.onNodeWithText(context.getString(R.string.today_retry))

    private companion object {
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
