package com.bukovinafilip.gradey.feature.account

import android.view.KeyEvent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountDeletionInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun openingAndFirstContinueNeverDelete() {
        val deleteCount = AtomicInteger(0)
        setScreen(onDeleteAccount = { deleteCount.incrementAndGet() })

        openFirstStage()
        assertDeleteCount(deleteCount, 0)

        continueToFinalStage()
        assertDeleteCount(deleteCount, 0)
    }

    @Test
    fun cancelAndSystemBackDismissEveryStageWithoutDeleting() {
        val deleteCount = AtomicInteger(0)
        setScreen(onDeleteAccount = { deleteCount.incrementAndGet() })

        openFirstStage()
        cancelDialog()
        firstStageTitle().assertDoesNotExist()
        assertDeleteCount(deleteCount, 0)

        openFirstStage()
        pressSystemBack()
        firstStageTitle().assertDoesNotExist()
        assertDeleteCount(deleteCount, 0)

        openFirstStage()
        continueToFinalStage()
        cancelDialog()
        finalStageTitle().assertDoesNotExist()
        assertDeleteCount(deleteCount, 0)

        openFirstStage()
        continueToFinalStage()
        pressSystemBack()
        finalStageTitle().assertDoesNotExist()
        assertDeleteCount(deleteCount, 0)
    }

    @Test
    fun finalDestructiveActionDeletesExactlyOnce() {
        val deleteCount = AtomicInteger(0)
        setScreen(onDeleteAccount = { deleteCount.incrementAndGet() })

        openFirstStage()
        continueToFinalStage()
        composeRule.onNodeWithText(context.getString(R.string.delete_final_action))
            .assertIsDisplayed()
            .performClick()

        finalStageTitle().assertDoesNotExist()
        assertDeleteCount(deleteCount, 1)
    }

    @Test
    fun exportAndDeleteWorkDisableTheDeleteEntry() {
        val deleteCount = AtomicInteger(0)
        var isExportingData by mutableStateOf(true)
        var isDeletingAccount by mutableStateOf(false)
        composeRule.setContent {
            TestAccountScreen(
                isExportingData = isExportingData,
                isDeletingAccount = isDeletingAccount,
                onDeleteAccount = { deleteCount.incrementAndGet() },
            )
        }

        deleteEntry().performScrollTo().assertIsNotEnabled()

        composeRule.runOnIdle {
            isExportingData = false
            isDeletingAccount = true
        }
        deleteEntry().performScrollTo().assertIsNotEnabled()
        assertDeleteCount(deleteCount, 0)
    }

    private fun setScreen(onDeleteAccount: () -> Unit) {
        composeRule.setContent {
            TestAccountScreen(onDeleteAccount = onDeleteAccount)
        }
    }

    @Composable
    private fun TestAccountScreen(
        isExportingData: Boolean = false,
        isDeletingAccount: Boolean = false,
        onDeleteAccount: () -> Unit,
    ) {
        GradeyTheme {
            AccountScreen(
                account = TestAccount,
                linkedAccounts = emptyList(),
                selectedDestination = AccountSettingsDestination.PRIVACY_DATA,
                hasBakalariConnectionOnDevice = true,
                isExportingData = isExportingData,
                isDeletingAccount = isDeletingAccount,
                onUpdateFullName = {},
                onSelectedDestinationChange = {},
                onConnectGradeyId = {},
                onRefreshLinkedAccounts = {},
                onAddSchool = {},
                onActivateLinkedAccount = {},
                onReconnectLinkedAccount = {},
                onToggleLinkedNotifications = { _, _ -> },
                onOpenNotificationSettings = {},
                onUpdateNotificationPreferences = {},
                onOpenMeals = {},
                onRetryStravaCloudLink = {},
                onOpenPrivacyPolicy = {},
                onOpenTermsOfUse = {},
                onExportData = {},
                onDeleteAccount = onDeleteAccount,
                onOpenSupport = {},
                onUnlinkLinkedAccount = {},
                onAppLanguageChange = {},
                onShowMealsTabChange = {},
                onSignOut = {},
            )
        }
    }

    private fun openFirstStage() {
        deleteEntry()
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        firstStageTitle().assertIsDisplayed()
    }

    private fun continueToFinalStage() {
        composeRule.onNodeWithText(context.getString(R.string.delete_continue))
            .assertIsDisplayed()
            .performClick()
        finalStageTitle().assertIsDisplayed()
    }

    private fun cancelDialog() {
        composeRule.onNodeWithText(context.getString(R.string.delete_cancel))
            .assertIsDisplayed()
            .performClick()
    }

    private fun pressSystemBack() {
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        composeRule.waitForIdle()
    }

    private fun deleteEntry(): SemanticsNodeInteraction =
        composeRule.onNodeWithTag(ACCOUNT_DELETE_ENTRY_TEST_TAG)

    private fun firstStageTitle(): SemanticsNodeInteraction =
        composeRule.onNodeWithText(context.getString(R.string.delete_first_title))

    private fun finalStageTitle(): SemanticsNodeInteraction =
        composeRule.onNodeWithText(context.getString(R.string.delete_final_title))

    private fun assertDeleteCount(deleteCount: AtomicInteger, expected: Int) {
        composeRule.runOnIdle { assertEquals(expected, deleteCount.get()) }
    }

    private companion object {
        val TestAccount = GradeyAccount(
            id = "deletion-test-account",
            email = "student@example.com",
        )
    }
}
