package com.bukovinafilip.gradey.feature.auth

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OnboardingUpgradeSupportScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun schoolAndMealsFailuresRenderIndependentRetryActions() {
        val schoolRetries = AtomicInteger(0)
        val mealsRetries = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingUpgradeSupportScreen(
                    schoolCloudLinkFailed = true,
                    schoolCloudLinkErrorMessage = "School sync failed",
                    mealsCloudLinkFailed = true,
                    mealsCloudLinkErrorMessage = "Meals sync failed",
                    onRetrySchoolCloudLink = { schoolRetries.incrementAndGet() },
                    onRetryMealsCloudLink = { mealsRetries.incrementAndGet() },
                    onFinish = {},
                )
            }
        }

        composeRule.onNodeWithText(context.getString(R.string.onboarding_sync_warning_school))
            .assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.onboarding_sync_warning_meals))
            .performScrollTo()
            .assertIsDisplayed()

        val retryLabel = context.getString(R.string.onboarding_sync_warning_retry)
        composeRule.onAllNodesWithText(retryLabel).assertCountEquals(2)
        composeRule.onNodeWithTag(ONBOARDING_UPGRADE_SCHOOL_RETRY_TEST_TAG)
            .performScrollTo()
            .performClick()
        composeRule.runOnIdle {
            assertEquals(1, schoolRetries.get())
            assertEquals(0, mealsRetries.get())
        }
        composeRule.onNodeWithTag(ONBOARDING_UPGRADE_MEALS_RETRY_TEST_TAG)
            .performScrollTo()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(1, schoolRetries.get())
            assertEquals(1, mealsRetries.get())
        }
    }

    @Test
    fun finishRequiresCompletedMigrationAndNoActiveWork() {
        val canFinish = mutableStateOf(false)
        val isWorking = mutableStateOf(false)
        val finishes = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingUpgradeSupportScreen(
                    canFinish = canFinish.value,
                    isWorking = isWorking.value,
                    onFinish = { finishes.incrementAndGet() },
                )
            }
        }

        val finishLabel = context.getString(R.string.onboarding_upgrade_support_continue)
        composeRule.onNodeWithText(finishLabel)
            .performScrollTo()
            .assertIsNotEnabled()

        composeRule.runOnIdle { canFinish.value = true }
        composeRule.onNodeWithText(finishLabel)
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        composeRule.runOnIdle { assertEquals(1, finishes.get()) }

        composeRule.runOnIdle { isWorking.value = true }
        composeRule.onNodeWithText(finishLabel)
            .performScrollTo()
            .assertIsNotEnabled()
    }

    @Test
    fun supportStepShowsProgressWithoutBackAction() {
        composeRule.setContent {
            GradeyTheme {
                OnboardingUpgradeSupportScreen(
                    progressPosition = 2,
                    progressCount = 2,
                    onFinish = {},
                )
            }
        }

        composeRule.onNodeWithText(context.getString(R.string.onboarding_progress, 2, 2))
            .assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.auth_back))
            .assertDoesNotExist()
    }
}
