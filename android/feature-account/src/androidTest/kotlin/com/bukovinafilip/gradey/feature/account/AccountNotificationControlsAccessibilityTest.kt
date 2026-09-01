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
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountNotificationControlsAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun labeledRowsExposeRolesStatesTargetsAndExactCallbacks() {
        val latestUpdate = AtomicReference<NotificationPreferences?>()
        setNotificationScreen(onUpdate = latestUpdate::set)

        switchNode(R.string.notifications_new_marks)
            .assert(switchRoleMatcher)
            .assert(toggleOnMatcher)
            .assertIsEnabled()
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

        radioNode(R.string.notifications_private_summary)
            .assertIsNotSelected()
            .assertIsEnabled()
        radioNode(R.string.notifications_mark_and_subject)
            .assertIsSelected()
            .assertIsEnabled()
        radioNode(R.string.notifications_full_details)
            .assertIsNotSelected()
            .assertIsEnabled()
            .performClick()
            .assertIsSelected()
        composeRule.runOnIdle {
            assertEquals(NotificationLockScreenDetail.FULL_DETAILS, latestUpdate.get()?.lockScreenDetail)
        }

        switchNode(R.string.notifications_quiet_hours)
            .assert(switchRoleMatcher)
            .assert(toggleOffMatcher)
            .assertIsEnabled()
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
            .assert(toggleOnMatcher)
        composeRule.runOnIdle { assertEquals(true, latestUpdate.get()?.quietHoursEnabled) }
        val quietHoursStart = quietHoursStartNode().assertIsEnabled()
        val quietHoursEnd = quietHoursEndNode().assertIsEnabled()

        switchNode(R.string.notifications_new_marks)
            .performClick()
            .assert(toggleOffMatcher)
        composeRule.runOnIdle {
            assertEquals(
                NotificationPreferences.Default.copy(
                    newMarksEnabled = false,
                    lockScreenDetail = NotificationLockScreenDetail.FULL_DETAILS,
                    quietHoursEnabled = true,
                ),
                latestUpdate.get(),
            )
        }

        NotificationLockScreenDetail.entries.forEach { detail ->
            radioNode(detail.labelResourceForTest()).assertIsNotEnabled()
        }
        switchNode(R.string.notifications_quiet_hours).assertIsNotEnabled()
        val disabledPreferences = latestUpdate.get()
        quietHoursStart.assertIsNotEnabled().performClick()
        quietHoursEnd.assertIsNotEnabled().performClick()
        composeRule.runOnIdle { assertEquals(disabledPreferences, latestUpdate.get()) }
    }

    @Test
    fun savingDisablesEveryLabeledNotificationControl() {
        setNotificationScreen(isUpdating = true)

        switchNode(R.string.notifications_new_marks)
            .assert(switchRoleMatcher)
            .assertIsNotEnabled()
            .assertHeightIsAtLeast(48.dp)
        NotificationLockScreenDetail.entries.forEach { detail ->
            radioNode(detail.labelResourceForTest())
                .assertIsNotEnabled()
                .assertHeightIsAtLeast(48.dp)
        }
        switchNode(R.string.notifications_quiet_hours)
            .assert(switchRoleMatcher)
            .assertIsNotEnabled()
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun enablingWithoutPermissionRequestsPermissionWithoutPersistingOn() {
        val permissionRequests = AtomicInteger(0)
        val latestUpdate = AtomicReference<NotificationPreferences?>()
        setNotificationScreen(
            initialPreferences = NotificationPreferences.Default.copy(newMarksEnabled = false),
            permissionGranted = false,
            onRequestPermission = { permissionRequests.incrementAndGet() },
            onUpdate = latestUpdate::set,
        )

        switchNode(R.string.notifications_new_marks)
            .assert(toggleOffMatcher)
            .performClick()
            .assert(toggleOffMatcher)

        composeRule.runOnIdle {
            assertEquals(1, permissionRequests.get())
            assertNull(latestUpdate.get())
        }
    }

    @Test
    fun enablingWithPermissionPersistsOn() {
        val latestUpdate = AtomicReference<NotificationPreferences?>()
        setNotificationScreen(
            initialPreferences = NotificationPreferences.Default.copy(newMarksEnabled = false),
            permissionGranted = true,
            onUpdate = latestUpdate::set,
        )

        switchNode(R.string.notifications_new_marks)
            .assert(toggleOffMatcher)
            .performClick()
            .assert(toggleOnMatcher)

        composeRule.runOnIdle {
            assertEquals(true, latestUpdate.get()?.newMarksEnabled)
        }
    }

    @Test
    fun deniedPermissionExposesWorkingSystemSettingsRecovery() {
        val settingsOpens = AtomicInteger(0)
        setNotificationScreen(
            permissionGranted = false,
            onOpenSettings = { settingsOpens.incrementAndGet() },
        )

        composeRule.onNodeWithText(context.getString(R.string.notifications_open_system_settings))
            .performScrollTo()
            .assertIsEnabled()
            .performClick()

        composeRule.runOnIdle { assertEquals(1, settingsOpens.get()) }
    }

    private fun setNotificationScreen(
        initialPreferences: NotificationPreferences = NotificationPreferences.Default,
        permissionGranted: Boolean = true,
        isUpdating: Boolean = false,
        onRequestPermission: () -> Unit = {},
        onOpenSettings: () -> Unit = {},
        onUpdate: (NotificationPreferences) -> Unit = {},
    ) {
        composeRule.setContent {
            var preferences by remember { mutableStateOf(initialPreferences) }
            NotificationTestScreen(
                preferences = preferences,
                permissionGranted = permissionGranted,
                isUpdating = isUpdating,
                onRequestPermission = onRequestPermission,
                onOpenSettings = onOpenSettings,
                onUpdate = {
                    preferences = it
                    onUpdate(it)
                },
            )
        }
    }

    @Composable
    private fun NotificationTestScreen(
        preferences: NotificationPreferences,
        permissionGranted: Boolean,
        isUpdating: Boolean,
        onRequestPermission: () -> Unit,
        onOpenSettings: () -> Unit,
        onUpdate: (NotificationPreferences) -> Unit,
    ) {
        GradeyTheme {
            AccountScreen(
                account = TestAccount,
                linkedAccounts = listOf(TestSchoolAccount),
                selectedDestination = AccountSettingsDestination.NOTIFICATIONS,
                hasBakalariConnectionOnDevice = true,
                notificationPreferences = preferences,
                notificationPermissionGranted = permissionGranted,
                isUpdatingNotificationPreferences = isUpdating,
                onUpdateFullName = {},
                onSelectedDestinationChange = {},
                onConnectGradeyId = {},
                onRefreshLinkedAccounts = {},
                onAddSchool = {},
                onActivateLinkedAccount = {},
                onReconnectLinkedAccount = {},
                onToggleLinkedNotifications = { _, _ -> },
                onOpenNotificationSettings = onOpenSettings,
                onRequestNotificationPermission = onRequestPermission,
                onUpdateNotificationPreferences = onUpdate,
                onOpenMeals = {},
                onRetryStravaCloudLink = {},
                onOpenPrivacyPolicy = {},
                onOpenTermsOfUse = {},
                onExportData = {},
                onDeleteAccount = {},
                onOpenSupport = {},
                onUnlinkLinkedAccount = {},
                onAppLanguageChange = {},
                onShowMealsTabChange = {},
                onSignOut = {},
            )
        }
    }

    private fun switchNode(labelResource: Int): SemanticsNodeInteraction =
        composeRule.onNodeWithText(context.getString(labelResource))
            .performScrollTo()

    private fun radioNode(labelResource: Int): SemanticsNodeInteraction =
        composeRule.onNodeWithText(context.getString(labelResource))
            .performScrollTo()
            .assert(radioRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

    private fun quietHoursStartNode(): SemanticsNodeInteraction =
        composeRule.onNodeWithText(
            context.getString(R.string.notifications_quiet_start, "22:00"),
        ).performScrollTo()

    private fun quietHoursEndNode(): SemanticsNodeInteraction =
        composeRule.onNodeWithText(
            context.getString(R.string.notifications_quiet_end, "06:00"),
        ).performScrollTo()

    private companion object {
        val TestAccount = GradeyAccount(id = "account")
        val TestSchoolAccount = LinkedSchoolAccount(
            id = "school-account",
            provider = LinkedAccountProvider.BAKALARI,
            displayName = "School account",
        )
        val switchRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)
        val radioRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton)
        val toggleOffMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.Off,
        )
        val toggleOnMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.On,
        )

        fun NotificationLockScreenDetail.labelResourceForTest(): Int = when (this) {
            NotificationLockScreenDetail.PRIVATE_SUMMARY -> R.string.notifications_private_summary
            NotificationLockScreenDetail.MARK_AND_SUBJECT -> R.string.notifications_mark_and_subject
            NotificationLockScreenDetail.FULL_DETAILS -> R.string.notifications_full_details
        }
    }
}
