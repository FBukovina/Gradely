package com.bukovinafilip.gradey.feature.today

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.text.AnnotatedString
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.SchoolReconnectPrefill
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
/**
 * Verifies Compose routing and callback ownership only. Provider credential identity is enforced
 * and tested at the repository boundary; every fixture here uses a distinct modern provider ID.
 */
class TodayLinkedAccountInteractionTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun accountMenuRoutesHealthyAndFailedAccountsToOnlyTheirExactActions() {
        val activations = CopyOnWriteArrayList<LinkedSchoolAccount>()
        val prefillAccounts = CopyOnWriteArrayList<LinkedSchoolAccount>()
        val reconnects = CopyOnWriteArrayList<ReconnectInvocation>()
        setScreen(
            accounts = listOf(ActiveAccount, HealthyAccount, FailedAccount),
            onActivate = activations::add,
            onPrefill = { account ->
                prefillAccounts += account
                prefillFor(account)
            },
            onReconnect = { account, school, username, password ->
                reconnects += ReconnectInvocation(account, school, username, password)
                null
            },
        )
        waitForText(FailedReason)

        openAccountMenu()
        composeRule.onNode(
            hasText(ActiveAccount.displayName) and
                SemanticsMatcher.keyIsDefined(SemanticsProperties.Disabled),
        ).assertIsNotEnabled()
        composeRule.onNode(hasText(HealthyAccount.displayName) and hasClickAction()).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) { activations.size == 1 }

        openAccountMenu()
        composeRule.onNode(hasText(FailedAccount.displayName) and hasClickAction()).performClick()
        waitForText(reconnectTitle(FailedPrefill.schoolName))

        composeRule.runOnIdle {
            assertEquals(listOf(HealthyAccount), activations)
            assertEquals(listOf(FailedAccount), prefillAccounts)
            assertEquals(emptyList<ReconnectInvocation>(), reconnects)
        }
        schoolField().assertEditableTextEquals(FailedPrefill.schoolURL)
        usernameField().assertEditableTextEquals(FailedPrefill.username)
        passwordField().assertEditableTextEquals("")
        composeRule.onNodeWithContentDescription(showPasswordLabel)
            .assertContentDescriptionEquals(showPasswordLabel)
    }

    @Test
    fun actionRequiredNoticeShowsExactServerReason() {
        setScreen(accounts = listOf(ActiveAccount, FailedAccount))

        composeRule.onNodeWithText(FailedReason).assertIsDisplayed()
        composeRule.onNodeWithText(reconnectFallback).assertDoesNotExist()
    }

    @Test
    fun blankActionRequiredReasonUsesLocalizedFallback() {
        val blankReason = FailedAccount.copy(actionRequiredReason = "   ")
        setScreen(accounts = listOf(ActiveAccount, blankReason))

        composeRule.onNodeWithText(reconnectFallback).assertIsDisplayed()
        composeRule.onNodeWithText(FailedReason).assertDoesNotExist()
    }

    @Test
    fun reconnectValidationCancelErrorAndSuccessPreserveExactAccountOwnership() {
        val prefillAccounts = CopyOnWriteArrayList<LinkedSchoolAccount>()
        val reconnects = CopyOnWriteArrayList<ReconnectInvocation>()
        val reconnectAttempts = AtomicInteger(0)
        setScreen(
            accounts = listOf(ActiveAccount, FailedAccount),
            onPrefill = { account ->
                prefillAccounts += account
                FailedPrefill
            },
            onReconnect = { account, school, username, password ->
                reconnects += ReconnectInvocation(account, school, username, password)
                if (reconnectAttempts.incrementAndGet() == 1) ReconnectError else null
            },
        )
        waitForText(FailedReason)

        openReconnectNotice()
        waitForText(reconnectTitle(FailedPrefill.schoolName))
        reconnectSubmit().performScrollTo().performClick()
        composeRule.onNodeWithText(passwordRequiredLabel).assertIsDisplayed()
        composeRule.runOnIdle {
            assertEquals(0, reconnectAttempts.get())
            assertEquals(emptyList<ReconnectInvocation>(), reconnects)
        }

        pressBack()
        waitForTextToDisappear(reconnectTitle(FailedPrefill.schoolName))
        composeRule.runOnIdle {
            assertEquals(0, reconnectAttempts.get())
            assertEquals(emptyList<ReconnectInvocation>(), reconnects)
        }

        openReconnectNotice()
        waitForText(reconnectTitle(FailedPrefill.schoolName))
        passwordField().performScrollTo().performTextInput(Password)
        reconnectSubmit().performScrollTo().performClick()
        waitForText(ReconnectError)

        val expected = ReconnectInvocation(
            FailedAccount,
            FailedPrefill.schoolURL,
            FailedPrefill.username,
            Password,
        )
        composeRule.runOnIdle {
            assertEquals(listOf(FailedAccount, FailedAccount), prefillAccounts)
            assertEquals(listOf(expected), reconnects)
            assertEquals(1, reconnectAttempts.get())
        }
        schoolField().assertEditableTextEquals(FailedPrefill.schoolURL)
        usernameField().assertEditableTextEquals(FailedPrefill.username)
        passwordField().assertInputTextEquals(Password)
        composeRule.onNodeWithContentDescription(showPasswordLabel)
            .assertContentDescriptionEquals(showPasswordLabel)

        reconnectSubmit().performScrollTo().performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) { reconnectAttempts.get() == 2 }
        waitForTextToDisappear(reconnectTitle(FailedPrefill.schoolName))
        composeRule.runOnIdle {
            assertEquals(listOf(expected, expected), reconnects)
        }
    }

    @Test
    fun mutationInProgressDisablesEveryAccountChangeEntryPoint() {
        val activations = AtomicInteger(0)
        val prefills = AtomicInteger(0)
        val reconnects = AtomicInteger(0)
        setScreen(
            accounts = listOf(ActiveAccount, HealthyAccount, FailedAccount),
            mutatingAccountID = FailedAccount.id,
            onActivate = { activations.incrementAndGet() },
            onPrefill = {
                prefills.incrementAndGet()
                FailedPrefill
            },
            onReconnect = { _, _, _, _ ->
                reconnects.incrementAndGet()
                null
            },
        )
        waitForText(FailedReason)

        composeRule.onNodeWithContentDescription(chooseAccountLabel).assertDoesNotExist()
        composeRule.onNode(hasText(reconnectLabel) and hasClickAction())
            .assertIsNotEnabled()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(0, activations.get())
            assertEquals(0, prefills.get())
            assertEquals(0, reconnects.get())
        }
    }

    @Test
    fun stalePrefillCannotReplaceTheNewestSelectedAccount() {
        val failedC = FailedAccount
        val failedD = SecondFailedAccount
        val pendingC = CompletableDeferred<SchoolReconnectPrefill?>()
        val pendingD = CompletableDeferred<SchoolReconnectPrefill?>()
        val prefillOrder = CopyOnWriteArrayList<String>()
        val reconnects = CopyOnWriteArrayList<ReconnectInvocation>()
        setScreen(
            accounts = listOf(ActiveAccount, failedC, failedD),
            onPrefill = { account ->
                prefillOrder += account.id
                when (account.id) {
                    failedC.id -> pendingC.await()
                    failedD.id -> pendingD.await()
                    else -> error("Unexpected account ${account.id}")
                }
            },
            onReconnect = { account, school, username, password ->
                reconnects += ReconnectInvocation(account, school, username, password)
                null
            },
        )
        waitForText(FailedReason)

        openAccountMenu()
        composeRule.onNode(hasText(failedC.displayName) and hasClickAction()).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) { prefillOrder == listOf(failedC.id) }
        openAccountMenu()
        composeRule.onNode(hasText(failedD.displayName) and hasClickAction()).performClick()
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            prefillOrder == listOf(failedC.id, failedD.id)
        }

        composeRule.runOnIdle { pendingD.complete(SecondFailedPrefill) }
        waitForText(reconnectTitle(SecondFailedPrefill.schoolName))
        composeRule.runOnIdle { pendingC.complete(FailedPrefill) }
        composeRule.waitForIdle()

        composeRule.onNodeWithText(reconnectTitle(FailedPrefill.schoolName)).assertDoesNotExist()
        schoolField().assertEditableTextEquals(SecondFailedPrefill.schoolURL)
        usernameField().assertEditableTextEquals(SecondFailedPrefill.username)
        passwordField().performScrollTo().performTextInput(Password)
        reconnectSubmit().performScrollTo().performClick()
        waitForTextToDisappear(reconnectTitle(SecondFailedPrefill.schoolName))

        composeRule.runOnIdle {
            assertEquals(
                listOf(
                    ReconnectInvocation(
                        failedD,
                        SecondFailedPrefill.schoolURL,
                        SecondFailedPrefill.username,
                        Password,
                    ),
                ),
                reconnects,
            )
        }
    }

    private fun setScreen(
        accounts: List<LinkedSchoolAccount>,
        activeAccountID: String = ActiveAccount.id,
        mutatingAccountID: String? = null,
        onActivate: (LinkedSchoolAccount) -> Unit = {},
        onPrefill: suspend (LinkedSchoolAccount) -> SchoolReconnectPrefill? = ::prefillFor,
        onReconnect: suspend (LinkedSchoolAccount, String, String, String) -> String? = { _, _, _, _ -> null },
    ) {
        composeRule.setContent {
            GradeyTheme {
                TodayScreen(
                    dashboard = DashboardData(MarksResponse()),
                    absence = AbsenceResponse(),
                    timetable = null,
                    stravaMenu = null,
                    isMealsConnected = false,
                    linkedSchoolAccounts = accounts,
                    activeLinkedAccountID = activeAccountID,
                    mutatingLinkedAccountID = mutatingAccountID,
                    isRefreshing = false,
                    onRefresh = {},
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                    onOpenMarks = {},
                    onOpenAbsence = {},
                    onOpenTimetable = {},
                    onOpenMeals = {},
                    onActivateLinkedAccount = onActivate,
                    onReconnectPrefill = onPrefill,
                    onReconnectLinkedAccount = onReconnect,
                )
            }
        }
    }

    private fun openAccountMenu() {
        composeRule.onNodeWithContentDescription(chooseAccountLabel).performClick()
    }

    private fun openReconnectNotice() {
        composeRule.onNode(hasText(reconnectLabel) and hasClickAction()).performClick()
    }

    private fun reconnectSubmit(): SemanticsNodeInteraction {
        val candidates = composeRule.onAllNodes(hasText(reconnectLabel) and hasClickAction())
        return candidates[candidates.fetchSemanticsNodes().lastIndex]
    }

    private fun schoolField(): SemanticsNodeInteraction = field(schoolURLLabel)

    private fun usernameField(): SemanticsNodeInteraction = field(usernameLabel)

    private fun passwordField(): SemanticsNodeInteraction = field(passwordLabel)

    private fun field(label: String): SemanticsNodeInteraction = composeRule.onNode(
        hasSetTextAction() and hasText(label, substring = true),
    )

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForTextToDisappear(text: String) {
        composeRule.waitUntil(timeoutMillis = TimeoutMillis) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isEmpty()
        }
    }

    private val targetContext
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val chooseAccountLabel get() = targetContext.getString(R.string.today_choose_school_account)
    private val reconnectLabel get() = targetContext.getString(R.string.today_reconnect)
    private val reconnectFallback get() = targetContext.getString(R.string.today_reconnect_fallback)
    private val schoolURLLabel get() = targetContext.getString(R.string.today_school_url)
    private val usernameLabel get() = targetContext.getString(R.string.today_username)
    private val passwordLabel get() = targetContext.getString(R.string.today_password)
    private val passwordRequiredLabel get() = targetContext.getString(R.string.today_password_required)
    private val showPasswordLabel get() = targetContext.getString(R.string.today_show_password)

    private fun reconnectTitle(schoolName: String): String =
        targetContext.getString(R.string.today_reconnect_title, schoolName)

    private data class ReconnectInvocation(
        val account: LinkedSchoolAccount,
        val schoolURL: String,
        val username: String,
        val password: String,
    )

    private companion object {
        const val TimeoutMillis = 10_000L
        const val FailedReason = "The school password changed on the server."
        const val ReconnectError = "These credentials belong to another student."
        const val Password = "private-password"
        val ActiveAccount = account("active", "Active Student")
        val HealthyAccount = account("healthy", "Healthy Student")
        val FailedAccount = account(
            id = "failed-c",
            displayName = "Failed Student C",
            status = LinkedAccountStatus.ACTION_REQUIRED,
            actionRequiredReason = FailedReason,
        )
        val SecondFailedAccount = account(
            id = "failed-d",
            displayName = "Failed Student D",
            status = LinkedAccountStatus.FAILED,
            actionRequiredReason = "The connection for student D expired.",
        )
        val FailedPrefill = SchoolReconnectPrefill(
            schoolURL = "https://school-c.example.cz/",
            schoolName = "School C",
            username = "student-c",
        )
        val SecondFailedPrefill = SchoolReconnectPrefill(
            schoolURL = "https://school-d.example.cz/",
            schoolName = "School D",
            username = "student-d",
        )

        fun account(
            id: String,
            displayName: String,
            status: LinkedAccountStatus = LinkedAccountStatus.ACTIVE,
            actionRequiredReason: String? = null,
        ) = LinkedSchoolAccount(
            id = id,
            provider = LinkedAccountProvider.BAKALARI,
            providerUserID = "bakalari-user-$id",
            displayName = displayName,
            schoolName = "$displayName School",
            status = status,
            actionRequiredReason = actionRequiredReason,
        )

        fun prefillFor(account: LinkedSchoolAccount): SchoolReconnectPrefill? = when (account.id) {
            FailedAccount.id -> FailedPrefill
            SecondFailedAccount.id -> SecondFailedPrefill
            else -> null
        }
    }
}

private fun SemanticsNodeInteraction.assertEditableTextEquals(expected: String) = assert(
    SemanticsMatcher.expectValue(
        SemanticsProperties.EditableText,
        AnnotatedString(expected),
    ),
)

private fun SemanticsNodeInteraction.assertInputTextEquals(expected: String) = assert(
    SemanticsMatcher.expectValue(
        SemanticsProperties.InputText,
        AnnotatedString(expected),
    ),
)
