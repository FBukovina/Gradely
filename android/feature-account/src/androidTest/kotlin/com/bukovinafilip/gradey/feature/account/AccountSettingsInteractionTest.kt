package com.bukovinafilip.gradey.feature.account

import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.text.AnnotatedString
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountSettingsInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun localOnlyConnectedServicesOpensRealMealsActionAndReturnsToOverview() {
        val mealsOpens = AtomicInteger(0)
        composeRule.setContent {
            var destination by remember { mutableStateOf<AccountSettingsDestination?>(null) }
            GradeyTheme {
                TestAccountScreen(
                    selectedDestination = destination,
                    onSelectedDestinationChange = { destination = it },
                    onOpenMeals = { mealsOpens.incrementAndGet() },
                )
            }
        }

        composeRule.onNodeWithText(context.getString(R.string.settings_destination_connected))
            .performScrollTo()
            .performClick()
        composeRule.onNodeWithText(context.getString(R.string.connected_cloud_requires_gradey_id))
            .assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.connected_manage_strava))
            .assertIsDisplayed()
            .performClick()
        composeRule.runOnIdle { assertEquals(1, mealsOpens.get()) }

        composeRule.onNodeWithText(context.getString(R.string.settings_back)).performClick()
        composeRule.onNodeWithText(context.getString(R.string.settings_overview_title))
            .assertIsDisplayed()
    }

    @Test
    fun supportDestinationSurvivesTemporaryExternalScreen() {
        composeRule.setContent {
            var destination by remember { mutableStateOf<AccountSettingsDestination?>(null) }
            var showingExternalSupport by remember { mutableStateOf(false) }
            GradeyTheme {
                if (showingExternalSupport) {
                    Button(onClick = { showingExternalSupport = false }) {
                        Text(ReturnFromSupport)
                    }
                } else {
                    TestAccountScreen(
                        selectedDestination = destination,
                        onSelectedDestinationChange = { destination = it },
                        onOpenSupport = { showingExternalSupport = true },
                    )
                }
            }
        }

        composeRule.onNodeWithText(context.getString(R.string.settings_destination_support))
            .performScrollTo()
            .performClick()
        composeRule.onNodeWithText(context.getString(R.string.support_open))
            .assertIsDisplayed()
            .performClick()
        composeRule.onNodeWithText(ReturnFromSupport).assertIsDisplayed().performClick()

        composeRule.onNodeWithText(context.getString(R.string.settings_back)).assertIsDisplayed()
        composeRule.onNodeWithText(context.getString(R.string.support_open)).assertIsDisplayed()
    }

    @Test
    fun expandedOverviewExposesAndUpdatesItsSelectedTab() {
        composeRule.setContent {
            var destination by remember { mutableStateOf(AccountSettingsDestination.ACCOUNT) }
            GradeyTheme {
                AccountSettingsOverview(
                    account = null,
                    linkedAccounts = emptyList(),
                    notificationPreferences = NotificationPreferences.Default,
                    isStravaConnectedOnDevice = false,
                    hasBakalariConnectionOnDevice = true,
                    activeLinkedAccountID = null,
                    notificationPermissionGranted = false,
                    notificationsAvailable = false,
                    selectedDestination = destination,
                    onSelect = { destination = it },
                )
            }
        }

        destinationNode(AccountSettingsDestination.ACCOUNT)
            .assert(tabRoleMatcher)
            .assertIsSelected()
        destinationNode(AccountSettingsDestination.CONNECTED_SERVICES)
            .performScrollTo()
            .assert(tabRoleMatcher)
            .assertIsNotSelected()
            .performClick()
            .assertIsSelected()
        destinationNode(AccountSettingsDestination.ACCOUNT).assertIsNotSelected()
    }

    @Test
    fun editedFullNameSurvivesRestorationAndSubmitsTheExactDraft() {
        val submittedName = AtomicReference<String>()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                TestAccountScreen(
                    account = AccountA,
                    selectedDestination = AccountSettingsDestination.ACCOUNT,
                    onSelectedDestinationChange = {},
                    onUpdateFullName = submittedName::set,
                )
            }
        }

        composeRule.onNodeWithTag(ACCOUNT_FULL_NAME_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextReplacement(EditedName)
        restorationTester.emulateSavedInstanceStateRestore()

        assertFullName(EditedName)
        composeRule.onNodeWithTag(ACCOUNT_SAVE_FULL_NAME_TEST_TAG)
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        composeRule.runOnIdle { assertEquals(EditedName, submittedName.get()) }
    }

    @Test
    fun restorationIntoAnotherAccountDoesNotLeakThePriorNameDraft() {
        var account = AccountA
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            GradeyTheme {
                TestAccountScreen(
                    account = account,
                    selectedDestination = AccountSettingsDestination.ACCOUNT,
                    onSelectedDestinationChange = {},
                )
            }
        }

        composeRule.onNodeWithTag(ACCOUNT_FULL_NAME_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextReplacement(EditedName)
        composeRule.runOnIdle { account = AccountB }
        restorationTester.emulateSavedInstanceStateRestore()

        assertFullName(AccountB.fullName.orEmpty())
    }

    @Test
    fun sameAccountRefreshDoesNotOverwriteAnEditedNameDraft() {
        var account by mutableStateOf(AccountA)
        composeRule.setContent {
            GradeyTheme {
                TestAccountScreen(
                    account = account,
                    selectedDestination = AccountSettingsDestination.ACCOUNT,
                    onSelectedDestinationChange = {},
                )
            }
        }

        composeRule.onNodeWithTag(ACCOUNT_FULL_NAME_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextReplacement(EditedName)
        composeRule.runOnIdle {
            account = account.copy(fullName = RefreshedCanonicalName)
        }

        assertFullName(EditedName)
    }

    @Composable
    private fun TestAccountScreen(
        account: GradeyAccount? = null,
        selectedDestination: AccountSettingsDestination?,
        onSelectedDestinationChange: (AccountSettingsDestination?) -> Unit,
        onUpdateFullName: (String) -> Unit = {},
        onOpenMeals: () -> Unit = {},
        onOpenSupport: () -> Unit = {},
    ) {
        AccountScreen(
            account = account,
            linkedAccounts = emptyList(),
            selectedDestination = selectedDestination,
            hasBakalariConnectionOnDevice = true,
            isGuestMode = true,
            onUpdateFullName = onUpdateFullName,
            onSelectedDestinationChange = onSelectedDestinationChange,
            onConnectGradeyId = {},
            onRefreshLinkedAccounts = {},
            onAddSchool = {},
            onActivateLinkedAccount = { _ -> },
            onReconnectLinkedAccount = { _ -> },
            onToggleLinkedNotifications = { _, _ -> },
            onOpenNotificationSettings = {},
            onUpdateNotificationPreferences = { _ -> },
            onOpenMeals = onOpenMeals,
            onRetryStravaCloudLink = {},
            onOpenPrivacyPolicy = {},
            onOpenTermsOfUse = {},
            onExportData = {},
            onDeleteAccount = {},
            onOpenSupport = onOpenSupport,
            onUnlinkLinkedAccount = { _ -> },
            onAppLanguageChange = { _ -> },
            onShowMealsTabChange = { _ -> },
            onSignOut = {},
        )
    }

    private companion object {
        const val ReturnFromSupport = "Return from Support"
        const val EditedName = "Edited Student"
        const val RefreshedCanonicalName = "Refreshed Student"
        val AccountA = GradeyAccount(
            id = "account-a",
            email = "a@example.com",
            fullName = "Student A",
        )
        val AccountB = GradeyAccount(
            id = "account-b",
            email = "b@example.com",
            fullName = "Student B",
        )
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
    }

    private fun destinationNode(destination: AccountSettingsDestination) =
        composeRule.onNodeWithText(context.getString(destination.titleResource))

    private fun assertFullName(expected: String) {
        composeRule.onNodeWithTag(ACCOUNT_FULL_NAME_FIELD_TEST_TAG)
            .performScrollTo()
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.EditableText,
                    AnnotatedString(expected),
                ),
            )
    }
}
