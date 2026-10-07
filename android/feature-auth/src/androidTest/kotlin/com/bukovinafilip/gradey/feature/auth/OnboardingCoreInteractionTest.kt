package com.bukovinafilip.gradey.feature.auth

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.espresso.Espresso.pressBack
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OnboardingCoreInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun welcomeRoutesLanguageGetStartedAndLoginActions() {
        val language = mutableStateOf(AppLanguage.ENGLISH)
        val continueCount = AtomicInteger(0)
        val loginCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingWelcomeScreen(
                    appLanguage = language.value,
                    onAppLanguageChange = { language.value = it },
                    onContinue = { continueCount.incrementAndGet() },
                    onLogIn = { loginCount.incrementAndGet() },
                )
            }
        }

        composeRule.onNodeWithText(
            context.getString(com.bukovinafilip.gradey.ui.R.string.language_czech),
        ).performScrollTo().performClick()
        composeRule.runOnIdle { assertEquals(AppLanguage.CZECH, language.value) }

        composeRule.onNodeWithText(context.getString(R.string.onboarding_get_started))
            .performScrollTo()
            .performClick()
        composeRule.onNodeWithText(context.getString(R.string.onboarding_log_in))
            .performScrollTo()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(1, continueCount.get())
            assertEquals(1, loginCount.get())
        }
    }

    @Test
    fun notificationsRoutesEveryActionAndDisablesNavigationDuringWork() {
        val isWorking = mutableStateOf(false)
        val backCount = AtomicInteger(0)
        val enableCount = AtomicInteger(0)
        val notNowCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingNotificationsScreen(
                    onEnable = { enableCount.incrementAndGet() },
                    onNotNow = { notNowCount.incrementAndGet() },
                    onBack = { backCount.incrementAndGet() },
                    isWorking = isWorking.value,
                    progressPosition = 3,
                    progressCount = 4,
                )
            }
        }

        click(context.getString(R.string.auth_back))
        click(context.getString(R.string.onboarding_notifications_enable))
        click(context.getString(R.string.onboarding_notifications_not_now))
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            assertEquals(1, enableCount.get())
            assertEquals(1, notNowCount.get())
            isWorking.value = true
        }

        assertDisabled(context.getString(R.string.auth_back))
        assertDisabled(context.getString(R.string.onboarding_notifications_enable))
        assertDisabled(context.getString(R.string.onboarding_notifications_not_now))
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            assertEquals(1, enableCount.get())
            assertEquals(1, notNowCount.get())
        }
    }

    @Test
    fun notificationsSystemBackUsesThePreviousStepAndIsConsumedDuringWork() {
        val isWorking = mutableStateOf(false)
        val backCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingNotificationsScreen(
                    onEnable = {},
                    onNotNow = {},
                    onBack = { backCount.incrementAndGet() },
                    isWorking = isWorking.value,
                )
            }
        }

        pressBack()
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            isWorking.value = true
        }

        pressBack()
        composeRule.runOnIdle { assertEquals(1, backCount.get()) }
        composeRule.onNodeWithText(context.getString(R.string.onboarding_notifications_title))
            .assertIsDisplayed()
    }

    @Test
    fun readySystemBackUsesThePreviousStepAndIsConsumedDuringWork() {
        val isFinishing = mutableStateOf(false)
        val backCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingReadyScreen(
                    isGuestMode = false,
                    notificationsEnabled = false,
                    onFinish = {},
                    onBack = { backCount.incrementAndGet() },
                    isFinishing = isFinishing.value,
                )
            }
        }

        pressBack()
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            isFinishing.value = true
        }

        pressBack()
        composeRule.runOnIdle { assertEquals(1, backCount.get()) }
        composeRule.onNodeWithText(context.getString(R.string.onboarding_ready_title))
            .assertIsDisplayed()
    }

    @Test
    fun gradeyIdSystemBackUsesThePreviousStepAndIsConsumedDuringLoading() {
        val isLoading = mutableStateOf(false)
        val backCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                GradeyIdLoginScreen(
                    isLoading = isLoading.value,
                    onGoogleSignIn = {},
                    onOpenHelp = {},
                    onOpenGitHub = {},
                    onBack = { backCount.incrementAndGet() },
                )
            }
        }

        pressBack()
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            isLoading.value = true
        }

        pressBack()
        composeRule.runOnIdle { assertEquals(1, backCount.get()) }
        composeRule.onNodeWithText(context.getString(R.string.gradey_id_title))
            .assertIsDisplayed()
    }

    @Test
    fun readyRoutesRecoverySettingsFinishAndBackThenGatesAllActions() {
        val isFinishing = mutableStateOf(false)
        val backCount = AtomicInteger(0)
        val schoolRetryCount = AtomicInteger(0)
        val notificationRetryCount = AtomicInteger(0)
        val settingsCount = AtomicInteger(0)
        val finishCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                OnboardingReadyScreen(
                    isGuestMode = false,
                    notificationsEnabled = false,
                    onFinish = { finishCount.incrementAndGet() },
                    onBack = { backCount.incrementAndGet() },
                    schoolCloudLinkFailed = true,
                    schoolCloudLinkErrorMessage = SchoolFailure,
                    onRetrySchoolCloudLink = { schoolRetryCount.incrementAndGet() },
                    notificationSyncErrorMessage = NotificationFailure,
                    onRetryNotificationSync = { notificationRetryCount.incrementAndGet() },
                    showNotificationSettingsAction = true,
                    onOpenNotificationSettings = { settingsCount.incrementAndGet() },
                    isFinishing = isFinishing.value,
                    progressPosition = 4,
                    progressCount = 4,
                )
            }
        }

        composeRule.onNodeWithText(context.getString(R.string.onboarding_school_link_warning_body))
            .performScrollTo()
            .assert(liveRegionMatcher(LiveRegionMode.Polite))
        composeRule.onNodeWithText(context.getString(R.string.onboarding_notification_sync_warning_body))
            .performScrollTo()
            .assert(liveRegionMatcher(LiveRegionMode.Polite))

        click(context.getString(R.string.auth_back))
        click(context.getString(R.string.onboarding_upgrade_retry))
        click(context.getString(R.string.onboarding_notification_sync_retry))
        click(context.getString(R.string.onboarding_open_notification_settings))
        click(context.getString(R.string.onboarding_ready_open))
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            assertEquals(1, schoolRetryCount.get())
            assertEquals(1, notificationRetryCount.get())
            assertEquals(1, settingsCount.get())
            assertEquals(1, finishCount.get())
            isFinishing.value = true
        }

        assertDisabled(context.getString(R.string.auth_back))
        assertDisabled(context.getString(R.string.onboarding_upgrade_retry))
        assertDisabled(context.getString(R.string.onboarding_notification_sync_retry))
        assertDisabled(context.getString(R.string.onboarding_open_notification_settings))
        assertDisabled(context.getString(R.string.onboarding_ready_open))
    }

    @Test
    fun gradeyIdRoutesAllActionsAndAnnouncesBlockingFailure() {
        val isLoading = mutableStateOf(false)
        val errorMessage = mutableStateOf<String?>(null)
        val googleCount = AtomicInteger(0)
        val localCount = AtomicInteger(0)
        val backCount = AtomicInteger(0)
        val helpCount = AtomicInteger(0)
        val githubCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                GradeyIdLoginScreen(
                    isLoading = isLoading.value,
                    onGoogleSignIn = { googleCount.incrementAndGet() },
                    onOpenHelp = { helpCount.incrementAndGet() },
                    onOpenGitHub = { githubCount.incrementAndGet() },
                    errorMessage = errorMessage.value,
                    onContinueWithoutAccount = { localCount.incrementAndGet() },
                    onBack = { backCount.incrementAndGet() },
                )
            }
        }

        click(context.getString(R.string.auth_back))
        click(context.getString(R.string.gradey_id_continue_google))
        click(context.getString(R.string.gradey_id_continue_without_account))
        click(context.getString(R.string.auth_help))
        click(context.getString(R.string.auth_github))
        composeRule.runOnIdle {
            assertEquals(1, backCount.get())
            assertEquals(1, googleCount.get())
            assertEquals(1, localCount.get())
            assertEquals(1, helpCount.get())
            assertEquals(1, githubCount.get())
            errorMessage.value = GradeyIdFailure
        }

        composeRule.onNodeWithText(GradeyIdFailure)
            .performScrollTo()
            .assertIsDisplayed()
            .assert(liveRegionMatcher(LiveRegionMode.Assertive))

        composeRule.runOnIdle { isLoading.value = true }
        assertDisabled(context.getString(R.string.auth_back))
        assertDisabled(context.getString(R.string.gradey_id_signing_in))
        assertDisabled(context.getString(R.string.gradey_id_continue_without_account))
        composeRule.onNodeWithText(context.getString(R.string.auth_help))
            .performScrollTo()
            .assertIsEnabled()
        composeRule.onNodeWithText(context.getString(R.string.auth_github))
            .performScrollTo()
            .assertIsEnabled()
    }

    private fun click(text: String) {
        composeRule.onNodeWithText(text)
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
    }

    private fun assertDisabled(text: String) {
        composeRule.onNodeWithText(text)
            .performScrollTo()
            .assertIsNotEnabled()
    }

    private fun liveRegionMatcher(mode: LiveRegionMode) =
        SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, mode)

    private companion object {
        const val SchoolFailure = "School cloud link failed for onboarding test"
        const val NotificationFailure = "Notification sync failed for onboarding test"
        const val GradeyIdFailure = "Gradey ID sign-in failed for onboarding test"
    }
}
