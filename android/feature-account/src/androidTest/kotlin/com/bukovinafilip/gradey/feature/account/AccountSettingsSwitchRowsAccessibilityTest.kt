package com.bukovinafilip.gradey.feature.account

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountSettingsSwitchRowsAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun mealsTabUsesLabeledFullRowSwitchAndExactCallback() {
        val latestSelection = AtomicReference<Boolean?>()
        composeRule.setContent {
            var showMealsTab by remember { mutableStateOf(false) }
            TestAccountScreen(
                selectedDestination = AccountSettingsDestination.APP_PREFERENCES,
                showMealsTab = showMealsTab,
                onShowMealsTabChange = {
                    showMealsTab = it
                    latestSelection.set(it)
                },
            )
        }

        switchNode(R.string.meals_tab_setting_title)
            .assertTextContains(context.getString(R.string.meals_tab_setting_message))
            .assert(toggleOffMatcher)
            .assertIsEnabled()
            .performClick()
            .assert(toggleOnMatcher)
        composeRule.runOnIdle { assertEquals(true, latestSelection.get()) }
    }

    @Test
    fun linkedSchoolNotificationsUseLabeledFullRowSwitchAndExactCallback() {
        val latestUpdate = AtomicReference<Pair<String, Boolean>?>()
        composeRule.setContent {
            var linkedAccounts by remember {
                mutableStateOf(
                    listOf(
                        OtherSchoolAccount.copy(notificationsEnabled = false),
                        TestSchoolAccount.copy(notificationsEnabled = false),
                    ),
                )
            }
            TestAccountScreen(
                selectedDestination = AccountSettingsDestination.CONNECTED_SERVICES,
                linkedAccounts = linkedAccounts,
                activeLinkedAccountID = TestSchoolAccount.id,
                onToggleLinkedNotifications = { account, enabled ->
                    latestUpdate.set(account.id to enabled)
                    linkedAccounts = linkedAccounts.map { linkedAccount ->
                        if (linkedAccount.id == account.id) {
                            linkedAccount.copy(notificationsEnabled = enabled)
                        } else {
                            linkedAccount
                        }
                    }
                },
            )
        }

        linkedSchoolSwitchNode(TestSchoolAccount.id)
            .assertTextContains(context.getString(R.string.account_new_mark_notifications))
            .assertTextContains(context.getString(R.string.account_new_mark_notifications_message))
            .assert(toggleOffMatcher)
            .assertIsEnabled()
            .performClick()
            .assert(toggleOnMatcher)
        composeRule.runOnIdle {
            assertEquals(TestSchoolAccount.id to true, latestUpdate.get())
        }
    }

    @Test
    fun linkedSchoolNotificationsAreDisabledWhenGlobalNewMarksAreOff() {
        val latestUpdate = AtomicReference<Pair<String, Boolean>?>()
        composeRule.setContent {
            TestAccountScreen(
                selectedDestination = AccountSettingsDestination.CONNECTED_SERVICES,
                linkedAccounts = listOf(TestSchoolAccount),
                activeLinkedAccountID = TestSchoolAccount.id,
                notificationPreferences = NotificationPreferences.Default.copy(newMarksEnabled = false),
                onToggleLinkedNotifications = { account, enabled ->
                    latestUpdate.set(account.id to enabled)
                },
            )
        }

        linkedSchoolSwitchNode(TestSchoolAccount.id)
            .assert(toggleOnMatcher)
            .assertIsNotEnabled()
            .performClick()
        composeRule.runOnIdle { assertNull(latestUpdate.get()) }
    }

    private fun switchNode(labelResource: Int) =
        composeRule.onNodeWithText(context.getString(labelResource))
            .performScrollTo()
            .assert(switchRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

    private fun linkedSchoolSwitchNode(linkedAccountID: String) =
        composeRule.onNodeWithTag(
            "$ACCOUNT_LINKED_NOTIFICATIONS_TEST_TAG_PREFIX$linkedAccountID",
        )
            .performScrollTo()
            .assert(switchRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

    @Composable
    private fun TestAccountScreen(
        selectedDestination: AccountSettingsDestination,
        linkedAccounts: List<LinkedSchoolAccount> = emptyList(),
        activeLinkedAccountID: String? = null,
        showMealsTab: Boolean = true,
        notificationPreferences: NotificationPreferences = NotificationPreferences.Default,
        onToggleLinkedNotifications: (LinkedSchoolAccount, Boolean) -> Unit = { _, _ -> },
        onShowMealsTabChange: (Boolean) -> Unit = {},
    ) {
        GradeyTheme {
            AccountScreen(
                account = TestAccount,
                linkedAccounts = linkedAccounts,
                selectedDestination = selectedDestination,
                hasBakalariConnectionOnDevice = true,
                activeLinkedAccountID = activeLinkedAccountID,
                showMealsTab = showMealsTab,
                notificationPreferences = notificationPreferences,
                onUpdateFullName = {},
                onSelectedDestinationChange = {},
                onConnectGradeyId = {},
                onRefreshLinkedAccounts = {},
                onAddSchool = {},
                onActivateLinkedAccount = {},
                onReconnectLinkedAccount = {},
                onToggleLinkedNotifications = onToggleLinkedNotifications,
                onOpenNotificationSettings = {},
                onUpdateNotificationPreferences = {},
                onOpenMeals = {},
                onRetryStravaCloudLink = {},
                onOpenPrivacyPolicy = {},
                onOpenTermsOfUse = {},
                onExportData = {},
                onDeleteAccount = {},
                onOpenSupport = {},
                onUnlinkLinkedAccount = {},
                onAppLanguageChange = {},
                onShowMealsTabChange = onShowMealsTabChange,
                onSignOut = {},
            )
        }
    }

    private companion object {
        val TestAccount = GradeyAccount(id = "account")
        val TestSchoolAccount = LinkedSchoolAccount(
            id = "school-account",
            provider = LinkedAccountProvider.BAKALARI,
            displayName = "School account",
        )
        val OtherSchoolAccount = LinkedSchoolAccount(
            id = "other-school-account",
            provider = LinkedAccountProvider.BAKALARI,
            displayName = "Other school account",
        )
        val switchRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)
        val toggleOffMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.Off,
        )
        val toggleOnMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.On,
        )
    }
}
