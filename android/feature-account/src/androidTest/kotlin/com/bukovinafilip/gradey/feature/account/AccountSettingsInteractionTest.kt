package com.bukovinafilip.gradey.feature.account

import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
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

    @Composable
    private fun TestAccountScreen(
        selectedDestination: AccountSettingsDestination?,
        onSelectedDestinationChange: (AccountSettingsDestination?) -> Unit,
        onOpenMeals: () -> Unit = {},
        onOpenSupport: () -> Unit = {},
    ) {
        AccountScreen(
            account = null,
            linkedAccounts = emptyList(),
            selectedDestination = selectedDestination,
            hasBakalariConnectionOnDevice = true,
            isGuestMode = true,
            onUpdateFullName = { _ -> },
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
    }
}
