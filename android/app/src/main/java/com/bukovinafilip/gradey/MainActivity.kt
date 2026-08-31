package com.bukovinafilip.gradey

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.bukovinafilip.gradey.feature.absence.AbsenceScreen
import com.bukovinafilip.gradey.feature.absence.AbsenceStateScreen
import com.bukovinafilip.gradey.feature.absence.R as AbsenceR
import com.bukovinafilip.gradey.feature.account.AccountScreen
import com.bukovinafilip.gradey.feature.account.AccountSettingsDestination
import com.bukovinafilip.gradey.feature.account.OnboardingSupportOptionsContent
import com.bukovinafilip.gradey.feature.account.SupportScreen
import com.bukovinafilip.gradey.feature.auth.AgeAttestationScreen
import com.bukovinafilip.gradey.feature.auth.GradeyCheckingScreen
import com.bukovinafilip.gradey.feature.auth.GradeyIdLoginScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingNotificationsScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingReadyScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingUpgradeSupportScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingWelcomeScreen
import com.bukovinafilip.gradey.feature.gradeyai.GradeyAIScreen
import com.bukovinafilip.gradey.feature.login.SchoolLoginScreen
import com.bukovinafilip.gradey.feature.stravacz.StravaCZScreen
import com.bukovinafilip.gradey.feature.subjects.SubjectsScreen
import com.bukovinafilip.gradey.feature.timetable.TimetableScreen
import com.bukovinafilip.gradey.feature.timetable.R as TimetableR
import com.bukovinafilip.gradey.feature.today.TodayScreen
import com.bukovinafilip.gradey.feature.today.TodayStateScreen
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeyStartupDestination
import com.bukovinafilip.gradey.domain.AbsencePresentationState
import com.bukovinafilip.gradey.domain.AbsencePresentationStates
import com.bukovinafilip.gradey.domain.AbsencePartialDayCandidate
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionFailure
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionProgress
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.SchoolCloudMutationToken
import com.bukovinafilip.gradey.domain.SchoolReconnectPrefill
import com.bukovinafilip.gradey.domain.SchoolReconnectPrefills
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.domain.TodayPresentationStates
import com.bukovinafilip.gradey.domain.RetainedStravaCloudLinkResult
import com.bukovinafilip.gradey.domain.WearPayloadBuilder
import com.bukovinafilip.gradey.domain.canFinishUpgradeOnboarding
import com.bukovinafilip.gradey.domain.linkRetainedStravaSession
import com.bukovinafilip.gradey.domain.refreshRetainingContent
import com.bukovinafilip.gradey.domain.reconcileOnboardingProgress
import com.bukovinafilip.gradey.domain.isCurrentSchoolCloudLinked
import com.bukovinafilip.gradey.domain.selectGradeyStartupDestination
import com.bukovinafilip.gradey.domain.selectRestorableSchoolAccount
import com.bukovinafilip.gradey.domain.selectSchoolAccountRequiringReconnect
import com.bukovinafilip.gradey.domain.shouldShowOnboardingSchoolCloudLinkWarning
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.OnboardingAccountIntent
import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.SupportCatalog
import com.bukovinafilip.gradey.model.SupportEntitlement
import com.bukovinafilip.gradey.model.SupportPlanOption
import com.bukovinafilip.gradey.model.SupportPlanEligibility
import com.bukovinafilip.gradey.model.SupportPurchaseOutcome
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.push.GradeyPushRegistration
import com.bukovinafilip.gradey.network.GradeyJson
import com.bukovinafilip.gradey.navigation.MainDestination
import com.bukovinafilip.gradey.navigation.MainNavigationViewModel
import com.bukovinafilip.gradey.navigation.SignedInNavHost
import com.bukovinafilip.gradey.navigation.navigateFromGradeyAiToAccount
import com.bukovinafilip.gradey.navigation.navigateFromGradeyAiToSupport
import com.bukovinafilip.gradey.navigation.navigateToMainDestination
import com.bukovinafilip.gradey.navigation.resetToToday
import com.bukovinafilip.gradey.widgets.updateNextLessonWidgets
import com.bukovinafilip.gradey.wear.PhoneWearSyncPublisher
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

internal fun activeSchoolSessionForScope(
    requestedSchoolScope: String,
    currentSession: StoredSession?,
): StoredSession? = currentSession?.takeIf { it.cacheScope == requestedSchoolScope }

internal fun shouldRouteToSchoolReconnect(currentSession: StoredSession?): Boolean =
    currentSession == null

internal data class SchoolMutationOwner(
    val gradeyAccountID: String?,
    val isGuestMode: Boolean,
    val gradeyIdentityGeneration: Long,
    val operationToken: Long,
)

internal fun SchoolMutationOwner.isCurrent(
    currentGradeyAccountID: String?,
    currentGuestMode: Boolean,
    currentGradeyIdentityGeneration: Long,
    activeOperationToken: Long?,
): Boolean =
    gradeyAccountID == currentGradeyAccountID &&
        isGuestMode == currentGuestMode &&
        gradeyIdentityGeneration == currentGradeyIdentityGeneration &&
        operationToken == activeOperationToken

internal data class GradeyIdentityOwner(
    val accountID: String,
    val generation: Long,
)

internal fun GradeyIdentityOwner.isCurrent(
    currentAccountID: String?,
    currentGeneration: Long,
    currentGuestMode: Boolean,
): Boolean =
    !currentGuestMode &&
        accountID == currentAccountID &&
        generation == currentGeneration

internal data class OnboardingIdentityOwner(
    val accountID: String?,
    val isGuestMode: Boolean,
    val generation: Long,
)

internal fun OnboardingIdentityOwner.isCurrent(
    currentAccountID: String?,
    currentGuestMode: Boolean,
    currentGeneration: Long,
): Boolean =
    accountID == currentAccountID &&
        isGuestMode == currentGuestMode &&
        generation == currentGeneration

internal data class GradeyIdentityBoundaryState(
    val linkedAccounts: List<LinkedSchoolAccount>,
    val activeLinkedAccountID: String?,
    val notificationPreferences: NotificationPreferences,
)

internal fun GradeyIdentityBoundaryState.cleared(): GradeyIdentityBoundaryState =
    GradeyIdentityBoundaryState(
        linkedAccounts = emptyList(),
        activeLinkedAccountID = null,
        notificationPreferences = NotificationPreferences.Default,
    )

internal fun shouldTrustCachedSchoolAssociation(
    trustCachedAssociation: Boolean,
    session: StoredSession,
    cachedAccounts: List<LinkedSchoolAccount>,
): Boolean =
    trustCachedAssociation &&
        session.linkedAccountID != null &&
        cachedAccounts.any {
            it.id == session.linkedAccountID &&
                it.provider.isSupportedSchoolProvider &&
                it.status == LinkedAccountStatus.ACTIVE
        }

internal fun shouldDetachSchoolAssociationAfterAuthoritativeRefresh(
    session: StoredSession?,
    authoritativeAccounts: List<LinkedSchoolAccount>?,
): Boolean {
    val linkedAccountID = session?.linkedAccountID ?: return false
    return authoritativeAccounts != null &&
        authoritativeAccounts.none { it.id == linkedAccountID }
}

internal suspend fun completeLocalStravaDisconnectBeforeRemoteCleanup(
    takeLocalSessionForSignOut: suspend () -> StravaCZStoredSession?,
    clearVisibleState: () -> Unit,
    captureGradeySessionForCleanup: suspend () -> GradeyAuthSession?,
    launchRemoteCleanup: (StravaCZStoredSession?, GradeyAuthSession?) -> Unit,
) {
    val signedOutStravaSession = try {
        takeLocalSessionForSignOut()
    } finally {
        clearVisibleState()
    }
    val gradeySession = try {
        captureGradeySessionForCleanup()
    } catch (error: CancellationException) {
        launchRemoteCleanup(signedOutStravaSession, null)
        throw error
    } catch (_: Throwable) {
        null
    }
    launchRemoteCleanup(signedOutStravaSession, gradeySession)
}

private const val CURRENT_SCHOOL_LINK_MUTATION_ID = "current-school-link"

class MainActivity : ComponentActivity() {
    private var deepLinkSequence = 0L
    private val deepLinkRequests = MutableStateFlow(DeepLinkRequest())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) acceptDeepLink(intent)
        enableEdgeToEdge()
        setContent {
            val graph = (application as GradeyApplication).graph
            val deepLinkRequest by deepLinkRequests.collectAsStateWithLifecycle()
            var appLanguage by remember { mutableStateOf(graph.appLanguageStore.selection) }
            val localizedContext = remember(appLanguage) {
                graph.appLanguageStore.localizedContext(this@MainActivity, appLanguage)
            }
            CompositionLocalProvider(
                LocalContext provides localizedContext,
                LocalConfiguration provides localizedContext.resources.configuration,
            ) {
                GradeyTheme {
                    GradeyApp(
                        graph = graph,
                        activity = this@MainActivity,
                        appLanguage = appLanguage,
                        onAppLanguageChange = { selection ->
                            graph.appLanguageStore.selection = selection
                            appLanguage = selection
                        },
                        deepLinkRequest = deepLinkRequest,
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptDeepLink(intent)
    }

    private fun acceptDeepLink(intent: Intent?) {
        deepLinkSequence += 1
        deepLinkRequests.value = DeepLinkRequest(
            sequence = deepLinkSequence,
            rawUri = intent.resolvedGradeyLaunchDeepLink(),
        )
    }
}

private enum class AppPhase {
    CHECKING,
    SIGNED_OUT,
    NEEDS_SCHOOL,
    SIGNED_IN,
}

private enum class OnboardingUpgradeCloudLinkState {
    PENDING,
    NOT_ATTEMPTED,
    LINKED,
    FAILED,
}

private enum class OnboardingUpgradeRetryTarget {
    SCHOOL,
    MEALS,
}

private fun android.content.Context.notificationsAreEnabled(): Boolean =
    NotificationManagerCompat.from(this).areNotificationsEnabled() &&
        (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            )

private data class GradeHistorySnapshot(
    val linkedAccountID: String?,
    val trends: List<SubjectGradeTrend>,
    val recentNewMarkEvents: List<NewMarkEvent>,
)

private data class MealsSnapshot(
    val session: StravaCZStoredSession?,
    val menu: StravaCZMenu?,
)

@Composable
private fun GradeyApp(
    graph: com.bukovinafilip.gradey.data.AndroidGradeyGraph,
    activity: ComponentActivity,
    appLanguage: AppLanguage,
    onAppLanguageChange: (AppLanguage) -> Unit,
    deepLinkRequest: DeepLinkRequest,
) {
    val context = LocalContext.current
    val activeLanguageCode = LocalConfiguration.current.locales[0].language
    val scope = rememberCoroutineScope()
    val signedInNavController = rememberNavController()
    val navigationViewModel: MainNavigationViewModel = viewModel()
    val pendingNavigationRoute by navigationViewModel.pendingDestinationRoute.collectAsStateWithLifecycle()
    val dashboardViewModel: SignedInDashboardViewModel = viewModel()
    val dashboardState by dashboardViewModel.state.collectAsStateWithLifecycle()
    val marksRefreshError = dashboardState.failure?.userFacingMessage(context)
    val signedInBackStackEntry by signedInNavController.currentBackStackEntryAsState()
    val currentMainDestination = MainDestination.fromRoute(
        signedInBackStackEntry?.destination?.route,
    ) ?: MainDestination.TODAY
    var phase by remember { mutableStateOf(AppPhase.CHECKING) }
    var resetSignedInNavigationOnReady by rememberSaveable { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(false) }
    var authError by remember { mutableStateOf<String?>(null) }
    var schoolLoginError by remember { mutableStateOf<String?>(null) }
    var schoolDirectoryError by remember { mutableStateOf<String?>(null) }
    var dataError by remember { mutableStateOf<String?>(null) }
    var absenceRefreshError by remember { mutableStateOf<String?>(null) }
    var profileError by remember { mutableStateOf<String?>(null) }
    var isUpdatingProfile by remember { mutableStateOf(false) }
    var isExportingData by remember { mutableStateOf(false) }
    var isDeletingAccount by remember { mutableStateOf(false) }
    var privacyDataError by remember { mutableStateOf<String?>(null) }
    val supportService = remember { RevenueCatSupportService() }
    var supportCatalog by remember { mutableStateOf<SupportCatalog?>(null) }
    var supportTier by remember { mutableStateOf(GradeySupportTier.NONE) }
    var resolvedSupportIdentityKey by remember { mutableStateOf<String?>(null) }
    var isSupportLoading by remember { mutableStateOf(false) }
    var purchasingSupportOptionID by remember { mutableStateOf<String?>(null) }
    var isRestoringSupport by remember { mutableStateOf(false) }
    var supportMessage by remember { mutableStateOf<String?>(null) }
    var ageAttestationKind by remember { mutableStateOf(graph.ageAttestationStore.kind) }
    var isGuestMode by remember { mutableStateOf(graph.guestModeStore.isEnabled) }
    var onboardingProgress by remember { mutableStateOf<OnboardingProgress?>(null) }
    var onboardingAccountIntent by rememberSaveable {
        mutableStateOf(OnboardingAccountIntent.GET_STARTED)
    }
    var account by remember { mutableStateOf<GradeyAccount?>(null) }
    var gradeyIdentityGeneration by remember { mutableLongStateOf(0L) }
    val onboardingUpgradeIdentityKey = when {
        isGuestMode -> "guest:$gradeyIdentityGeneration"
        account != null -> "account:${account?.id}:$gradeyIdentityGeneration"
        else -> "signed-out:$gradeyIdentityGeneration"
    }
    var onboardingUpgradeSchoolCloudLinkState by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf(OnboardingUpgradeCloudLinkState.PENDING)
    }
    var onboardingUpgradeMealsCloudLinkState by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf(OnboardingUpgradeCloudLinkState.PENDING)
    }
    var onboardingUpgradeSchoolCloudLinkError by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf<String?>(null)
    }
    var onboardingUpgradeMealsCloudLinkError by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf<String?>(null)
    }
    var onboardingUpgradeCloudLinkAttempt by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableIntStateOf(0)
    }
    var isOnboardingUpgradeCloudLinkWorking by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf(false)
    }
    var onboardingUpgradeRetryTarget by remember(
        onboardingProgress?.journey,
        onboardingUpgradeIdentityKey,
    ) {
        mutableStateOf<OnboardingUpgradeRetryTarget?>(null)
    }
    var accountSettingsDestination by rememberSaveable(account?.id, isGuestMode) {
        mutableStateOf<AccountSettingsDestination?>(null)
    }
    fun resetSignedInNavigation() {
        accountSettingsDestination = null
        resetSignedInNavigationOnReady = true
        if (phase == AppPhase.SIGNED_IN && signedInBackStackEntry != null) {
            signedInNavController.resetToToday()
            resetSignedInNavigationOnReady = false
        }
    }
    var linkedAccounts by remember { mutableStateOf<List<LinkedSchoolAccount>>(emptyList()) }
    var activeLinkedAccountID by remember { mutableStateOf<String?>(null) }
    var currentSchoolBaseURL by remember { mutableStateOf("") }
    var reconnectLinkedAccount by remember { mutableStateOf<LinkedSchoolAccount?>(null) }
    var reconnectLinkedAccountID by rememberSaveable { mutableStateOf<String?>(null) }
    var reconnectSchoolURL by remember { mutableStateOf("") }
    var reconnectSchoolName by remember { mutableStateOf("") }
    var reconnectSchoolUsername by remember { mutableStateOf("") }
    var isAddingSchool by rememberSaveable { mutableStateOf(false) }
    var linkedAccountError by remember { mutableStateOf<String?>(null) }
    var onboardingSchoolCloudLinkFailed by rememberSaveable { mutableStateOf(false) }
    var onboardingSchoolCloudLinkError by remember { mutableStateOf<String?>(null) }
    var isRetryingOnboardingSchoolCloudLink by remember { mutableStateOf(false) }
    var onboardingNotificationsReturnToReady by rememberSaveable { mutableStateOf(false) }
    var isRefreshingLinkedAccounts by remember { mutableStateOf(false) }
    var mutatingLinkedAccountID by remember { mutableStateOf<String?>(null) }
    var linkedAccountMutationSequence by remember { mutableLongStateOf(0L) }
    var activeLinkedAccountMutationToken by remember { mutableStateOf<Long?>(null) }
    var gradeyIdentityBoundarySequence by remember { mutableLongStateOf(0L) }
    var activeGradeyIdentityBoundaryTokens by remember { mutableStateOf<Set<Long>>(emptySet()) }
    var schoolLoginJob by remember { mutableStateOf<Job?>(null) }
    var schoolLoginAttempt by remember { mutableIntStateOf(0) }
    var directorySchools by remember { mutableStateOf<List<SchoolDirectorySchool>>(emptyList()) }
    var isSchoolDirectoryLoading by remember { mutableStateOf(false) }
    var hasLoadedSchoolDirectory by remember { mutableStateOf(false) }

    fun applyReconnectPrefill(prefill: SchoolReconnectPrefill?) {
        reconnectSchoolURL = prefill?.schoolURL.orEmpty()
        reconnectSchoolName = prefill?.schoolName.orEmpty()
        reconnectSchoolUsername = prefill?.username.orEmpty()
    }

    suspend fun reconnectPrefillFor(account: LinkedSchoolAccount): SchoolReconnectPrefill? = try {
        SchoolReconnectPrefills.resolve(
            session = graph.schoolRepository.currentStoredSession(),
            account = account,
            accounts = linkedAccounts,
        )
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        null
    }
    var absence by remember { mutableStateOf<AbsenceResponse?>(null) }
    var absenceSourceResponse by remember { mutableStateOf<AbsenceResponse?>(null) }
    var isResolvingAbsenceSubjects by remember { mutableStateOf(false) }
    var absenceSubjectProgress by remember { mutableStateOf<AbsenceSubjectResolutionProgress?>(null) }
    var absenceSubjectWarning by remember { mutableStateOf<String?>(null) }
    var absenceSubjectError by remember { mutableStateOf<String?>(null) }
    var absencePartialDays by remember { mutableStateOf<List<AbsencePartialDayCandidate>>(emptyList()) }
    var absenceSubjectResolutionJob by remember { mutableStateOf<Job?>(null) }
    var absenceSubjectResolutionAttempt by remember { mutableIntStateOf(0) }
    var timetable by remember { mutableStateOf<TimetableWeek?>(null) }
    var timetableRequestedWeek by rememberSaveable { mutableStateOf(TimetableDates.todayString()) }
    var timetableError by remember { mutableStateOf<String?>(null) }
    var stravaSession by remember { mutableStateOf<StravaCZStoredSession?>(null) }
    var stravaMenu by remember { mutableStateOf<StravaCZMenu?>(null) }
    var stravaError by remember { mutableStateOf<String?>(null) }
    var isStravaLoading by remember { mutableStateOf(false) }
    var isStravaRefreshing by remember { mutableStateOf(false) }
    var isRetryingStravaCloudLink by remember { mutableStateOf(false) }
    var submittingStravaMealID by remember { mutableStateOf<Int?>(null) }
    var showMealsTab by remember { mutableStateOf(graph.mealsTabPreferenceStore.isVisible) }
    var gradeHistorySnapshot by remember { mutableStateOf<GradeHistorySnapshot?>(null) }
    var gradeHistoryRefreshError by remember { mutableStateOf<String?>(null) }
    var notificationPreferences by remember {
        mutableStateOf(graph.notificationPreferencesStore.preferences)
    }
    var isUpdatingNotificationPreferences by remember { mutableStateOf(false) }
    var notificationPreferencesError by remember { mutableStateOf<String?>(null) }
    var isHandlingOnboardingNotificationChoice by remember { mutableStateOf(false) }
    var notificationPermissionRequestOwner by remember {
        mutableStateOf<OnboardingIdentityOwner?>(null)
    }
    var notificationSettingsRequestOwner by remember {
        mutableStateOf<OnboardingIdentityOwner?>(null)
    }
    var notificationPermissionGranted by remember {
        mutableStateOf(context.notificationsAreEnabled())
    }

    fun isGradeyIdentityBoundaryChanging(): Boolean =
        activeGradeyIdentityBoundaryTokens.isNotEmpty()

    fun currentGradeyIdentityOwner(): GradeyIdentityOwner? {
        if (isGradeyIdentityBoundaryChanging()) return null
        val accountID = account?.id ?: return null
        if (isGuestMode) return null
        return GradeyIdentityOwner(accountID, gradeyIdentityGeneration)
    }

    fun currentOnboardingIdentityOwner(): OnboardingIdentityOwner? {
        if (isGradeyIdentityBoundaryChanging()) return null
        return OnboardingIdentityOwner(
            accountID = account?.id,
            isGuestMode = isGuestMode,
            generation = gradeyIdentityGeneration,
        )
    }

    fun beginSchoolMutation(linkedAccountID: String): SchoolMutationOwner? {
        if (isGradeyIdentityBoundaryChanging() || activeLinkedAccountMutationToken != null) return null
        linkedAccountMutationSequence += 1
        val owner = SchoolMutationOwner(
            gradeyAccountID = account?.id,
            isGuestMode = isGuestMode,
            gradeyIdentityGeneration = gradeyIdentityGeneration,
            operationToken = linkedAccountMutationSequence,
        )
        activeLinkedAccountMutationToken = owner.operationToken
        mutatingLinkedAccountID = linkedAccountID
        linkedAccountError = null
        return owner
    }

    fun SchoolMutationOwner.isCurrent(): Boolean = isCurrent(
        currentGradeyAccountID = account?.id,
        currentGuestMode = isGuestMode,
        currentGradeyIdentityGeneration = gradeyIdentityGeneration,
        activeOperationToken = activeLinkedAccountMutationToken,
    )

    fun SchoolMutationOwner.requireCurrent() {
        if (!isCurrent()) throw GradeyIdentityChangedException()
    }

    fun GradeyIdentityOwner.isCurrent(): Boolean = isCurrent(
        currentAccountID = account?.id,
        currentGeneration = gradeyIdentityGeneration,
        currentGuestMode = isGuestMode,
    )

    fun GradeyIdentityOwner.requireCurrent() {
        if (!isCurrent()) throw GradeyIdentityChangedException()
    }

    fun OnboardingIdentityOwner.isCurrent(): Boolean =
        !isGradeyIdentityBoundaryChanging() &&
            isCurrent(
                currentAccountID = account?.id,
                currentGuestMode = isGuestMode,
                currentGeneration = gradeyIdentityGeneration,
            )

    fun OnboardingIdentityOwner.requireCurrent() {
        if (!isCurrent()) throw GradeyIdentityChangedException()
    }

    fun finishSchoolMutation(owner: SchoolMutationOwner) {
        if (!owner.isCurrent()) return
        activeLinkedAccountMutationToken = null
        mutatingLinkedAccountID = null
    }

    fun invalidateGradeyIdentityWork(): Long {
        gradeyIdentityBoundarySequence += 1
        val boundaryToken = gradeyIdentityBoundarySequence
        activeGradeyIdentityBoundaryTokens = activeGradeyIdentityBoundaryTokens + boundaryToken
        gradeyIdentityGeneration += 1
        isRefreshingLinkedAccounts = false
        isUpdatingNotificationPreferences = false
        isRetryingStravaCloudLink = false
        isUpdatingProfile = false
        isExportingData = false
        isDeletingAccount = false
        profileError = null
        privacyDataError = null
        isHandlingOnboardingNotificationChoice = false
        notificationPermissionRequestOwner = null
        notificationSettingsRequestOwner = null
        schoolLoginAttempt += 1
        schoolLoginJob?.cancel()
        schoolLoginJob = null
        schoolLoginError = null
        activeLinkedAccountMutationToken = null
        mutatingLinkedAccountID = null
        linkedAccountError = null
        return boundaryToken
    }

    fun finishGradeyIdentityBoundaryChange(boundaryToken: Long) {
        activeGradeyIdentityBoundaryTokens = activeGradeyIdentityBoundaryTokens - boundaryToken
    }

    var onboardingNotificationNeedsSystemSettings by rememberSaveable {
        mutableStateOf(graph.onboardingProgressStore.notificationPermissionRecoveryNeeded)
    }
    var onboardingNotificationPreferenceSyncPending by remember {
        mutableStateOf(graph.onboardingProgressStore.notificationPreferenceSyncPending)
    }
    var onboardingNotificationPushRegistrationPending by remember {
        mutableStateOf(graph.onboardingProgressStore.notificationPushRegistrationPending)
    }
    fun setOnboardingNotificationPermissionRecoveryNeeded(value: Boolean) {
        onboardingNotificationNeedsSystemSettings = value
        if (value) {
            account?.id?.let { ownerAccountID ->
                graph.onboardingProgressStore.notificationSyncOwnerAccountID = ownerAccountID
            }
        }
        graph.onboardingProgressStore.notificationPermissionRecoveryNeeded = value
        if (
            !value &&
            !onboardingNotificationPreferenceSyncPending &&
            !onboardingNotificationPushRegistrationPending
        ) {
            graph.onboardingProgressStore.notificationSyncOwnerAccountID = null
        }
    }
    fun setOnboardingNotificationPreferenceSyncPending(value: Boolean) {
        onboardingNotificationPreferenceSyncPending = value
        if (value) {
            account?.id?.let { ownerAccountID ->
                graph.onboardingProgressStore.notificationSyncOwnerAccountID = ownerAccountID
            }
        }
        graph.onboardingProgressStore.notificationPreferenceSyncPending = value
        if (
            !value &&
            !onboardingNotificationNeedsSystemSettings &&
            !onboardingNotificationPushRegistrationPending
        ) {
            graph.onboardingProgressStore.notificationSyncOwnerAccountID = null
        }
    }
    fun setOnboardingNotificationPushRegistrationPending(value: Boolean) {
        onboardingNotificationPushRegistrationPending = value
        if (value) {
            account?.id?.let { ownerAccountID ->
                graph.onboardingProgressStore.notificationSyncOwnerAccountID = ownerAccountID
            }
        }
        graph.onboardingProgressStore.notificationPushRegistrationPending = value
        if (
            !value &&
            !onboardingNotificationNeedsSystemSettings &&
            !onboardingNotificationPreferenceSyncPending
        ) {
            graph.onboardingProgressStore.notificationSyncOwnerAccountID = null
        }
    }
    fun clearOnboardingNotificationRecovery() {
        graph.onboardingProgressStore.clearNotificationRecovery()
        onboardingNotificationNeedsSystemSettings = false
        onboardingNotificationPreferenceSyncPending = false
        onboardingNotificationPushRegistrationPending = false
    }

    suspend fun clearSchoolPlatformProjectionsAfterAccountChange(
        onlyWhileSignedOut: Boolean = false,
        isStillCurrent: () -> Boolean = { true },
    ) = withContext(NonCancellable) {
        if (!isStillCurrent()) return@withContext
        val shouldPublishSignedOut = if (onlyWhileSignedOut) {
            // This check and clear share the repository's session/publication mutex. A replacement
            // session therefore either prevents the clear or commits after it; old cleanup cannot
            // delete a newly published widget snapshot.
            graph.schoolRepository.clearNextLessonSnapshotIfSignedOut()
        } else {
            try {
                graph.cache?.clearNextLessonSnapshot()
            } catch (_: Throwable) {
                // A disposable widget-cache failure must not block the authoritative account change.
            }
            true
        }
        if (!shouldPublishSignedOut || !isStillCurrent()) return@withContext
        try {
            updateNextLessonWidgets(context.applicationContext)
        } catch (_: Throwable) {
            // A launcher host failure must not undo activation or reconnect routing.
        }
        if (!isStillCurrent()) return@withContext
        try {
            PhoneWearSyncPublisher.publish(
                context.applicationContext,
                com.bukovinafilip.gradey.model.GradeyWearSyncPayload.signedOut(),
                isStillCurrent = {
                    isStillCurrent() &&
                        (!onlyWhileSignedOut || graph.schoolRepository.currentStoredSession() == null)
                },
            )
        } catch (_: Throwable) {
            // The phone session is authoritative even when no Wear OS device is paired.
        }
    }

    suspend fun clearGradeyIdentityBoundaryState() {
        val cleared = GradeyIdentityBoundaryState(
            linkedAccounts = linkedAccounts,
            activeLinkedAccountID = activeLinkedAccountID,
            notificationPreferences = notificationPreferences,
        ).cleared()
        linkedAccounts = cleared.linkedAccounts
        activeLinkedAccountID = cleared.activeLinkedAccountID
        notificationPreferences = cleared.notificationPreferences
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        notificationPreferencesError = null
        isUpdatingNotificationPreferences = false
        graph.pushRegistrationStore.clear()
        graph.notificationPreferencesStore.clear()
        clearOnboardingNotificationRecovery()
        val schoolInvalidation = try {
            graph.schoolRepository.invalidateSchoolCloudMutationsAndDisassociate()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            try {
                graph.schoolRepository.logout()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // The visible identity boundary still fails closed below. The repository's cloud
                // mutation epoch was invalidated before its suspended persistence work began.
            }
            null
        }
        if (schoolInvalidation == null) {
            dashboardViewModel.clear()
            currentSchoolBaseURL = ""
            clearSchoolPlatformProjectionsAfterAccountChange(onlyWhileSignedOut = true)
        } else {
            val result = schoolInvalidation
            val retainedSession = result.retainedSession
            if (retainedSession == null) {
                dashboardViewModel.clear()
                currentSchoolBaseURL = ""
                clearSchoolPlatformProjectionsAfterAccountChange(onlyWhileSignedOut = true)
            } else {
                dashboardViewModel.adoptScope(retainedSession.cacheScope)
                currentSchoolBaseURL = retainedSession.baseURL
            }
        }
        try {
            graph.historyRepository.clearAllCachedGradeHistory()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Cloud history is disposable; the visible identity boundary is already clear.
        }
        try {
            graph.linkedAccountRepository.clearLocalAccounts()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // The in-memory identity boundary remains authoritative if the optional snapshot is damaged.
        }
    }

    suspend fun expireGradeyIdentity(error: GradeySessionExpiredException) {
        val boundaryToken = invalidateGradeyIdentityWork()
        try {
            withContext(NonCancellable) {
                clearGradeyIdentityBoundaryState()
                // A rejected cloud session cannot authenticate an unregister call. Invalidate the local
                // FCM token so delivery to the former account's still-active backend row starts failing.
                GradeyPushRegistration.invalidateCurrentToken()
            }
        } finally {
            account = null
            authError = error.userFacingMessage(context)
            resetSignedInNavigation()
            phase = AppPhase.SIGNED_OUT
            finishGradeyIdentityBoundaryChange(boundaryToken)
        }
    }

    suspend fun prepareForInteractiveGradeyIdentityAdoption(): Long {
        val boundaryToken = invalidateGradeyIdentityWork()
        try {
            withContext(NonCancellable) {
                clearGradeyIdentityBoundaryState()
            }
            return boundaryToken
        } catch (error: Throwable) {
            finishGradeyIdentityBoundaryChange(boundaryToken)
            throw error
        }
    }

    suspend fun persistOnboardingNotificationPreference(
        enabled: Boolean,
        owner: OnboardingIdentityOwner,
    ): Boolean {
        if (!owner.isCurrent()) return false
        val updated = prepareNotificationPreferencesForUpdate(
            preferences = onboardingNotificationPreferences(notificationPreferences, enabled),
            timeZoneID = ZoneId.systemDefault().id,
        )
        owner.requireCurrent()
        notificationPreferences = updated
        graph.notificationPreferencesStore.preferences = updated
        notificationPreferencesError = null

        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) {
            owner.requireCurrent()
            setOnboardingNotificationPreferenceSyncPending(false)
            setOnboardingNotificationPushRegistrationPending(false)
            return true
        }
        owner.requireCurrent()
        if (!updated.newMarksEnabled || !notificationPermissionGranted) {
            setOnboardingNotificationPushRegistrationPending(false)
        }
        setOnboardingNotificationPreferenceSyncPending(true)
        return try {
            owner.requireCurrent()
            val session = graph.gradeyAuthRepository.validSession()
            owner.requireCurrent()
            graph.devicePushTokenClient.updateNotificationPreferences(updated, session)
            owner.requireCurrent()
            setOnboardingNotificationPreferenceSyncPending(false)
            true
        } catch (_: GradeyIdentityChangedException) {
            false
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (owner.isCurrent()) {
                expireGradeyIdentity(error)
                if (account == null && !isGuestMode && !isGradeyIdentityBoundaryChanging()) {
                    onboardingProgress?.let { current ->
                        val accountStep = current.copy(step = OnboardingStep.ACCOUNT)
                        graph.onboardingProgressStore.saveProgress(accountStep)
                        onboardingProgress = accountStep
                    }
                }
            }
            false
        } catch (error: Throwable) {
            // Keep the local choice and surface a retryable warning on Ready.
            if (owner.isCurrent()) {
                notificationPreferencesError = error.userFacingMessage(context)
                true
            } else {
                false
            }
        }
    }
    suspend fun refreshOnboardingPushRegistration(owner: OnboardingIdentityOwner) {
        if (!owner.isCurrent()) return
        setOnboardingNotificationPushRegistrationPending(true)
        try {
            owner.requireCurrent()
            if (GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph)) {
                owner.requireCurrent()
                setOnboardingNotificationPushRegistrationPending(false)
                if (!onboardingNotificationPreferenceSyncPending) {
                    notificationPreferencesError = null
                }
            }
        } catch (_: GradeyIdentityChangedException) {
            // A replacement identity owns the recovery flags and visible error state.
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (owner.isCurrent()) {
                notificationPreferencesError = error.userFacingMessage(context)
            }
        }
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val owner = notificationPermissionRequestOwner
        notificationPermissionRequestOwner = null
        if (owner != null && owner.isCurrent()) {
            isHandlingOnboardingNotificationChoice = true
            notificationPermissionGranted = granted || context.notificationsAreEnabled()
            if (!notificationPermissionGranted) {
                setOnboardingNotificationPermissionRecoveryNeeded(true)
            }
            scope.launch {
                try {
                    val canAdvance = persistOnboardingNotificationPreference(
                        notificationPermissionGranted,
                        owner,
                    )
                    if (!owner.isCurrent()) return@launch
                    if (notificationPermissionGranted) {
                        setOnboardingNotificationPermissionRecoveryNeeded(false)
                    }
                    if (canAdvance) {
                        owner.requireCurrent()
                        val current = onboardingProgress ?: graph.onboardingProgressStore.loadProgress()
                        owner.requireCurrent()
                        if (current?.step == OnboardingStep.NOTIFICATIONS) {
                            onboardingNotificationsReturnToReady = false
                            val ready = current.copy(step = OnboardingStep.READY)
                            graph.onboardingProgressStore.saveProgress(ready)
                            onboardingProgress = ready
                        }
                    }
                    if (canAdvance && notificationPermissionGranted) {
                        refreshOnboardingPushRegistration(owner)
                    }
                } finally {
                    if (owner.isCurrent()) {
                        isHandlingOnboardingNotificationChoice = false
                    }
                }
            }
        }
    }
    val notificationSettingsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        val owner = notificationSettingsRequestOwner
        notificationSettingsRequestOwner = null
        if (owner != null && owner.isCurrent()) {
            notificationPermissionGranted = context.notificationsAreEnabled()
            val currentProgress = onboardingProgress ?: graph.onboardingProgressStore.loadProgress()
            val shouldEnableFromOnboarding =
                currentProgress?.step == OnboardingStep.READY &&
                (
                    onboardingNotificationNeedsSystemSettings ||
                        graph.onboardingProgressStore.notificationPermissionRecoveryNeeded
                    ) &&
                notificationPermissionGranted
            if (shouldEnableFromOnboarding && !isHandlingOnboardingNotificationChoice) {
                isHandlingOnboardingNotificationChoice = true
                scope.launch {
                    try {
                        val canContinue = persistOnboardingNotificationPreference(
                            enabled = true,
                            owner = owner,
                        )
                        if (!owner.isCurrent()) return@launch
                        setOnboardingNotificationPermissionRecoveryNeeded(false)
                        if (canContinue) {
                            refreshOnboardingPushRegistration(owner)
                        }
                    } finally {
                        if (owner.isCurrent()) {
                            isHandlingOnboardingNotificationChoice = false
                        }
                    }
                }
            } else if (notificationPermissionGranted) {
                scope.launch {
                    if (owner.isCurrent()) {
                        GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph)
                    }
                }
            }
        }
    }

    LaunchedEffect(deepLinkRequest.sequence, deepLinkRequest.rawUri) {
        if (deepLinkRequest.sequence > 0L) {
            navigationViewModel.acceptDeepLink(deepLinkRequest.rawUri)
        }
    }

    LaunchedEffect(
        phase,
        pendingNavigationRoute,
        resetSignedInNavigationOnReady,
        signedInBackStackEntry,
    ) {
        if (phase != AppPhase.SIGNED_IN || signedInBackStackEntry == null) {
            return@LaunchedEffect
        }
        if (resetSignedInNavigationOnReady) {
            signedInNavController.resetToToday()
            resetSignedInNavigationOnReady = false
        }
        val route = pendingNavigationRoute ?: return@LaunchedEffect
        val destination = MainDestination.fromRoute(route) ?: run {
            navigationViewModel.consumePendingDestination(route)
            return@LaunchedEffect
        }
        signedInNavController.navigateToMainDestination(destination)
        navigationViewModel.consumePendingDestination(route)
    }

    LaunchedEffect(account?.id, notificationPermissionGranted) {
        if (account != null && notificationPermissionGranted) {
            GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph)
        }
    }

    LaunchedEffect(
        phase,
        account?.id,
        isGuestMode,
        gradeyIdentityGeneration,
        notificationPermissionGranted,
    ) {
        if (phase == AppPhase.CHECKING) return@LaunchedEffect
        val notificationOwner = currentOnboardingIdentityOwner() ?: return@LaunchedEffect
        val currentAccountID = account?.id
        val hasPendingNotificationRecovery =
            onboardingNotificationNeedsSystemSettings ||
                onboardingNotificationPreferenceSyncPending ||
                onboardingNotificationPushRegistrationPending
        if (
            hasPendingNotificationRecovery &&
            currentAccountID != null &&
            graph.onboardingProgressStore.notificationSyncOwnerAccountID != currentAccountID
        ) {
            clearOnboardingNotificationRecovery()
            return@LaunchedEffect
        }
        if (
            (
                onboardingNotificationPreferenceSyncPending ||
                    onboardingNotificationPushRegistrationPending
                ) &&
            account != null &&
            !isGuestMode &&
            graph.isGradeyCloudConfigured &&
            !isHandlingOnboardingNotificationChoice
        ) {
            isHandlingOnboardingNotificationChoice = true
            try {
                val canContinue = persistOnboardingNotificationPreference(
                    enabled = notificationPreferences.newMarksEnabled,
                    owner = notificationOwner,
                )
                if (!notificationOwner.isCurrent()) return@LaunchedEffect
                val current = onboardingProgress ?: graph.onboardingProgressStore.loadProgress()
                if (!notificationOwner.isCurrent()) return@LaunchedEffect
                if (
                    canContinue &&
                    !onboardingNotificationPreferenceSyncPending &&
                    current?.step == OnboardingStep.NOTIFICATIONS
                ) {
                    val ready = current.copy(step = OnboardingStep.READY)
                    graph.onboardingProgressStore.saveProgress(ready)
                    onboardingProgress = ready
                }
                if (
                    canContinue &&
                    notificationPreferences.newMarksEnabled &&
                    notificationPermissionGranted
                ) {
                    refreshOnboardingPushRegistration(notificationOwner)
                }
            } finally {
                if (notificationOwner.isCurrent()) {
                    isHandlingOnboardingNotificationChoice = false
                }
            }
        }
    }

    suspend fun runWithLoading(block: suspend () -> Unit) {
        if (isLoading) return
        isLoading = true
        try {
            block()
        } finally {
            isLoading = false
        }
    }

    fun launchSchoolLogin(block: suspend () -> Unit) {
        val identityOwner = currentOnboardingIdentityOwner() ?: return
        schoolLoginAttempt += 1
        val attempt = schoolLoginAttempt
        schoolLoginJob?.cancel()
        schoolLoginJob = scope.launch {
            isLoading = true
            schoolLoginError = null
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (identityOwner.isCurrent()) {
                    schoolLoginError = error.userFacingMessage(context)
                }
            } finally {
                if (identityOwner.isCurrent() && attempt == schoolLoginAttempt) {
                    isLoading = false
                    schoolLoginJob = null
                }
            }
        }
    }

    fun cancelSchoolLogin() {
        schoolLoginAttempt += 1
        schoolLoginJob?.cancel()
        schoolLoginJob = null
        schoolLoginError = null
        isLoading = false
    }

    fun resetAbsenceSubjectResolution() {
        absenceSubjectResolutionAttempt += 1
        absenceSubjectResolutionJob?.cancel()
        absenceSubjectResolutionJob = null
        absenceSourceResponse = null
        isResolvingAbsenceSubjects = false
        absenceSubjectProgress = null
        absenceSubjectWarning = null
        absenceSubjectError = null
        absencePartialDays = emptyList()
    }

    fun resetTimetableState() {
        timetable = null
        timetableRequestedWeek = TimetableDates.todayString()
        timetableError = null
    }

    fun clearSchoolPresentationAfterAccountChange(scopeKey: String? = null) {
        dashboardViewModel.switchScope(scopeKey)
        absence = null
        resetAbsenceSubjectResolution()
        absenceRefreshError = null
        resetTimetableState()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
    }

    suspend fun routeToSchoolReconnect() {
        // A stale request from account A can report its terminal expiry after account B has already
        // been activated. In that case B is authoritative and the old continuation must not tear it
        // down or publish signed-out state over it.
        if (!shouldRouteToSchoolReconnect(graph.schoolRepository.currentStoredSession())) return
        dashboardViewModel.expireSession()
        absence = null
        resetAbsenceSubjectResolution()
        resetTimetableState()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        activeLinkedAccountID = null
        currentSchoolBaseURL = ""
        reconnectLinkedAccount = null
        reconnectLinkedAccountID = null
        applyReconnectPrefill(null)
        isAddingSchool = false
        resetSignedInNavigation()
        dataError = null
        absenceRefreshError = null
        schoolLoginError = context.getString(R.string.school_session_expired)
        phase = AppPhase.NEEDS_SCHOOL
        clearSchoolPlatformProjectionsAfterAccountChange(onlyWhileSignedOut = true)
    }

    suspend fun <T> withSchoolSessionRecovery(block: suspend () -> T): T = try {
        block()
    } catch (error: SchoolSessionExpiredException) {
        routeToSchoolReconnect()
        throw error
    }

    fun startAbsenceSubjectResolution(response: AbsenceResponse) {
        absenceSubjectResolutionAttempt += 1
        val attempt = absenceSubjectResolutionAttempt
        absenceSubjectResolutionJob?.cancel()
        absenceSourceResponse = response
        absence = response
        absenceSubjectProgress = null
        absenceSubjectWarning = null
        absenceSubjectError = null
        absencePartialDays = emptyList()

        if (response.absencesPerSubject.isNotEmpty() || response.absences.isEmpty()) {
            isResolvingAbsenceSubjects = false
            absenceSubjectResolutionJob = null
            return
        }

        isResolvingAbsenceSubjects = true
        absenceSubjectResolutionJob = scope.launch {
            try {
                val resolution = graph.schoolRepository.resolveAbsenceSubjects(response) { progress ->
                    if (attempt == absenceSubjectResolutionAttempt) absenceSubjectProgress = progress
                }
                if (attempt != absenceSubjectResolutionAttempt) return@launch
                if (resolution.failure == AbsenceSubjectResolutionFailure.NO_USABLE_TIMETABLE) {
                    absenceSubjectError = context.getString(AbsenceR.string.absence_subjects_error_no_timetable)
                } else {
                    absence = response.copy(absencesPerSubject = resolution.subjects)
                    absencePartialDays = resolution.unresolvedPartialDays
                    if (resolution.isPartial) {
                        absenceSubjectWarning = context.getString(AbsenceR.string.absence_subjects_partial_warning)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: SchoolSessionExpiredException) {
                if (attempt == absenceSubjectResolutionAttempt) routeToSchoolReconnect()
            } catch (error: Throwable) {
                if (attempt == absenceSubjectResolutionAttempt) {
                    absenceSubjectError = error.userFacingMessage(context)
                }
            } finally {
                if (attempt == absenceSubjectResolutionAttempt) {
                    isResolvingAbsenceSubjects = false
                    absenceSubjectResolutionJob = null
                }
            }
        }
    }

    suspend fun saveManualAbsenceSelections(selections: Map<String, Set<String>>): String? = try {
        graph.schoolRepository.saveManualAbsenceLessonSelections(selections)
        absenceSourceResponse?.let(::startAbsenceSubjectResolution)
        null
    } catch (error: CancellationException) {
        throw error
    } catch (error: SchoolSessionExpiredException) {
        routeToSchoolReconnect()
        error.userFacingMessage(context)
    } catch (error: Throwable) {
        error.userFacingMessage(context)
    }

    suspend fun loadCachedSignedInData(isStillCurrent: () -> Boolean) {
        fun requireCurrent() {
            if (!isStillCurrent()) throw GradeyIdentityChangedException()
        }

        requireCurrent()
        val storedSession = graph.schoolRepository.currentStoredSession()
        requireCurrent()
        activeLinkedAccountID = storedSession?.linkedAccountID
        currentSchoolBaseURL = storedSession?.baseURL.orEmpty()
        dashboardViewModel.loadCached(
            scopeKey = storedSession?.cacheScope,
            load = graph.schoolRepository::loadCachedDashboard,
        )
        requireCurrent()
        val cachedAbsence = graph.schoolRepository.loadCachedAbsence()
        requireCurrent()
        cachedAbsence?.let(::startAbsenceSubjectResolution)
        val cachedTimetable = graph.schoolRepository.loadCachedTimetable(timetableRequestedWeek)
        requireCurrent()
        cachedTimetable?.let {
            timetable = it
            timetableRequestedWeek = it.weekStart
        }
        val cachedStravaSession = try {
            graph.stravaCZRepository.bootstrapSession()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        requireCurrent()
        stravaSession = cachedStravaSession
        val cachedMenu = graph.stravaCZRepository.loadCachedMenu()
        requireCurrent()
        cachedMenu?.let { stravaMenu = it }
        val cachedLinkedAccounts = try {
            graph.linkedAccountRepository.localAccounts()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            emptyList()
        }
        requireCurrent()
        linkedAccounts = cachedLinkedAccounts
        val linkedAccountID = storedSession?.linkedAccountID
        if (account != null && !isGuestMode && graph.isGradeyCloudConfigured && linkedAccountID != null) {
            val cachedHistory = graph.historyRepository.loadCachedGradeHistory(linkedAccountID)
            requireCurrent()
            cachedHistory?.let { history ->
                gradeHistorySnapshot = GradeHistorySnapshot(
                    linkedAccountID = linkedAccountID,
                    trends = GradeHistoryTrends.make(history.events),
                    recentNewMarkEvents = history.recentNewMarkEvents,
                )
            }
        }
    }

    suspend fun linkCurrentStravaAccountIfNeeded(session: StravaCZStoredSession): Boolean {
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) return false
        val linkOwner = currentGradeyIdentityOwner() ?: return false
        return try {
            // Re-link even when a cached record exists so the cloud receives the current
            // Strava session from this device, matching the iOS reconnect contract.
            linkOwner.requireCurrent()
            graph.linkedAccountRepository.linkStravaCZAccount(session)
            linkOwner.requireCurrent()
            val refreshedAccounts = graph.linkedAccountRepository.localAccounts()
            linkOwner.requireCurrent()
            linkedAccounts = refreshedAccounts
            linkedAccountError = null
            true
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!linkOwner.isCurrent()) throw GradeyIdentityChangedException()
            // The local meals connection remains usable if optional cloud linking fails.
            linkedAccountError = error.userFacingMessage(context)
            false
        }
    }

    suspend fun retryStravaCloudLink() {
        val session = stravaSession ?: return
        if (isRetryingStravaCloudLink) return
        val retryOwner = currentGradeyIdentityOwner() ?: return
        isRetryingStravaCloudLink = true
        try {
            linkCurrentStravaAccountIfNeeded(session)
        } finally {
            if (retryOwner.isCurrent()) isRetryingStravaCloudLink = false
        }
    }

    suspend fun connectStravaCZ(canteenNumber: String, username: String, password: String) {
        if (isStravaLoading) return
        isStravaLoading = true
        stravaError = null
        try {
            val session = graph.stravaCZRepository.login(canteenNumber, username, password)
            stravaSession = session
            stravaMenu = null
            linkCurrentStravaAccountIfNeeded(session)
            val (updatedSession, updatedMenu) = graph.stravaCZRepository.loadMenu(forceRefresh = true)
            stravaSession = updatedSession
            stravaMenu = updatedMenu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            stravaError = error.userFacingMessage(context)
        } finally {
            isStravaLoading = false
        }
    }

    suspend fun refreshStravaCZ(forceRefresh: Boolean = true) {
        if (stravaSession == null || isStravaRefreshing) return
        isStravaRefreshing = true
        stravaError = null
        try {
            val (updatedSession, updatedMenu) = graph.stravaCZRepository.loadMenu(forceRefresh)
            stravaSession = updatedSession
            stravaMenu = updatedMenu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            stravaError = error.userFacingMessage(context)
            if (graph.stravaCZRepository.bootstrapSession() == null) {
                stravaSession = null
                stravaMenu = null
            }
        } finally {
            isStravaRefreshing = false
        }
    }

    suspend fun setStravaCZMeal(meal: StravaCZMeal, ordered: Boolean) {
        if (submittingStravaMealID != null) return
        submittingStravaMealID = meal.id
        stravaError = null
        try {
            val (updatedSession, updatedMenu) = graph.stravaCZRepository.setMeal(meal, ordered)
            stravaSession = updatedSession
            stravaMenu = updatedMenu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            stravaError = error.userFacingMessage(context)
            graph.stravaCZRepository.loadCachedMenu()?.let { stravaMenu = it }
            if (graph.stravaCZRepository.bootstrapSession() == null) {
                stravaSession = null
                stravaMenu = null
            }
        } finally {
            submittingStravaMealID = null
        }
    }

    fun cleanupSignedOutStravaBestEffort(
        session: StravaCZStoredSession?,
        linkedAccountIDsToUnlink: List<String> = emptyList(),
        gradeySession: GradeyAuthSession? = null,
    ) {
        if (gradeySession != null) {
            linkedAccountIDsToUnlink.forEach { accountID ->
                scope.launch {
                    try {
                        graph.linkedAccountRepository.unlinkAccountForSignedOutSession(
                            accountID,
                            gradeySession,
                        )
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // The local meals session is already gone; cloud unlink is opportunistic.
                    }
                }
            }
        }
        if (session != null) {
            scope.launch {
                try {
                    graph.stravaCZRepository.revokeSignedOutSession(session)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    // The local meals session is already gone; remote logout is opportunistic.
                }
            }
        }
    }

    fun clearStravaCZPresentation(linkedAccountIDsToHide: Set<String> = emptySet()) {
        stravaSession = null
        stravaMenu = null
        stravaError = null
        submittingStravaMealID = null
        if (linkedAccountIDsToHide.isNotEmpty()) {
            linkedAccounts = linkedAccounts.filterNot { it.id in linkedAccountIDsToHide }
        }
    }

    suspend fun signOutStravaCZLocally() {
        val signedOutSession = try {
            graph.stravaCZRepository.takeLocalSessionForSignOut()
        } finally {
            clearStravaCZPresentation()
        }
        cleanupSignedOutStravaBestEffort(signedOutSession)
    }

    suspend fun disconnectStravaCZ() {
        val disconnectOwner = currentGradeyIdentityOwner()
        val mealAccounts = linkedAccounts.filter { it.provider == LinkedAccountProvider.STRAVA_CZ }
        val mealAccountIDs = mealAccounts.map(LinkedSchoolAccount::id)
        disconnectOwner?.requireCurrent()
        completeLocalStravaDisconnectBeforeRemoteCleanup(
            takeLocalSessionForSignOut = graph.stravaCZRepository::takeLocalSessionForSignOut,
            clearVisibleState = {
                clearStravaCZPresentation(mealAccountIDs.toSet())
            },
            captureGradeySessionForCleanup = {
                if (disconnectOwner == null) {
                    null
                } else {
                    disconnectOwner.requireCurrent()
                    graph.gradeyAuthRepository.bootstrapSession().also { capturedSession ->
                        disconnectOwner.requireCurrent()
                        if (
                            capturedSession != null &&
                            capturedSession.account.id != disconnectOwner.accountID
                        ) {
                            throw GradeyIdentityChangedException()
                        }
                    }
                }
            },
            launchRemoteCleanup = { signedOutSession, gradeySession ->
                cleanupSignedOutStravaBestEffort(
                    session = signedOutSession,
                    linkedAccountIDsToUnlink = mealAccountIDs,
                    gradeySession = gradeySession,
                )
            },
        )
    }

    suspend fun loadSchoolDirectory(forceRefresh: Boolean = false) {
        if (isSchoolDirectoryLoading || (hasLoadedSchoolDirectory && !forceRefresh)) return
        hasLoadedSchoolDirectory = true
        schoolDirectoryError = null

        val cachedDirectory = try {
            graph.schoolDirectoryRepository.loadCachedDirectory()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        if (cachedDirectory != null) directorySchools = cachedDirectory.schools

        val shouldRefresh = forceRefresh ||
            cachedDirectory == null ||
            cachedDirectory.isStale() ||
            !cachedDirectory.isCurrentFormat
        if (!shouldRefresh) return

        isSchoolDirectoryLoading = directorySchools.isEmpty()
        try {
            directorySchools = graph.schoolDirectoryRepository.refreshDirectory()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            hasLoadedSchoolDirectory = false
            if (directorySchools.isEmpty()) {
                schoolDirectoryError = context.getString(R.string.school_directory_load_failed)
            }
        } finally {
            isSchoolDirectoryLoading = false
        }
    }

    suspend fun applyFreshTimetable(loaded: TimetableWeek, requestedSchoolScope: String) {
        // Resolve any current-week fallback before touching presentation state. If the account
        // changes while that cache read is suspended, the final owner check below discards every
        // projection from the old account rather than repopulating state cleared by the switch.
        if (
            activeSchoolSessionForScope(
                requestedSchoolScope,
                graph.schoolRepository.currentStoredSession(),
            ) == null
        ) return
        val today = TimetableDates.today()
        val currentWeekStart = TimetableDates.apiDateString(TimetableDates.monday(today))
        val cachedCurrent = if (WearPayloadBuilder.currentWeekProjection(loaded, null, today) == null) {
            try {
                graph.schoolRepository.loadCachedTimetable(currentWeekStart)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
        } else {
            null
        }
        val publicationSession = activeSchoolSessionForScope(
            requestedSchoolScope,
            graph.schoolRepository.currentStoredSession(),
        ) ?: return
        // There is intentionally no suspension between this owner check and the assignments. An
        // account switch therefore either wins afterwards by clearing them, or is observed above.
        timetable = loaded
        timetableRequestedWeek = loaded.weekStart
        timetableError = null
        try {
            updateNextLessonWidgets(context.applicationContext)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // A launcher/widget host failure must not hide a successful timetable refresh.
        }
        val wearTimetable = WearPayloadBuilder.currentWeekProjection(loaded, cachedCurrent, today)
            ?: return
        try {
            PhoneWearSyncPublisher.publish(
                context.applicationContext,
                WearPayloadBuilder.signedIn(wearTimetable, dashboardViewModel.currentDashboard?.user, supportTier),
                isStillCurrent = {
                    activeSchoolSessionForScope(
                        publicationSession.cacheScope,
                        graph.schoolRepository.currentStoredSession(),
                    ) != null
                },
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // A missing/unpaired watch must not hide a successful timetable refresh.
        }
    }

    suspend fun loginReplacingSchoolSession(
        schoolURL: String,
        username: String,
        password: String,
    ): StoredSession {
        val mutationOwner = beginSchoolMutation(CURRENT_SCHOOL_LINK_MUTATION_ID)
            ?: throw IllegalStateException(context.getString(R.string.school_account_change_in_progress))
        try {
            mutationOwner.requireCurrent()
            val cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
            mutationOwner.requireCurrent()
            val previousScope = graph.schoolRepository.currentStoredSession()?.cacheScope
            mutationOwner.requireCurrent()
            val session = graph.schoolRepository.login(
                schoolURL,
                username,
                password,
                cloudMutationToken,
            )
            mutationOwner.requireCurrent()
            if (previousScope != session.cacheScope) {
                clearSchoolPresentationAfterAccountChange(session.cacheScope)
                clearSchoolPlatformProjectionsAfterAccountChange(
                    isStillCurrent = { mutationOwner.isCurrent() },
                )
                mutationOwner.requireCurrent()
            }
            return session
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun loadTimetable(weekContaining: String): Throwable? {
        return try {
            val requestedSchoolScope = graph.schoolRepository.currentStoredSession()?.cacheScope
                ?: throw SchoolSessionExpiredException()
            timetableRequestedWeek = TimetableDates.apiDateString(
                TimetableDates.monday(TimetableDates.parseApiDate(weekContaining) ?: TimetableDates.today()),
            )
            val loaded = graph.schoolRepository.loadTimetable(weekContaining)
            if (
                activeSchoolSessionForScope(
                    requestedSchoolScope,
                    graph.schoolRepository.currentStoredSession(),
                ) == null
            ) return null
            applyFreshTimetable(loaded, requestedSchoolScope)
            null
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
            routeToSchoolReconnect()
            error
        } catch (error: Throwable) {
            error
        }
    }

    suspend fun loadTimetableCacheFirst(weekContaining: String): Throwable? {
        val requested = TimetableDates.apiDateString(
            TimetableDates.monday(TimetableDates.parseApiDate(weekContaining) ?: TimetableDates.today()),
        )
        timetableRequestedWeek = requested
        timetableError = null
        return try {
            val requestedSchoolScope = graph.schoolRepository.currentStoredSession()?.cacheScope
                ?: throw SchoolSessionExpiredException()
            val cached = graph.schoolRepository.loadCachedTimetable(requested)
            if (
                activeSchoolSessionForScope(
                    requestedSchoolScope,
                    graph.schoolRepository.currentStoredSession(),
                ) == null
            ) return null
            timetable = cached
            val loaded = graph.schoolRepository.loadTimetable(requested)
            if (
                activeSchoolSessionForScope(
                    requestedSchoolScope,
                    graph.schoolRepository.currentStoredSession(),
                ) == null
            ) return null
            applyFreshTimetable(loaded, requestedSchoolScope)
            null
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
            routeToSchoolReconnect()
            error
        } catch (error: Throwable) {
            error
        }
    }

    suspend fun disconnectSchool() {
        graph.schoolRepository.logout()
        graph.historyRepository.clearAllCachedGradeHistory()
        try {
            PhoneWearSyncPublisher.publish(
                context.applicationContext,
                com.bukovinafilip.gradey.model.GradeyWearSyncPayload.signedOut(),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // School sign-out is complete even when no Wear OS device is paired.
        }
        try {
            updateNextLessonWidgets(context.applicationContext)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // The school session and cached widget data are already cleared.
        }
        dashboardViewModel.clear()
        absence = null
        resetAbsenceSubjectResolution()
        resetTimetableState()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        activeLinkedAccountID = null
        currentSchoolBaseURL = ""
        reconnectLinkedAccount = null
        reconnectLinkedAccountID = null
        applyReconnectPrefill(null)
        isAddingSchool = false
        resetSignedInNavigation()
        dataError = null
        absenceRefreshError = null
        schoolLoginError = null
    }

    suspend fun clearLinkedAccountsForLocalMode() {
        val ownsBoundary = !isGradeyIdentityBoundaryChanging()
        val boundaryToken = if (ownsBoundary) invalidateGradeyIdentityWork() else null
        try {
            withContext(NonCancellable) { clearGradeyIdentityBoundaryState() }
        } finally {
            boundaryToken?.let(::finishGradeyIdentityBoundaryChange)
        }
    }

    suspend fun refreshLinkedAccountSnapshot() {
        val localReadOwner = currentOnboardingIdentityOwner() ?: return
        val localRefresh = refreshRetainingContent(linkedAccounts) {
            graph.linkedAccountRepository.localAccounts()
        }
        if (!localReadOwner.isCurrent()) return
        linkedAccounts = localRefresh.value
        val refreshOwner = currentGradeyIdentityOwner() ?: return
        if (!graph.isGradeyCloudConfigured || isRefreshingLinkedAccounts) return

        isRefreshingLinkedAccounts = true
        linkedAccountError = null
        try {
            val snapshot = graph.linkedAccountRepository.refreshAccounts()
            if (
                !refreshOwner.isCurrent(
                    account?.id,
                    gradeyIdentityGeneration,
                    isGuestMode,
                )
            ) return
            linkedAccounts = snapshot.linkedAccounts
            notificationPreferences = snapshot.notificationPreferences
            graph.notificationPreferencesStore.preferences = snapshot.notificationPreferences
            notificationPreferencesError = null
        } catch (_: GradeyIdentityChangedException) {
            // A replacement identity owns both the cache and any subsequent UI publication.
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (
                refreshOwner.isCurrent(
                    account?.id,
                    gradeyIdentityGeneration,
                    isGuestMode,
                )
            ) {
                expireGradeyIdentity(error)
            }
        } catch (error: Throwable) {
            if (
                refreshOwner.isCurrent(
                    account?.id,
                    gradeyIdentityGeneration,
                    isGuestMode,
                )
            ) {
                linkedAccountError = error.userFacingMessage(context)
            }
        } finally {
            if (
                refreshOwner.isCurrent(
                    account?.id,
                    gradeyIdentityGeneration,
                    isGuestMode,
                )
            ) {
                isRefreshingLinkedAccounts = false
            }
        }
    }

    suspend fun updateNotificationPreferences(updated: NotificationPreferences) {
        if (
            account == null ||
            isGuestMode ||
            !graph.isGradeyCloudConfigured ||
            isUpdatingNotificationPreferences
        ) return
        val updateOwner = currentGradeyIdentityOwner() ?: return

        val previous = notificationPreferences
        val prepared = prepareNotificationPreferencesForUpdate(
            preferences = updated,
            timeZoneID = ZoneId.systemDefault().id,
        )
        notificationPreferences = prepared
        graph.notificationPreferencesStore.preferences = prepared
        notificationPreferencesError = null
        isUpdatingNotificationPreferences = true
        try {
            updateOwner.requireCurrent()
            val session = graph.gradeyAuthRepository.validSession()
            updateOwner.requireCurrent()
            graph.devicePushTokenClient.updateNotificationPreferences(prepared, session)
            updateOwner.requireCurrent()
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            if (updateOwner.isCurrent()) {
                notificationPreferences = previous
                graph.notificationPreferencesStore.preferences = previous
            }
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (!updateOwner.isCurrent()) throw GradeyIdentityChangedException()
            notificationPreferences = previous
            graph.notificationPreferencesStore.preferences = previous
            expireGradeyIdentity(error)
        } catch (error: Throwable) {
            if (!updateOwner.isCurrent()) throw GradeyIdentityChangedException()
            notificationPreferences = previous
            graph.notificationPreferencesStore.preferences = previous
            notificationPreferencesError = error.userFacingMessage(context)
        } finally {
            if (updateOwner.isCurrent()) isUpdatingNotificationPreferences = false
        }
    }

    suspend fun refreshGradeHistory() {
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) {
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
            return
        }
        val refreshOwner = currentGradeyIdentityOwner() ?: return
        refreshOwner.requireCurrent()
        val linkedAccountID = graph.schoolRepository.currentStoredSession()?.linkedAccountID
        refreshOwner.requireCurrent()
        if (gradeHistorySnapshot?.linkedAccountID != linkedAccountID) {
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
        }
        val refresh = refreshRetainingContent(gradeHistorySnapshot) {
            refreshOwner.requireCurrent()
            val response = graph.historyRepository.gradeHistory(linkedAccountID, days = 400)
            refreshOwner.requireCurrent()
            GradeHistorySnapshot(
                linkedAccountID = linkedAccountID,
                trends = GradeHistoryTrends.make(response.events),
                recentNewMarkEvents = response.recentNewMarkEvents,
            )
        }
        if (!refreshOwner.isCurrent()) return
        if (graph.schoolRepository.currentStoredSession()?.linkedAccountID != linkedAccountID) return
        gradeHistorySnapshot = refresh.value
        gradeHistoryRefreshError = refresh.failure?.userFacingMessage(context)
    }

    suspend fun linkCurrentSchoolIfNeeded(trustCachedAssociation: Boolean = true): Boolean {
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) return true
        val mutationOwner = beginSchoolMutation(CURRENT_SCHOOL_LINK_MUTATION_ID) ?: return false
        return try {
            mutationOwner.requireCurrent()
            val cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
            mutationOwner.requireCurrent()
            val session = graph.schoolRepository.currentStoredSession() ?: return false
            mutationOwner.requireCurrent()
            val cachedAccounts = graph.linkedAccountRepository.localAccounts()
            mutationOwner.requireCurrent()
            if (shouldTrustCachedSchoolAssociation(trustCachedAssociation, session, cachedAccounts)) {
                activeLinkedAccountID = session.linkedAccountID
                linkedAccounts = cachedAccounts
                linkedAccountError = null
                return true
            }

            val linked = graph.linkedAccountRepository.linkSchoolAccount(
                session,
                dashboardViewModel.currentDashboard?.user,
            )
            mutationOwner.requireCurrent()
            if (
                !linked.provider.isSupportedSchoolProvider ||
                linked.status != LinkedAccountStatus.ACTIVE
            ) {
                val refreshedAccounts = graph.linkedAccountRepository.localAccounts()
                mutationOwner.requireCurrent()
                linkedAccounts = refreshedAccounts
                linkedAccountError = context.getString(R.string.error_linked_account)
                return false
            }
            mutationOwner.requireCurrent()
            val associatedSession = graph.schoolRepository.associateCurrentSession(
                linked,
                cloudMutationToken,
            )
            mutationOwner.requireCurrent()
            val refreshedAccounts = graph.linkedAccountRepository.localAccounts()
            mutationOwner.requireCurrent()
            dashboardViewModel.adoptScope(associatedSession.cacheScope)
            activeLinkedAccountID = linked.id
            linkedAccounts = refreshedAccounts
            linkedAccountError = null
            true
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            expireGradeyIdentity(error)
            false
        } catch (error: Throwable) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            linkedAccountError = error.userFacingMessage(context)
            false
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun reconnectLinkedAccountWithCredentials(
        linked: LinkedSchoolAccount,
        schoolURL: String,
        username: String,
        password: String,
    ): String? {
        if (!linked.provider.isSupportedSchoolProvider) {
            return context.getString(R.string.error_linked_account)
        }
        val mutationOwner = beginSchoolMutation(linked.id)
        if (mutationOwner == null) {
            return context.getString(R.string.school_account_change_in_progress)
        }
        var previousSession: StoredSession? = null
        var cloudMutationToken: SchoolCloudMutationToken? = null
        return try {
            mutationOwner.requireCurrent()
            cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
            mutationOwner.requireCurrent()
            previousSession = graph.schoolRepository.currentStoredSession()
            mutationOwner.requireCurrent()
            val candidate = graph.schoolRepository.authenticateSchoolSessionCandidate(
                schoolURL,
                username,
                password,
                cloudMutationToken!!,
            )
            mutationOwner.requireCurrent()
            val updated = graph.linkedAccountRepository.reconnectSchoolAccount(
                linked.id,
                candidate.session,
                candidate.dashboard.user,
            )
            mutationOwner.requireCurrent()
            val associatedSession = graph.schoolRepository.promoteAuthenticatedSchoolSessionCandidate(
                candidate = candidate,
                account = updated,
                cloudMutationToken = cloudMutationToken!!,
            )
            mutationOwner.requireCurrent()
            if (previousSession?.cacheScope != associatedSession.cacheScope) {
                mutationOwner.requireCurrent()
                clearSchoolPlatformProjectionsAfterAccountChange(
                    isStillCurrent = { mutationOwner.isCurrent() },
                )
                mutationOwner.requireCurrent()
            }
            mutationOwner.requireCurrent()
            clearSchoolPresentationAfterAccountChange(associatedSession.cacheScope)
            dashboardViewModel.replaceDashboard(candidate.dashboard, associatedSession.cacheScope)
            activeLinkedAccountID = updated.id
            currentSchoolBaseURL = associatedSession.baseURL
            linkedAccounts = linkedAccounts
                .filterNot { it.id == updated.id }
                .plus(updated)
                .sortedBy { it.displayName.lowercase() }
            reconnectLinkedAccount = null
            reconnectLinkedAccountID = null
            applyReconnectPrefill(null)
            linkedAccountError = null
            resetSignedInNavigation()
            schoolLoginError = null
            phase = AppPhase.SIGNED_IN
            null
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            error.userFacingMessage(context).also { linkedAccountError = it }
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun activateLinkedAccount(linked: LinkedSchoolAccount): Boolean {
        val mutationOwner = beginSchoolMutation(linked.id) ?: return false
        try {
            mutationOwner.requireCurrent()
            val cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
            mutationOwner.requireCurrent()
            val previousSchoolScope = graph.schoolRepository.currentStoredSession()?.cacheScope
            mutationOwner.requireCurrent()
            val activation = graph.linkedAccountRepository.activateSchoolAccount(linked.id)
            mutationOwner.requireCurrent()
            val activatedSession = graph.schoolRepository.activateLinkedSchoolAccount(
                activation.tokenPayload.makeStoredSession(activation.account),
                cloudMutationToken,
            )
            mutationOwner.requireCurrent()
            if (previousSchoolScope != activatedSession.cacheScope) {
                clearSchoolPlatformProjectionsAfterAccountChange(
                    isStillCurrent = { mutationOwner.isCurrent() },
                )
                mutationOwner.requireCurrent()
            }
            clearSchoolPresentationAfterAccountChange(activatedSession.cacheScope)
            activeLinkedAccountID = activation.account.id
            resetSignedInNavigation()
            loadCachedSignedInData(isStillCurrent = { mutationOwner.isCurrent() })
            mutationOwner.requireCurrent()
            // A stale expiry callback can transiently route while activation is in flight but before
            // this session is stored. Successful activation is authoritative and restores the gate.
            schoolLoginError = null
            phase = AppPhase.SIGNED_IN
            return true
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            linkedAccountError = error.userFacingMessage(context)
            return false
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun updateLinkedAccountNotifications(linked: LinkedSchoolAccount, enabled: Boolean) {
        val mutationOwner = beginSchoolMutation(linked.id) ?: return
        try {
            mutationOwner.requireCurrent()
            graph.linkedAccountRepository.updateNotificationsEnabled(linked.id, enabled)
            mutationOwner.requireCurrent()
            val refreshedAccounts = graph.linkedAccountRepository.localAccounts()
            mutationOwner.requireCurrent()
            linkedAccounts = refreshedAccounts
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            linkedAccountError = error.userFacingMessage(context)
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun unlinkLinkedAccount(linked: LinkedSchoolAccount) {
        val mutationOwner = beginSchoolMutation(linked.id) ?: return
        try {
            mutationOwner.requireCurrent()
            if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                completeLocalStravaDisconnectBeforeRemoteCleanup(
                    takeLocalSessionForSignOut = graph.stravaCZRepository::takeLocalSessionForSignOut,
                    clearVisibleState = {
                        clearStravaCZPresentation(setOf(linked.id))
                    },
                    captureGradeySessionForCleanup = {
                        mutationOwner.requireCurrent()
                        graph.gradeyAuthRepository.bootstrapSession().also { capturedSession ->
                            mutationOwner.requireCurrent()
                            if (
                                capturedSession != null &&
                                capturedSession.account.id != mutationOwner.gradeyAccountID
                            ) {
                                throw GradeyIdentityChangedException()
                            }
                        }
                    },
                    launchRemoteCleanup = { signedOutSession, gradeySession ->
                        cleanupSignedOutStravaBestEffort(
                            session = signedOutSession,
                            linkedAccountIDsToUnlink = listOf(linked.id),
                            gradeySession = gradeySession,
                        )
                    },
                )
                return
            }
            val cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
            mutationOwner.requireCurrent()
            graph.linkedAccountRepository.unlinkAccount(linked.id)
            // Once the remote unlink is durable, cancellation must not leave its old cloud
            // association visible locally. Identity replacement is still allowed to supersede us
            // through mutationOwner; ordinary navigation/caller cancellation is deferred until
            // the session, projections, history, and account list agree.
            withContext(NonCancellable) {
                mutationOwner.requireCurrent()
                if (activeLinkedAccountID == linked.id) {
                    val localSession = graph.schoolRepository.disassociateCurrentSession(
                        linked.id,
                        cloudMutationToken,
                    )
                    mutationOwner.requireCurrent()
                    if (localSession == null) {
                        clearSchoolPresentationAfterAccountChange()
                        currentSchoolBaseURL = ""
                        clearSchoolPlatformProjectionsAfterAccountChange(
                            onlyWhileSignedOut = true,
                            isStillCurrent = { mutationOwner.isCurrent() },
                        )
                    } else {
                        dashboardViewModel.adoptScope(localSession.cacheScope)
                        currentSchoolBaseURL = localSession.baseURL
                    }
                    activeLinkedAccountID = null
                    gradeHistorySnapshot = null
                    gradeHistoryRefreshError = null
                    try {
                        graph.historyRepository.clearCachedGradeHistory(linked.id)
                    } catch (_: Throwable) {
                        // The detached identity is already authoritative. A disposable, account-keyed
                        // cloud-history cache must not interrupt the remaining local teardown.
                    }
                }
                mutationOwner.requireCurrent()
                linkedAccounts = try {
                    graph.linkedAccountRepository.localAccounts()
                } catch (_: Throwable) {
                    linkedAccounts.filterNot { it.id == linked.id }
                }
                mutationOwner.requireCurrent()
            }
        } catch (error: GradeyIdentityChangedException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!mutationOwner.isCurrent()) throw GradeyIdentityChangedException()
            linkedAccountError = error.userFacingMessage(context)
        } finally {
            finishSchoolMutation(mutationOwner)
        }
    }

    suspend fun refreshSignedInData(forceRefresh: Boolean = false) {
        dataError = null
        absenceRefreshError = null
        timetableError = null
        stravaError = null
        val failures = mutableListOf<Throwable>()
        val dashboardScope = graph.schoolRepository.currentStoredSession()?.cacheScope
        when (
            val error = dashboardViewModel.refresh(
                scopeKey = dashboardScope,
                forceRefresh = forceRefresh,
                load = graph.schoolRepository::loadDashboard,
            )
        ) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }

            null -> Unit
            else -> {
                failures += error
            }
        }
        val absenceRefresh = refreshRetainingContent(absence) {
            graph.schoolRepository.loadAbsence(forceRefresh = forceRefresh)
        }
        if (absenceRefresh.failure == null) {
            absenceRefresh.value?.let(::startAbsenceSubjectResolution)
        } else {
            absence = absenceRefresh.value
        }
        when (val error = absenceRefresh.failure) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }

            null -> Unit
            else -> {
                failures += error
                absenceRefreshError = error.userFacingMessage(context)
            }
        }
        when (val timetableFailure = loadTimetable(timetableRequestedWeek)) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }
            null -> Unit
            else -> {
                failures += timetableFailure
                timetableError = timetableFailure.userFacingMessage(context)
            }
        }
        val mealsSessionRefresh = refreshRetainingContent(stravaSession) {
            graph.stravaCZRepository.bootstrapSession()
        }
        stravaSession = mealsSessionRefresh.value
        val mealsSessionFailure = mealsSessionRefresh.failure
        if (mealsSessionFailure != null) {
            stravaError = mealsSessionFailure.userFacingMessage(context)
        } else if (stravaSession != null) {
            val mealsRefresh = refreshRetainingContent(MealsSnapshot(stravaSession, stravaMenu)) {
                val (updatedSession, updatedMenu) = graph.stravaCZRepository.loadMenu(
                    forceRefresh = forceRefresh,
                )
                MealsSnapshot(session = updatedSession, menu = updatedMenu)
            }
            stravaSession = mealsRefresh.value.session
            stravaMenu = mealsRefresh.value.menu
            mealsRefresh.failure?.let { error ->
                stravaError = error.userFacingMessage(context)
                if (graph.stravaCZRepository.bootstrapSession() == null) {
                    stravaSession = null
                    stravaMenu = null
                }
            }
        } else {
            stravaMenu = null
        }
        refreshLinkedAccountSnapshot()
        refreshGradeHistory()
        dataError = failures.firstOrNull()?.userFacingMessage(context)
    }

    suspend fun openStoredSchoolOrLogin() {
        val owner = currentOnboardingIdentityOwner() ?: return
        val schoolSession = graph.schoolRepository.bootstrapSession()
        if (!owner.isCurrent()) return
        if (schoolSession == null) {
            phase = AppPhase.NEEDS_SCHOOL
            return
        }
        phase = AppPhase.SIGNED_IN
        loadCachedSignedInData(isStillCurrent = { owner.isCurrent() })
        if (!owner.isCurrent()) return
        refreshSignedInData()
    }

    fun persistOnboarding(progress: OnboardingProgress) {
        graph.onboardingProgressStore.saveProgress(progress)
        onboardingProgress = progress
    }

    fun isCurrentUpgradeSupportAttempt(owner: GradeyIdentityOwner, attempt: Int): Boolean =
        attempt == onboardingUpgradeCloudLinkAttempt &&
            owner.isCurrent() &&
            onboardingProgress?.journey == OnboardingJourney.UPGRADE &&
            onboardingProgress?.step == OnboardingStep.SUPPORT

    fun returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID: String) {
        val current = onboardingProgress ?: return
        if (
            account == null &&
            !isGuestMode &&
            ownerAccountID.isNotBlank() &&
            current.journey == OnboardingJourney.UPGRADE &&
            current.step == OnboardingStep.SUPPORT
        ) {
            persistOnboarding(current.copy(step = OnboardingStep.ACCOUNT))
        }
    }

    suspend fun migrateOnboardingUpgradeConnections(ownerAccountID: String) {
        if (
            isOnboardingUpgradeCloudLinkWorking ||
            account?.id != ownerAccountID ||
            isGuestMode ||
            onboardingProgress?.journey != OnboardingJourney.UPGRADE ||
            onboardingProgress?.step != OnboardingStep.SUPPORT ||
            onboardingUpgradeSchoolCloudLinkState != OnboardingUpgradeCloudLinkState.PENDING ||
            onboardingUpgradeMealsCloudLinkState != OnboardingUpgradeCloudLinkState.PENDING
        ) {
            return
        }
        val refreshOwner = currentGradeyIdentityOwner() ?: return

        val attempt = onboardingUpgradeCloudLinkAttempt + 1
        onboardingUpgradeCloudLinkAttempt = attempt
        isOnboardingUpgradeCloudLinkWorking = true
        onboardingUpgradeRetryTarget = null
        try {
            val existingAccounts = try {
                val snapshot = graph.linkedAccountRepository.refreshAccounts()
                if (
                    !refreshOwner.isCurrent(
                        account?.id,
                        gradeyIdentityGeneration,
                        isGuestMode,
                    )
                ) return
                linkedAccounts = snapshot.linkedAccounts
                notificationPreferences = snapshot.notificationPreferences
                graph.notificationPreferencesStore.preferences = snapshot.notificationPreferences
                snapshot.linkedAccounts
            } catch (_: GradeyIdentityChangedException) {
                return
            } catch (error: CancellationException) {
                throw error
            } catch (error: GradeySessionExpiredException) {
                if (
                    refreshOwner.isCurrent(
                        account?.id,
                        gradeyIdentityGeneration,
                        isGuestMode,
                    )
                ) {
                    expireGradeyIdentity(error)
                    returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID)
                }
                return
            } catch (_: Throwable) {
                // Never trust an unscoped on-device cloud snapshot after reauthentication.
                // Offline migration safely attempts the retained sessions instead.
                emptyList()
            }

            var schoolState: OnboardingUpgradeCloudLinkState
            var schoolError: String? = null
            // Match iOS migration semantics: a current-owner cloud record for the provider
            // is already migrated; otherwise copy the current on-device session below.
            if (existingAccounts.any { it.provider.isSupportedSchoolProvider }) {
                schoolState = OnboardingUpgradeCloudLinkState.LINKED
            } else {
                val schoolSession = try {
                    graph.schoolRepository.bootstrapSession()
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    null
                }
                if (schoolSession == null) {
                    schoolState = OnboardingUpgradeCloudLinkState.NOT_ATTEMPTED
                } else {
                    try {
                        dashboardViewModel.loadCached(
                            scopeKey = schoolSession.cacheScope,
                            load = graph.schoolRepository::loadCachedDashboard,
                        )
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // The retained school session is sufficient for the cloud-link attempt.
                    }
                    val linked = linkCurrentSchoolIfNeeded(trustCachedAssociation = false)
                    if (account?.id != ownerAccountID) {
                        returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID)
                        return
                    }
                    schoolState = if (linked) {
                        OnboardingUpgradeCloudLinkState.LINKED
                    } else {
                        OnboardingUpgradeCloudLinkState.FAILED
                    }
                    schoolError = linkedAccountError
                        .takeIf { schoolState == OnboardingUpgradeCloudLinkState.FAILED }
                        ?: context.getString(R.string.error_linked_account)
                            .takeIf { schoolState == OnboardingUpgradeCloudLinkState.FAILED }
                }
            }

            if (!isCurrentUpgradeSupportAttempt(refreshOwner, attempt)) return

            var mealsState: OnboardingUpgradeCloudLinkState
            var mealsError: String? = null
            var retainedMealsSession: StravaCZStoredSession? = null
            var refreshedAccounts: List<LinkedSchoolAccount>? = null
            // iOS likewise treats an existing Strava.cz provider record as migrated.
            if (existingAccounts.any { it.provider == LinkedAccountProvider.STRAVA_CZ }) {
                mealsState = OnboardingUpgradeCloudLinkState.LINKED
            } else {
                val result = linkRetainedStravaSession(
                    loadSession = {
                        try {
                            graph.stravaCZRepository.bootstrapSession()
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Throwable) {
                            null
                        }
                    },
                    linkSession = { session ->
                        val linked = graph.linkedAccountRepository.linkStravaCZAccount(session)
                        check(
                            linked.provider == LinkedAccountProvider.STRAVA_CZ &&
                                linked.status == LinkedAccountStatus.ACTIVE,
                        ) {
                            context.getString(R.string.error_linked_account)
                        }
                    },
                )
                when (result) {
                    RetainedStravaCloudLinkResult.NoLocalSession -> {
                        mealsState = OnboardingUpgradeCloudLinkState.NOT_ATTEMPTED
                    }
                    is RetainedStravaCloudLinkResult.Linked -> {
                        mealsState = OnboardingUpgradeCloudLinkState.LINKED
                        retainedMealsSession = result.session
                        refreshedAccounts = try {
                            graph.linkedAccountRepository.localAccounts()
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Throwable) {
                            null
                        }
                    }
                    is RetainedStravaCloudLinkResult.Failed -> {
                        val cause = result.cause
                        if (cause is GradeySessionExpiredException) {
                            expireGradeyIdentity(cause)
                            returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID)
                            return
                        }
                        mealsState = OnboardingUpgradeCloudLinkState.FAILED
                        mealsError = cause.userFacingMessage(context)
                        retainedMealsSession = result.session
                    }
                }
            }

            if (!isCurrentUpgradeSupportAttempt(refreshOwner, attempt)) return
            onboardingUpgradeSchoolCloudLinkState = schoolState
            onboardingUpgradeSchoolCloudLinkError = schoolError
            onboardingUpgradeMealsCloudLinkState = mealsState
            onboardingUpgradeMealsCloudLinkError = mealsError
            retainedMealsSession?.let { stravaSession = it }
            refreshedAccounts?.let { linkedAccounts = it }
        } finally {
            if (isCurrentUpgradeSupportAttempt(refreshOwner, attempt)) {
                isOnboardingUpgradeCloudLinkWorking = false
                onboardingUpgradeRetryTarget = null
            }
        }
    }

    suspend fun retryOnboardingUpgradeSchoolCloudLink(ownerAccountID: String) {
        if (
            isOnboardingUpgradeCloudLinkWorking ||
            account?.id != ownerAccountID ||
            isGuestMode ||
            onboardingProgress?.journey != OnboardingJourney.UPGRADE ||
            onboardingProgress?.step != OnboardingStep.SUPPORT
        ) {
            return
        }
        val retryOwner = currentGradeyIdentityOwner() ?: return
        val hasRetainedSession = try {
            graph.schoolRepository.bootstrapSession()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        } != null
        retryOwner.requireCurrent()
        if (!hasRetainedSession) return

        val attempt = onboardingUpgradeCloudLinkAttempt + 1
        onboardingUpgradeCloudLinkAttempt = attempt
        isOnboardingUpgradeCloudLinkWorking = true
        onboardingUpgradeRetryTarget = OnboardingUpgradeRetryTarget.SCHOOL
        try {
            try {
                dashboardViewModel.loadCached(
                    scopeKey = graph.schoolRepository.currentStoredSession()?.cacheScope,
                    load = graph.schoolRepository::loadCachedDashboard,
                )
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Retry with the retained session even when optional cached profile data is unavailable.
            }
            val linked = linkCurrentSchoolIfNeeded(trustCachedAssociation = false)
            if (!retryOwner.isCurrent()) {
                returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID)
                return
            }
            if (!isCurrentUpgradeSupportAttempt(retryOwner, attempt)) return
            onboardingUpgradeSchoolCloudLinkState = if (linked) {
                OnboardingUpgradeCloudLinkState.LINKED
            } else {
                OnboardingUpgradeCloudLinkState.FAILED
            }
            onboardingUpgradeSchoolCloudLinkError = if (linked) {
                null
            } else {
                linkedAccountError ?: context.getString(R.string.error_linked_account)
            }
        } finally {
            if (isCurrentUpgradeSupportAttempt(retryOwner, attempt)) {
                isOnboardingUpgradeCloudLinkWorking = false
                onboardingUpgradeRetryTarget = null
            }
        }
    }

    suspend fun retryOnboardingUpgradeMealsCloudLink(ownerAccountID: String) {
        if (
            isOnboardingUpgradeCloudLinkWorking ||
            account?.id != ownerAccountID ||
            isGuestMode ||
            onboardingProgress?.journey != OnboardingJourney.UPGRADE ||
            onboardingProgress?.step != OnboardingStep.SUPPORT
        ) {
            return
        }
        val retryOwner = currentGradeyIdentityOwner() ?: return

        val attempt = onboardingUpgradeCloudLinkAttempt + 1
        onboardingUpgradeCloudLinkAttempt = attempt
        isOnboardingUpgradeCloudLinkWorking = true
        onboardingUpgradeRetryTarget = OnboardingUpgradeRetryTarget.MEALS
        try {
            val result = linkRetainedStravaSession(
                loadSession = {
                    try {
                        graph.stravaCZRepository.bootstrapSession()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        null
                    }
                },
                linkSession = { session ->
                    val linked = graph.linkedAccountRepository.linkStravaCZAccount(session)
                    check(
                        linked.provider == LinkedAccountProvider.STRAVA_CZ &&
                            linked.status == LinkedAccountStatus.ACTIVE,
                    ) {
                        context.getString(R.string.error_linked_account)
                    }
                },
            )
            if (result is RetainedStravaCloudLinkResult.Failed) {
                val cause = result.cause
                if (cause is GradeySessionExpiredException) {
                    if (!retryOwner.isCurrent()) return
                    expireGradeyIdentity(cause)
                    returnUpgradeToAccountAfterExpiredIdentity(ownerAccountID)
                    return
                }
            }
            if (!isCurrentUpgradeSupportAttempt(retryOwner, attempt)) return
            when (result) {
                // A retry cannot recreate a session that disappeared outside this flow;
                // retain the warning so the user is not told that the failed link succeeded.
                RetainedStravaCloudLinkResult.NoLocalSession -> Unit
                is RetainedStravaCloudLinkResult.Linked -> {
                    stravaSession = result.session
                    onboardingUpgradeMealsCloudLinkState = OnboardingUpgradeCloudLinkState.LINKED
                    onboardingUpgradeMealsCloudLinkError = null
                    val refreshedAccounts = try {
                        graph.linkedAccountRepository.localAccounts()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        linkedAccounts
                    }
                    retryOwner.requireCurrent()
                    linkedAccounts = refreshedAccounts
                }
                is RetainedStravaCloudLinkResult.Failed -> {
                    stravaSession = result.session
                    onboardingUpgradeMealsCloudLinkState = OnboardingUpgradeCloudLinkState.FAILED
                    onboardingUpgradeMealsCloudLinkError = result.cause.userFacingMessage(context)
                }
            }
        } finally {
            if (isCurrentUpgradeSupportAttempt(retryOwner, attempt)) {
                isOnboardingUpgradeCloudLinkWorking = false
                onboardingUpgradeRetryTarget = null
            }
        }
    }

    suspend fun advanceOnboardingAfterAccountChoice() {
        val owner = currentOnboardingIdentityOwner() ?: return
        val current = onboardingProgress ?: return
        owner.requireCurrent()
        val hasSchool = graph.schoolRepository.bootstrapSession() != null
        if (!owner.isCurrent()) return
        if (current.journey == OnboardingJourney.UPGRADE) {
            owner.requireCurrent()
            persistOnboarding(
                reconcileOnboardingProgress(
                    progress = current.copy(step = OnboardingStep.ACCOUNT),
                    isGuestMode = isGuestMode,
                    hasGradeySession = account != null,
                    hasSchoolSession = hasSchool,
                ),
            )
            return
        }
        var isSchoolCloudLinked = true
        if (hasSchool && account != null && !isGuestMode) {
            val schoolScope = graph.schoolRepository.currentStoredSession()?.cacheScope
            owner.requireCurrent()
            dashboardViewModel.loadCached(
                scopeKey = schoolScope,
                load = graph.schoolRepository::loadCachedDashboard,
            )
            if (!owner.isCurrent()) return
            if (dashboardViewModel.currentDashboard == null) {
                dashboardViewModel.refresh(
                    scopeKey = schoolScope,
                    forceRefresh = false,
                    load = graph.schoolRepository::loadDashboard,
                )
                if (!owner.isCurrent()) return
            }
            isSchoolCloudLinked = try {
                linkCurrentSchoolIfNeeded()
            } catch (_: GradeyIdentityChangedException) {
                return
            }
            if (!owner.isCurrent()) return
        }
        owner.requireCurrent()
        onboardingSchoolCloudLinkFailed =
            current.journey == OnboardingJourney.NEW_USER &&
            hasSchool &&
            account != null &&
            !isGuestMode &&
            !isSchoolCloudLinked
        onboardingSchoolCloudLinkError = linkedAccountError.takeIf { onboardingSchoolCloudLinkFailed }
        owner.requireCurrent()
        persistOnboarding(
            reconcileOnboardingProgress(
                progress = current.copy(step = OnboardingStep.ACCOUNT),
                isGuestMode = isGuestMode,
                hasGradeySession = account != null,
                hasSchoolSession = hasSchool,
                isSchoolCloudLinked = isSchoolCloudLinked,
            ),
        )
    }

    suspend fun advanceOnboardingAfterSchoolConnection(isSchoolCloudLinked: Boolean = true) {
        val current = onboardingProgress ?: return
        onboardingSchoolCloudLinkFailed =
            current.journey == OnboardingJourney.NEW_USER &&
            account != null &&
            !isGuestMode &&
            !isSchoolCloudLinked
        onboardingSchoolCloudLinkError = linkedAccountError.takeIf { onboardingSchoolCloudLinkFailed }
        persistOnboarding(
            reconcileOnboardingProgress(
                progress = current.copy(step = OnboardingStep.SCHOOL),
                isGuestMode = isGuestMode,
                hasGradeySession = account != null,
                hasSchoolSession = true,
                isSchoolCloudLinked = isSchoolCloudLinked,
            ),
        )
    }

    fun goBackInOnboarding() {
        val current = onboardingProgress ?: return
        val previous = when (current.step) {
            OnboardingStep.WELCOME -> return
            OnboardingStep.ACCOUNT -> OnboardingStep.WELCOME
            OnboardingStep.SCHOOL -> OnboardingStep.ACCOUNT
            OnboardingStep.NOTIFICATIONS -> {
                if (onboardingNotificationsReturnToReady) {
                    onboardingNotificationsReturnToReady = false
                    OnboardingStep.READY
                } else {
                    OnboardingStep.SCHOOL
                }
            }
            OnboardingStep.READY -> {
                if (isGuestMode || onboardingSchoolCloudLinkFailed) {
                    OnboardingStep.SCHOOL
                } else {
                    OnboardingStep.NOTIFICATIONS
                }
            }
            OnboardingStep.SUPPORT -> OnboardingStep.ACCOUNT
        }
        persistOnboarding(current.copy(step = previous))
    }

    suspend fun finishOnboarding() {
        graph.onboardingProgressStore.complete()
        onboardingNotificationNeedsSystemSettings = false
        onboardingProgress = null
        openStoredSchoolOrLogin()
    }

    fun revokeSignedOutGradeySessionBestEffort(
        session: GradeyAuthSession?,
        linkedAccountIDsToUnlink: List<String> = emptyList(),
    ) {
        if (session == null) return
        scope.launch {
            linkedAccountIDsToUnlink.forEach { accountID ->
                try {
                    graph.linkedAccountRepository.unlinkAccountForSignedOutSession(accountID, session)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    // Local sign-out is already complete; unlink is optional remote cleanup.
                }
            }
            try {
                graph.gradeyAuthRepository.revokeSignedOutSession(session)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // The exact session is already gone locally; remote revocation is opportunistic.
            }
        }
    }

    suspend fun signOutGradeyIdentity(
        existingBoundaryToken: Long? = null,
        revokeRemoteSession: Boolean = true,
    ): GradeyAuthSession? {
        val boundaryToken = existingBoundaryToken ?: invalidateGradeyIdentityWork()
        var signedOutSession: GradeyAuthSession? = null
        // Hide the former account before the first suspension. The repository then
        // advances its auth epoch and durably clears the session without waiting for
        // any in-flight refresh/sign-in request; their late responses cannot commit.
        account = null
        try {
            withContext(NonCancellable) {
                try {
                    signedOutSession = graph.gradeyAuthRepository.takeLocalSessionForSignOut()
                } finally {
                    try {
                        clearGradeyIdentityBoundaryState()
                    } finally {
                        // There is no authenticated unregister-device endpoint. Deleting the FCM token makes
                        // the prior account's backend row unusable until delivery marks it invalid.
                        GradeyPushRegistration.invalidateCurrentToken()
                    }
                }
            }
            if (revokeRemoteSession) {
                revokeSignedOutGradeySessionBestEffort(signedOutSession)
            }
            return signedOutSession
        } finally {
            account = null
            if (existingBoundaryToken == null) {
                finishGradeyIdentityBoundaryChange(boundaryToken)
            }
        }
    }

    suspend fun signOutAllGradeyState() {
        val boundaryToken = invalidateGradeyIdentityWork()
        val stravaAccountIDs = linkedAccounts
            .filter { it.provider == LinkedAccountProvider.STRAVA_CZ }
            .map(LinkedSchoolAccount::id)
        var signedOutSession: GradeyAuthSession? = null
        var localCleanupFailure: Throwable? = null
        fun rememberCleanupFailure(error: Throwable) {
            if (localCleanupFailure == null) {
                localCleanupFailure = error
            } else {
                localCleanupFailure?.addSuppressed(error)
            }
        }
        isLoading = true
        account = null
        resetSignedInNavigation()
        phase = AppPhase.SIGNED_OUT
        try {
            try {
                signedOutSession = signOutGradeyIdentity(
                    existingBoundaryToken = boundaryToken,
                    revokeRemoteSession = false,
                )
            } catch (error: Throwable) {
                rememberCleanupFailure(error)
            }
            withContext(NonCancellable) {
                // Complete every durable local teardown before optional remote logout.
                try {
                    disconnectSchool()
                } catch (error: Throwable) {
                    rememberCleanupFailure(error)
                }
                stravaSession = null
                stravaMenu = null
                stravaError = null
                submittingStravaMealID = null
                try {
                    signOutStravaCZLocally()
                } catch (error: Throwable) {
                    // Continue clearing the remaining local state if meals storage is damaged.
                    rememberCleanupFailure(error)
                }
                try {
                    graph.linkedAccountRepository.clearLocalAccounts()
                } catch (error: Throwable) {
                    rememberCleanupFailure(error)
                }
                try {
                    CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
                } catch (_: Throwable) {
                    // Credential Manager cleanup must not undo completed local sign-out.
                }
                graph.guestModeStore.isEnabled = false
                isGuestMode = false
                account = null
                phase = AppPhase.SIGNED_OUT
            }
            revokeSignedOutGradeySessionBestEffort(
                session = signedOutSession,
                linkedAccountIDsToUnlink = stravaAccountIDs,
            )
            localCleanupFailure?.let { throw it }
        } finally {
            isLoading = false
            finishGradeyIdentityBoundaryChange(boundaryToken)
        }
    }

    suspend fun exportGradeyData() {
        if (isExportingData || isDeletingAccount || account == null) return
        val exportOwner = currentGradeyIdentityOwner() ?: return
        isExportingData = true
        privacyDataError = null
        try {
            exportOwner.requireCurrent()
            val session = graph.gradeyAuthRepository.validSession()
            exportOwner.requireCurrent()
            val payload = graph.devicePushTokenClient.requestDataExport(session)
            exportOwner.requireCurrent()
            GradeyJson.parseToJsonElement(payload)
            val exportDirectory = File(context.cacheDir, "exports")
            check(exportDirectory.exists() || exportDirectory.mkdirs()) {
                context.getString(R.string.export_folder_failed)
            }
            val exportFile = File(exportDirectory, "gradey-data-${LocalDate.now()}.json")
            exportFile.writeText(payload, Charsets.UTF_8)
            val contentUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.files",
                exportFile,
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, contentUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(
                Intent.createChooser(shareIntent, context.getString(R.string.share_gradey_data)),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (exportOwner.isCurrent()) expireGradeyIdentity(error)
        } catch (error: Throwable) {
            if (exportOwner.isCurrent()) privacyDataError = error.userFacingMessage(context)
        } finally {
            if (exportOwner.isCurrent()) isExportingData = false
        }
    }

    suspend fun deleteGradeyAccount() {
        if (isDeletingAccount || isExportingData || account == null) return
        val deleteOwner = currentGradeyIdentityOwner() ?: return
        var deleteBoundaryToken: Long? = null
        isDeletingAccount = true
        privacyDataError = null
        try {
            deleteOwner.requireCurrent()
            val session = graph.gradeyAuthRepository.validSession()
            deleteOwner.requireCurrent()
            graph.devicePushTokenClient.deleteAccount(session)
            deleteOwner.requireCurrent()
            val boundaryToken = invalidateGradeyIdentityWork()
            deleteBoundaryToken = boundaryToken
            isDeletingAccount = true
            withContext(NonCancellable) {
                try {
                    signOutStravaCZLocally()
                } catch (_: Throwable) {
                    // Continue clearing all other local identity state.
                }
                stravaSession = null
                stravaMenu = null
                stravaError = null
                try {
                    signOutGradeyIdentity(existingBoundaryToken = boundaryToken)
                } catch (_: Throwable) {
                    // The helper clears local Gradey state in its finally block.
                }
                try {
                    disconnectSchool()
                } catch (_: Throwable) {
                    // Continue after a damaged optional cache or platform surface.
                }
                try {
                    clearLinkedAccountsForLocalMode()
                } catch (_: Throwable) {
                    linkedAccounts = emptyList()
                }
                try {
                    CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
                } catch (_: Throwable) {
                    // Account deletion and local cleanup are complete even if Google state remains cached.
                }
                graph.guestModeStore.isEnabled = false
                isGuestMode = false
                account = null
                resetSignedInNavigation()
                phase = AppPhase.SIGNED_OUT
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            if (deleteOwner.isCurrent()) expireGradeyIdentity(error)
        } catch (error: Throwable) {
            if (deleteOwner.isCurrent()) privacyDataError = error.userFacingMessage(context)
        } finally {
            deleteBoundaryToken?.let { boundaryToken ->
                isDeletingAccount = false
                finishGradeyIdentityBoundaryChange(boundaryToken)
            }
            if (deleteOwner.isCurrent()) isDeletingAccount = false
        }
    }

    suspend fun publishCurrentWearState() {
        val publicationSession = graph.schoolRepository.currentStoredSession() ?: return
        val displayedTimetable = timetable
        val today = TimetableDates.today()
        val currentWeekStart = TimetableDates.apiDateString(TimetableDates.monday(today))
        val cachedCurrent = if (
            WearPayloadBuilder.currentWeekProjection(displayedTimetable, null, today) == null
        ) {
            try {
                graph.schoolRepository.loadCachedTimetable(currentWeekStart)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
        } else {
            null
        }
        val currentTimetable = WearPayloadBuilder.currentWeekProjection(displayedTimetable, cachedCurrent, today)
            ?: return
        try {
            PhoneWearSyncPublisher.publish(
                context.applicationContext,
                WearPayloadBuilder.signedIn(
                    currentTimetable,
                    dashboardViewModel.currentDashboard?.user,
                    supportTier,
                ),
                isStillCurrent = {
                    activeSchoolSessionForScope(
                        publicationSession.cacheScope,
                        graph.schoolRepository.currentStoredSession(),
                    ) != null
                },
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Support purchases must succeed even when no Wear OS device is paired.
        }
    }

    fun applySupportEntitlement(entitlement: SupportEntitlement) {
        supportTier = entitlement.tier
        supportCatalog = supportCatalog?.copy(
            entitlement = entitlement,
            managementURL = entitlement.managementURL ?: supportCatalog?.managementURL,
        )
    }

    suspend fun loadSupportCatalog() {
        if (isSupportLoading || purchasingSupportOptionID != null || isRestoringSupport) return
        isSupportLoading = true
        supportMessage = null
        try {
            val loaded = supportService.loadCatalog(account?.id.takeUnless { isGuestMode })
            supportCatalog = loaded
            supportTier = loaded.entitlement.tier
            supportMessage = if (loaded.isEmpty) {
                context.getString(com.bukovinafilip.gradey.feature.account.R.string.support_empty)
            } else {
                null
            }
            publishCurrentWearState()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            supportCatalog = null
            supportMessage = error.userFacingMessage(context)
        } finally {
            isSupportLoading = false
        }
    }

    suspend fun purchaseSupportOption(
        optionID: String,
        requiresGradeyID: Boolean,
        requestedPlan: SupportPlanOption? = null,
    ) {
        if (isSupportLoading || purchasingSupportOptionID != null || isRestoringSupport) return
        if (requiresGradeyID && (account == null || isGuestMode)) {
            supportMessage = context.getString(
                com.bukovinafilip.gradey.feature.account.R.string.support_sign_in_required,
            )
            return
        }
        if (requestedPlan != null) {
            val currentCatalog = supportCatalog ?: return
            val currentPlan = currentCatalog.plans.firstOrNull { it.id == optionID } ?: return
            val stillMatchesRequest = currentPlan.productIdentifier == requestedPlan.productIdentifier &&
                currentPlan.tier == requestedPlan.tier &&
                currentPlan.interval == requestedPlan.interval
            if (!stillMatchesRequest || !SupportPlanEligibility.canPurchase(currentCatalog.entitlement, currentPlan)) {
                return
            }
        }
        purchasingSupportOptionID = optionID
        supportMessage = null
        try {
            val result = supportService.purchase(
                activity = activity,
                optionID = optionID,
                expectedPlan = requestedPlan,
            )
            applySupportEntitlement(result.entitlement)
            supportMessage = when (result.outcome) {
                SupportPurchaseOutcome.SUCCESS -> {
                    supportCatalog = supportService.loadCatalog(account?.id.takeUnless { isGuestMode })
                    supportTier = supportCatalog?.entitlement?.tier ?: result.entitlement.tier
                    context.getString(com.bukovinafilip.gradey.feature.account.R.string.support_thank_you)
                }
                SupportPurchaseOutcome.PENDING -> context.getString(
                    com.bukovinafilip.gradey.feature.account.R.string.support_purchase_pending,
                )
                SupportPurchaseOutcome.CANCELLED -> context.getString(
                    com.bukovinafilip.gradey.feature.account.R.string.support_purchase_cancelled,
                )
            }
            publishCurrentWearState()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            supportMessage = error.userFacingMessage(context)
        } finally {
            purchasingSupportOptionID = null
        }
    }

    suspend fun restoreSupportPurchases() {
        if (isRestoringSupport || purchasingSupportOptionID != null) return
        isRestoringSupport = true
        supportMessage = null
        try {
            val restored = supportService.restore(account?.id.takeUnless { isGuestMode })
            applySupportEntitlement(restored)
            supportCatalog = supportService.loadCatalog(account?.id.takeUnless { isGuestMode })
            supportTier = supportCatalog?.entitlement?.tier ?: restored.tier
            supportMessage = if (restored.tier == GradeySupportTier.NONE) {
                context.getString(com.bukovinafilip.gradey.feature.account.R.string.support_restore_none)
            } else {
                context.getString(com.bukovinafilip.gradey.feature.account.R.string.support_restored)
            }
            publishCurrentWearState()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            supportMessage = error.userFacingMessage(context)
        } finally {
            isRestoringSupport = false
        }
    }

    LaunchedEffect(phase, account?.id, isGuestMode) {
        if (phase == AppPhase.CHECKING) return@LaunchedEffect
        val identityKey = account?.id?.takeUnless { isGuestMode } ?: "anonymous"
        supportCatalog = null
        supportMessage = null
        if (resolvedSupportIdentityKey != identityKey) supportTier = GradeySupportTier.NONE
        if (!supportService.isConfigured) {
            supportTier = GradeySupportTier.NONE
            resolvedSupportIdentityKey = identityKey
            return@LaunchedEffect
        }
        try {
            val entitlement = supportService.syncIdentity(account?.id.takeUnless { isGuestMode })
            supportTier = entitlement.tier
            resolvedSupportIdentityKey = identityKey
            publishCurrentWearState()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Preserve a resolved tier through a temporary outage, but never across identities.
        }
    }

    LaunchedEffect(
        onboardingProgress?.journey,
        onboardingProgress?.step,
        account?.id,
        isGuestMode,
    ) {
        if (
            onboardingProgress?.journey == OnboardingJourney.UPGRADE &&
            onboardingProgress?.step == OnboardingStep.SUPPORT &&
            !isGuestMode
        ) {
            account?.id?.let { migrateOnboardingUpgradeConnections(it) }
        }
    }

    LaunchedEffect(
        onboardingProgress?.journey,
        onboardingProgress?.step,
        onboardingUpgradeIdentityKey,
    ) {
        if (
            onboardingProgress?.journey == OnboardingJourney.UPGRADE &&
            onboardingProgress?.step == OnboardingStep.SUPPORT
        ) {
            loadSupportCatalog()
        }
    }

    LaunchedEffect(ageAttestationKind) {
        if (ageAttestationKind == null) return@LaunchedEffect
        if (isGuestMode) {
            try {
                signOutGradeyIdentity()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Guest mode remains usable if the cloud logout endpoint is unavailable.
            }
            clearLinkedAccountsForLocalMode()
        }

        var startupGradeyIdentityExpired = false
        val authSession = if (graph.isGradeyCloudConfigured && !isGuestMode) {
            val restored = try {
                graph.gradeyAuthRepository.bootstrapSession()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            if (restored == null) {
                null
            } else {
                try {
                    val valid = graph.gradeyAuthRepository.validSession()
                    try {
                        valid.copy(account = graph.gradeyAuthRepository.refreshAccount())
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: GradeySessionExpiredException) {
                        startupGradeyIdentityExpired = true
                        expireGradeyIdentity(error)
                        null
                    } catch (_: Throwable) {
                        // Profile refresh is opportunistic; retain the encrypted account snapshot.
                        valid
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: GradeySessionExpiredException) {
                    startupGradeyIdentityExpired = true
                    expireGradeyIdentity(error)
                    null
                } catch (_: Throwable) {
                    // A temporary cloud outage must not discard the restored account or school session.
                    restored
                }
            }
        } else {
            null
        }
        if (startupGradeyIdentityExpired) return@LaunchedEffect
        account = authSession?.account
        val startupIdentityOwner = currentOnboardingIdentityOwner() ?: return@LaunchedEffect
        val startupRefreshOwner = currentGradeyIdentityOwner()
        val storedNotificationRecoveryOwner =
            graph.onboardingProgressStore.notificationSyncOwnerAccountID
        val hasStoredNotificationRecovery =
            graph.onboardingProgressStore.notificationPermissionRecoveryNeeded ||
                graph.onboardingProgressStore.notificationPreferenceSyncPending ||
                graph.onboardingProgressStore.notificationPushRegistrationPending
        if (
            hasStoredNotificationRecovery &&
            account != null &&
            storedNotificationRecoveryOwner != account?.id
        ) {
            clearOnboardingNotificationRecovery()
        }
        var schoolSession = try {
            graph.schoolRepository.bootstrapSession()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        var refreshedLinkedAccounts: List<LinkedSchoolAccount>? = null
        if (authSession != null && startupRefreshOwner != null) {
            val snapshot = try {
                graph.linkedAccountRepository.refreshAccounts()
            } catch (_: GradeyIdentityChangedException) {
                null
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            if (
                !startupRefreshOwner.isCurrent(
                    account?.id,
                    gradeyIdentityGeneration,
                    isGuestMode,
                )
            ) return@LaunchedEffect
            if (snapshot != null) {
                refreshedLinkedAccounts = snapshot.linkedAccounts
                linkedAccounts = snapshot.linkedAccounts
            }
            if (
                shouldDetachSchoolAssociationAfterAuthoritativeRefresh(
                    session = schoolSession,
                    authoritativeAccounts = snapshot?.linkedAccounts,
                )
            ) {
                startupRefreshOwner.requireCurrent()
                schoolSession = try {
                    graph.schoolRepository
                        .invalidateSchoolCloudMutationsAndDisassociate()
                        .retainedSession
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    try {
                        graph.schoolRepository.logout()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // The in-memory startup projection still fails closed below.
                    }
                    null
                }
                startupRefreshOwner.requireCurrent()
            }
            if (schoolSession == null) {
                val preferred = selectRestorableSchoolAccount(
                    accounts = snapshot?.linkedAccounts ?: linkedAccounts,
                    preferredAccountID = snapshot?.activeSchoolAccountID,
                )
                if (preferred != null) {
                    schoolSession = try {
                        startupRefreshOwner.requireCurrent()
                        val cloudMutationToken = graph.schoolRepository.captureSchoolCloudMutationToken()
                        startupRefreshOwner.requireCurrent()
                        val activation = graph.linkedAccountRepository.activateSchoolAccount(preferred.id)
                        startupRefreshOwner.requireCurrent()
                        val activatedSession = graph.schoolRepository.activateLinkedSchoolAccount(
                            activation.tokenPayload.makeStoredSession(activation.account),
                            cloudMutationToken,
                        )
                        startupRefreshOwner.requireCurrent()
                        activatedSession
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        null
                    }
                } else {
                    reconnectLinkedAccount = selectSchoolAccountRequiringReconnect(
                        accounts = snapshot?.linkedAccounts.orEmpty(),
                        preferredAccountID = snapshot?.activeSchoolAccountID,
                    )
                    reconnectLinkedAccountID = reconnectLinkedAccount?.id
                }
            }
        }
        if (
            reconnectLinkedAccountID != null &&
            linkedAccounts.none { it.id == reconnectLinkedAccountID }
        ) {
            linkedAccounts = try {
                graph.linkedAccountRepository.localAccounts()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                linkedAccounts
            }
        }
        if (schoolSession == null) {
            // Reconcile durable platform surfaces on every cold start. A process can die after the
            // secure session is cleared but before the expiring request redraws the widget or sends
            // signed-out Wear state; startup is the next authoritative chance to finish that work.
            clearSchoolPlatformProjectionsAfterAccountChange(onlyWhileSignedOut = true)
        }
        activeLinkedAccountID = schoolSession?.linkedAccountID
        currentSchoolBaseURL = schoolSession?.baseURL.orEmpty()
        phase = when (
            selectGradeyStartupDestination(
                isCloudConfigured = graph.isGradeyCloudConfigured,
                isGuestMode = isGuestMode,
                hasGradeySession = authSession != null,
                hasSchoolSession = schoolSession != null,
            )
        ) {
            GradeyStartupDestination.SIGNED_OUT -> AppPhase.SIGNED_OUT
            GradeyStartupDestination.NEEDS_SCHOOL -> AppPhase.NEEDS_SCHOOL
            GradeyStartupDestination.SIGNED_IN -> AppPhase.SIGNED_IN
        }
        val isSchoolCloudLinked = isCurrentSchoolCloudLinked(
            linkedAccountID = schoolSession?.linkedAccountID,
            refreshedAccounts = refreshedLinkedAccounts,
        )
        val resolvedOnboarding = graph.onboardingProgressStore.resolve(
            hasSchoolSession = schoolSession != null,
        )?.let { progress ->
            reconcileOnboardingProgress(
                progress = progress,
                isGuestMode = isGuestMode,
                hasGradeySession = authSession != null,
                hasSchoolSession = schoolSession != null,
                isSchoolCloudLinked = isSchoolCloudLinked,
            )
        }
        if (resolvedOnboarding != null) {
            graph.onboardingProgressStore.saveProgress(resolvedOnboarding)
        }
        onboardingProgress = resolvedOnboarding
        val notificationPermissionRecoveryWasPending =
            graph.onboardingProgressStore.notificationPermissionRecoveryNeeded
        notificationPermissionGranted = context.notificationsAreEnabled()
        onboardingNotificationNeedsSystemSettings =
            notificationPermissionRecoveryWasPending && !notificationPermissionGranted
        onboardingNotificationPreferenceSyncPending =
            graph.onboardingProgressStore.notificationPreferenceSyncPending
        onboardingNotificationPushRegistrationPending =
            graph.onboardingProgressStore.notificationPushRegistrationPending
        val notificationRecoveryProgress = resolvedOnboarding
        val notificationRecoveryOwner = currentOnboardingIdentityOwner()
        if (
            notificationPermissionRecoveryWasPending &&
            notificationPermissionGranted &&
            notificationRecoveryOwner != null &&
            notificationRecoveryProgress != null &&
            notificationRecoveryProgress.step in
            setOf(OnboardingStep.NOTIFICATIONS, OnboardingStep.READY)
        ) {
            isHandlingOnboardingNotificationChoice = true
            try {
                val canAdvance = persistOnboardingNotificationPreference(
                    enabled = true,
                    owner = notificationRecoveryOwner,
                )
                if (!notificationRecoveryOwner.isCurrent()) return@LaunchedEffect
                setOnboardingNotificationPermissionRecoveryNeeded(false)
                if (canAdvance && notificationRecoveryProgress.step == OnboardingStep.NOTIFICATIONS) {
                    val ready = notificationRecoveryProgress.copy(step = OnboardingStep.READY)
                    graph.onboardingProgressStore.saveProgress(ready)
                    onboardingProgress = ready
                }
                if (canAdvance) refreshOnboardingPushRegistration(notificationRecoveryOwner)
            } finally {
                if (notificationRecoveryOwner.isCurrent()) {
                    isHandlingOnboardingNotificationChoice = false
                }
            }
        }
        onboardingSchoolCloudLinkFailed = shouldShowOnboardingSchoolCloudLinkWarning(
            progress = resolvedOnboarding,
            isGuestMode = isGuestMode,
            hasGradeySession = authSession != null,
            hasSchoolSession = schoolSession != null,
            isSchoolCloudLinked = isSchoolCloudLinked,
        )
        onboardingSchoolCloudLinkError = null

        if (resolvedOnboarding == null) {
            val restoredSchoolRoute = restoreSchoolRoute(
                isAddingSchool = isAddingSchool,
                reconnectAccountID = reconnectLinkedAccountID,
                hasSchoolSession = schoolSession != null,
                availableLinkedAccountIDs = linkedAccounts
                    .filter { it.provider.isSupportedSchoolProvider }
                    .mapTo(mutableSetOf()) { it.id },
            )
            when (restoredSchoolRoute.destination) {
                RestoredSchoolDestination.ADD_SCHOOL -> {
                    reconnectLinkedAccount = null
                    reconnectLinkedAccountID = null
                    applyReconnectPrefill(null)
                    phase = AppPhase.NEEDS_SCHOOL
                }
                RestoredSchoolDestination.RECONNECT_SCHOOL -> {
                    isAddingSchool = false
                    reconnectLinkedAccountID = restoredSchoolRoute.reconnectAccountID
                    reconnectLinkedAccount = linkedAccounts.firstOrNull {
                        it.id == restoredSchoolRoute.reconnectAccountID &&
                            it.provider.isSupportedSchoolProvider
                    }
                    applyReconnectPrefill(
                        reconnectLinkedAccount?.let { account ->
                            SchoolReconnectPrefills.resolve(schoolSession, account, linkedAccounts)
                        },
                    )
                    phase = AppPhase.NEEDS_SCHOOL
                }
                RestoredSchoolDestination.NONE -> {
                    if (schoolSession != null) {
                        isAddingSchool = false
                        reconnectLinkedAccountID = null
                        applyReconnectPrefill(null)
                    }
                }
            }
        }

        if (resolvedOnboarding == null && schoolSession != null) {
            loadCachedSignedInData(isStillCurrent = { startupIdentityOwner.isCurrent() })
            if (!startupIdentityOwner.isCurrent()) return@LaunchedEffect
            if (phase == AppPhase.SIGNED_IN) {
                isLoading = true
                try {
                    refreshSignedInData()
                } finally {
                    isLoading = false
                }
            }
        }
    }

    if (ageAttestationKind == null) {
        AgeAttestationScreen(
            onConfirm = { kind ->
                graph.ageAttestationStore.confirm(kind)
                ageAttestationKind = kind
            },
            onOpenPrivacyPolicy = {
                runCatching {
                    context.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse(privacyPolicyUrl(activeLanguageCode)),
                        ),
                    )
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    } else if (onboardingProgress != null) {
        val progress = onboardingProgress ?: return
        when (progress.step) {
                OnboardingStep.WELCOME -> OnboardingWelcomeScreen(
                    appLanguage = appLanguage,
                    onAppLanguageChange = onAppLanguageChange,
                    onContinue = {
                        onboardingAccountIntent = OnboardingAccountIntent.GET_STARTED
                        persistOnboarding(progress.copy(step = OnboardingStep.ACCOUNT))
                        if (account != null || isGuestMode) {
                            scope.launch { advanceOnboardingAfterAccountChoice() }
                        }
                    },
                    onLogIn = {
                        onboardingAccountIntent = OnboardingAccountIntent.LOG_IN
                        persistOnboarding(progress.copy(step = OnboardingStep.ACCOUNT))
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.ACCOUNT -> GradeyIdLoginScreen(
                    isLoading = isLoading,
                    errorMessage = authError,
                    isGoogleSignInAvailable = graph.isGradeyCloudConfigured,
                    isUpgradeJourney = progress.journey == OnboardingJourney.UPGRADE,
                    accountIntent = onboardingAccountIntent,
                    progressPosition = 1,
                    progressCount = if (progress.journey == OnboardingJourney.UPGRADE) 2 else 4,
                    onGoogleSignIn = {
                        scope.launch {
                            isLoading = true
                            authError = null
                            var identityBoundaryToken: Long? = null
                            try {
                                val googleCredential = requestGoogleCredential(context, graph.googleWebClientId)
                                val preparedBoundaryToken = prepareForInteractiveGradeyIdentityAdoption()
                                identityBoundaryToken = preparedBoundaryToken
                                val signedInAccount = graph.gradeyAuthRepository.signInWithGoogle(
                                    idToken = googleCredential.idToken,
                                    fullName = googleCredential.displayName,
                                ).account
                                withContext(NonCancellable) {
                                    clearGradeyIdentityBoundaryState()
                                    // Rotate only after the replacement session is durable. If Firebase
                                    // delivers onNewToken concurrently, registration is then owned by B,
                                    // never by the outgoing account A.
                                    GradeyPushRegistration.invalidateCurrentToken()
                                }
                                account = signedInAccount
                                finishGradeyIdentityBoundaryChange(preparedBoundaryToken)
                                identityBoundaryToken = null
                                graph.guestModeStore.isEnabled = false
                                isGuestMode = false
                                advanceOnboardingAfterAccountChoice()
                            } catch (error: CancellationException) {
                                identityBoundaryToken?.let(::finishGradeyIdentityBoundaryChange)
                                throw error
                            } catch (error: Throwable) {
                                identityBoundaryToken?.let(::finishGradeyIdentityBoundaryChange)
                                authError = error.userFacingMessage(context)
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onContinueWithoutAccount = {
                        scope.launch {
                            isLoading = true
                            authError = null
                            graph.guestModeStore.isEnabled = true
                            isGuestMode = true
                            account = null
                            try {
                                signOutGradeyIdentity()
                                clearLinkedAccountsForLocalMode()
                                advanceOnboardingAfterAccountChoice()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                authError = error.userFacingMessage(context)
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onOpenHelp = {
                        val language = helpCenterLanguageCode(activeLanguageCode)
                        runCatching {
                            activity.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://help.bukovinafilip.com/$language"),
                                ),
                            )
                        }
                    },
                    onOpenGitHub = {
                        runCatching {
                            activity.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/FBukovina/Gradely")),
                            )
                        }
                    },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize().statusBarsPadding(),
                )

                OnboardingStep.SCHOOL -> SchoolLoginScreen(
                    isLoading = isLoading,
                    stateScopeKey = "onboarding-school",
                    errorMessage = schoolLoginError,
                    directorySchools = directorySchools,
                    isDirectoryLoading = isSchoolDirectoryLoading,
                    directoryErrorMessage = schoolDirectoryError,
                    onLoadDirectory = { scope.launch { loadSchoolDirectory() } },
                    onRetryDirectory = { scope.launch { loadSchoolDirectory(forceRefresh = true) } },
                    onOpenHelp = {
                        val language = helpCenterLanguageCode(activeLanguageCode)
                        runCatching {
                            activity.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://help.bukovinafilip.com/$language"),
                                ),
                            )
                        }
                    },
                    onOpenGitHub = {
                        runCatching {
                            activity.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://github.com/FBukovina/Gradely"),
                                ),
                            )
                        }
                    },
                    onLogin = { school, username, password ->
                        launchSchoolLogin {
                            val schoolSession = loginReplacingSchoolSession(school, username, password)
                            val loginOwner = currentOnboardingIdentityOwner()
                                ?: return@launchSchoolLogin
                            dashboardViewModel.refresh(
                                scopeKey = schoolSession.cacheScope,
                                forceRefresh = false,
                                load = graph.schoolRepository::loadDashboard,
                            )
                            if (!loginOwner.isCurrent()) return@launchSchoolLogin
                            val isSchoolCloudLinked = linkCurrentSchoolIfNeeded()
                            if (!loginOwner.isCurrent()) return@launchSchoolLogin
                            phase = AppPhase.SIGNED_IN
                            advanceOnboardingAfterSchoolConnection(isSchoolCloudLinked)
                        }
                    },
                    onCancelLogin = ::cancelSchoolLogin,
                    onInputChanged = { schoolLoginError = null },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize().statusBarsPadding(),
                )

                OnboardingStep.NOTIFICATIONS -> OnboardingNotificationsScreen(
                    onEnable = {
                        if (!isHandlingOnboardingNotificationChoice) {
                            val notificationOwner = currentOnboardingIdentityOwner()
                                ?: return@OnboardingNotificationsScreen
                            isHandlingOnboardingNotificationChoice = true
                            setOnboardingNotificationPermissionRecoveryNeeded(true)
                            if (
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                !notificationPermissionGranted
                            ) {
                                notificationPermissionRequestOwner = notificationOwner
                                runCatching {
                                    notificationPermissionLauncher.launch(
                                        Manifest.permission.POST_NOTIFICATIONS,
                                    )
                                }.onFailure { error ->
                                    if (notificationOwner.isCurrent()) {
                                        notificationPermissionRequestOwner = null
                                        isHandlingOnboardingNotificationChoice = false
                                        notificationPreferencesError = error.userFacingMessage(context)
                                    }
                                }
                            } else {
                                scope.launch {
                                    try {
                                        notificationOwner.requireCurrent()
                                        notificationPermissionGranted = context.notificationsAreEnabled()
                                        val canAdvance = persistOnboardingNotificationPreference(
                                            enabled = true,
                                            owner = notificationOwner,
                                        )
                                        if (!notificationOwner.isCurrent()) return@launch
                                        if (notificationPermissionGranted) {
                                            setOnboardingNotificationPermissionRecoveryNeeded(false)
                                        }
                                        if (canAdvance) {
                                            onboardingNotificationsReturnToReady = false
                                            persistOnboarding(progress.copy(step = OnboardingStep.READY))
                                        }
                                        if (canAdvance && notificationPermissionGranted) {
                                            refreshOnboardingPushRegistration(notificationOwner)
                                        }
                                    } finally {
                                        if (notificationOwner.isCurrent()) {
                                            isHandlingOnboardingNotificationChoice = false
                                        }
                                    }
                                }
                            }
                        }
                    },
                    onNotNow = {
                        if (!isHandlingOnboardingNotificationChoice) {
                            val notificationOwner = currentOnboardingIdentityOwner()
                                ?: return@OnboardingNotificationsScreen
                            isHandlingOnboardingNotificationChoice = true
                            scope.launch {
                                try {
                                    notificationOwner.requireCurrent()
                                    setOnboardingNotificationPermissionRecoveryNeeded(false)
                                    val canAdvance = persistOnboardingNotificationPreference(
                                        enabled = false,
                                        owner = notificationOwner,
                                    )
                                    if (!notificationOwner.isCurrent()) return@launch
                                    if (canAdvance) {
                                        onboardingNotificationsReturnToReady = false
                                        persistOnboarding(progress.copy(step = OnboardingStep.READY))
                                    }
                                } finally {
                                    if (notificationOwner.isCurrent()) {
                                        isHandlingOnboardingNotificationChoice = false
                                    }
                                }
                            }
                        }
                    },
                    onBack = {
                        if (onboardingNotificationsReturnToReady) {
                            onboardingNotificationsReturnToReady = false
                            persistOnboarding(progress.copy(step = OnboardingStep.READY))
                        } else {
                            goBackInOnboarding()
                        }
                    },
                    isWorking = isHandlingOnboardingNotificationChoice,
                    progressPosition = 3,
                    progressCount = 4,
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.READY -> OnboardingReadyScreen(
                    isGuestMode = isGuestMode,
                    notificationsEnabled = onboardingNotificationsEnabled(
                        preferences = notificationPreferences,
                        permissionGranted = notificationPermissionGranted,
                    ) && !onboardingSchoolCloudLinkFailed,
                    schoolCloudLinkFailed = onboardingSchoolCloudLinkFailed,
                    schoolCloudLinkErrorMessage = onboardingSchoolCloudLinkError,
                    isRetryingSchoolCloudLink = isRetryingOnboardingSchoolCloudLink,
                    onRetrySchoolCloudLink = {
                        if (
                            !isRetryingOnboardingSchoolCloudLink &&
                            !isHandlingOnboardingNotificationChoice
                        ) {
                            isRetryingOnboardingSchoolCloudLink = true
                            scope.launch {
                                try {
                                    val linked = linkCurrentSchoolIfNeeded()
                                    if (onboardingProgress?.step != OnboardingStep.READY) {
                                        return@launch
                                    } else if (!linked && account == null && !isGuestMode) {
                                        onboardingSchoolCloudLinkFailed = false
                                        onboardingSchoolCloudLinkError = null
                                        persistOnboarding(progress.copy(step = OnboardingStep.ACCOUNT))
                                    } else if (linked) {
                                        onboardingSchoolCloudLinkFailed = false
                                        onboardingSchoolCloudLinkError = null
                                        onboardingNotificationsReturnToReady = true
                                        persistOnboarding(progress.copy(step = OnboardingStep.NOTIFICATIONS))
                                    } else {
                                        onboardingSchoolCloudLinkFailed = true
                                        onboardingSchoolCloudLinkError = linkedAccountError
                                    }
                                } finally {
                                    isRetryingOnboardingSchoolCloudLink = false
                                }
                            }
                        }
                    },
                    notificationSyncErrorMessage = notificationPreferencesError.takeIf {
                        !isGuestMode && !onboardingSchoolCloudLinkFailed
                    },
                    notificationSyncPending =
                        (
                            onboardingNotificationPreferenceSyncPending ||
                                onboardingNotificationPushRegistrationPending
                            ) &&
                        !isGuestMode &&
                        !onboardingSchoolCloudLinkFailed,
                    isRetryingNotificationSync = isHandlingOnboardingNotificationChoice,
                    isFinishing = isLoading,
                    onRetryNotificationSync = {
                        if (
                            !isHandlingOnboardingNotificationChoice &&
                            !isRetryingOnboardingSchoolCloudLink
                        ) {
                            val notificationOwner = currentOnboardingIdentityOwner()
                                ?: return@OnboardingReadyScreen
                            isHandlingOnboardingNotificationChoice = true
                            scope.launch {
                                try {
                                    val canContinue = persistOnboardingNotificationPreference(
                                        enabled = notificationPreferences.newMarksEnabled,
                                        owner = notificationOwner,
                                    )
                                    if (!notificationOwner.isCurrent()) return@launch
                                    if (
                                        canContinue &&
                                        notificationPreferences.newMarksEnabled &&
                                        notificationPermissionGranted
                                    ) {
                                        refreshOnboardingPushRegistration(notificationOwner)
                                    }
                                } finally {
                                    if (notificationOwner.isCurrent()) {
                                        isHandlingOnboardingNotificationChoice = false
                                    }
                                }
                            }
                        }
                    },
                    showNotificationSettingsAction =
                        onboardingNotificationNeedsSystemSettings &&
                        !isGuestMode &&
                        !onboardingSchoolCloudLinkFailed,
                    onOpenNotificationSettings = {
                        currentOnboardingIdentityOwner()?.let { notificationOwner ->
                            notificationSettingsRequestOwner = notificationOwner
                            notificationSettingsLauncher.launch(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                                    Settings.EXTRA_APP_PACKAGE,
                                    context.packageName,
                                ),
                            )
                        }
                    },
                    progressPosition = if (
                        isGuestMode || onboardingSchoolCloudLinkFailed
                    ) 3 else 4,
                    progressCount = if (
                        isGuestMode || onboardingSchoolCloudLinkFailed
                    ) 3 else 4,
                    onFinish = {
                        if (
                            !isRetryingOnboardingSchoolCloudLink &&
                            !isHandlingOnboardingNotificationChoice
                        ) {
                            scope.launch {
                                isLoading = true
                                try {
                                    finishOnboarding()
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (error: Throwable) {
                                    dataError = error.userFacingMessage(context)
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onBack = {
                        if (
                            !isRetryingOnboardingSchoolCloudLink &&
                            !isHandlingOnboardingNotificationChoice
                        ) {
                            goBackInOnboarding()
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.SUPPORT -> {
                    val upgradeCloudLinkWorking =
                        isOnboardingUpgradeCloudLinkWorking || isLoading
                    val canFinishUpgrade = canFinishUpgradeOnboarding(
                        isGuestMode = isGuestMode,
                        hasGradeySession = account != null,
                        hasRecordedSchoolMigration =
                            onboardingUpgradeSchoolCloudLinkState !=
                            OnboardingUpgradeCloudLinkState.PENDING,
                        hasRecordedMealsMigration =
                            onboardingUpgradeMealsCloudLinkState !=
                            OnboardingUpgradeCloudLinkState.PENDING,
                        isWorking = upgradeCloudLinkWorking,
                    )
                    OnboardingUpgradeSupportScreen(
                        schoolCloudLinkFailed =
                            onboardingUpgradeSchoolCloudLinkState ==
                            OnboardingUpgradeCloudLinkState.FAILED,
                        schoolCloudLinkErrorMessage = onboardingUpgradeSchoolCloudLinkError,
                        mealsCloudLinkFailed =
                            onboardingUpgradeMealsCloudLinkState ==
                            OnboardingUpgradeCloudLinkState.FAILED,
                        mealsCloudLinkErrorMessage = onboardingUpgradeMealsCloudLinkError,
                        isWorking = upgradeCloudLinkWorking,
                        isRetryingSchoolCloudLink =
                            onboardingUpgradeRetryTarget == OnboardingUpgradeRetryTarget.SCHOOL,
                        isRetryingMealsCloudLink =
                            onboardingUpgradeRetryTarget == OnboardingUpgradeRetryTarget.MEALS,
                        canFinish = canFinishUpgrade,
                        onRetrySchoolCloudLink = account?.id?.let { ownerAccountID ->
                            {
                                if (!isOnboardingUpgradeCloudLinkWorking && !isLoading) {
                                    scope.launch {
                                        retryOnboardingUpgradeSchoolCloudLink(ownerAccountID)
                                    }
                                }
                            }
                        },
                        onRetryMealsCloudLink = account?.id?.let { ownerAccountID ->
                            {
                                if (!isOnboardingUpgradeCloudLinkWorking && !isLoading) {
                                    scope.launch {
                                        retryOnboardingUpgradeMealsCloudLink(ownerAccountID)
                                    }
                                }
                            }
                        },
                        onFinish = {
                            if (canFinishUpgrade && !upgradeCloudLinkWorking) {
                                scope.launch {
                                    isLoading = true
                                    try {
                                        finishOnboarding()
                                    } catch (error: CancellationException) {
                                        throw error
                                    } catch (error: Throwable) {
                                        dataError = error.userFacingMessage(context)
                                    } finally {
                                        isLoading = false
                                    }
                                }
                            }
                        },
                        progressPosition = 2,
                        progressCount = 2,
                        supportOptionsContent = {
                            OnboardingSupportOptionsContent(
                                catalog = supportCatalog,
                                isSignedIn = account != null && !isGuestMode,
                                isConfigured = supportService.isConfigured,
                                isLoading = isSupportLoading,
                                purchasingOptionID = purchasingSupportOptionID,
                                isRestoring = isRestoringSupport,
                                message = supportMessage,
                                onReload = { scope.launch { loadSupportCatalog() } },
                                onPurchasePlan = { plan: SupportPlanOption ->
                                    scope.launch {
                                        purchaseSupportOption(
                                            plan.id,
                                            requiresGradeyID = true,
                                            requestedPlan = plan,
                                        )
                                    }
                                },
                                onPurchaseTip = { optionID ->
                                    scope.launch {
                                        purchaseSupportOption(optionID, requiresGradeyID = false)
                                    }
                                },
                                onRestore = { scope.launch { restoreSupportPurchases() } },
                                onManageSubscription = {
                                    val url = supportCatalog?.managementURL
                                        ?: "https://play.google.com/store/account/subscriptions?package=${activity.packageName}"
                                    runCatching {
                                        activity.startActivity(
                                            Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                                        )
                                    }
                                },
                                onOpenPrivacyPolicy = {
                                    runCatching {
                                        activity.startActivity(
                                            Intent(
                                                Intent.ACTION_VIEW,
                                                Uri.parse(privacyPolicyUrl(activeLanguageCode)),
                                            ),
                                        )
                                    }
                                },
                                onOpenTermsOfUse = {
                                    val language = helpCenterLanguageCode(activeLanguageCode)
                                    runCatching {
                                        activity.startActivity(
                                            Intent(
                                                Intent.ACTION_VIEW,
                                                Uri.parse(
                                                    "https://help.bukovinafilip.com/" +
                                                        "$language/articles/11-terms-and-conditions",
                                                ),
                                            ),
                                        )
                                    }
                                },
                                enabled = !upgradeCloudLinkWorking,
                            )
                        },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
        }
    } else when (phase) {
        AppPhase.CHECKING -> GradeyCheckingScreen()
        AppPhase.SIGNED_OUT -> GradeyIdLoginScreen(
            isLoading = isLoading,
            errorMessage = authError,
            onGoogleSignIn = {
                scope.launch {
                    isLoading = true
                    authError = null
                    var identityBoundaryToken: Long? = null
                    try {
                        val googleCredential = requestGoogleCredential(context, graph.googleWebClientId)
                        val preparedBoundaryToken = prepareForInteractiveGradeyIdentityAdoption()
                        identityBoundaryToken = preparedBoundaryToken
                        val signedInAccount = graph.gradeyAuthRepository.signInWithGoogle(
                            idToken = googleCredential.idToken,
                            fullName = googleCredential.displayName,
                        ).account
                        withContext(NonCancellable) {
                            clearGradeyIdentityBoundaryState()
                            // Rotate only after the replacement session is durable. If Firebase
                            // delivers onNewToken concurrently, registration is then owned by B,
                            // never by the outgoing account A.
                            GradeyPushRegistration.invalidateCurrentToken()
                        }
                        account = signedInAccount
                        finishGradeyIdentityBoundaryChange(preparedBoundaryToken)
                        identityBoundaryToken = null
                        graph.guestModeStore.isEnabled = false
                        isGuestMode = false
                        val schoolSession = graph.schoolRepository.currentStoredSession()
                        if (schoolSession != null) {
                            dashboardViewModel.loadCached(
                                scopeKey = schoolSession.cacheScope,
                                load = graph.schoolRepository::loadCachedDashboard,
                            )
                            if (dashboardViewModel.currentDashboard == null) {
                                dashboardViewModel.refresh(
                                    scopeKey = schoolSession.cacheScope,
                                    forceRefresh = false,
                                    load = graph.schoolRepository::loadDashboard,
                                )
                            }
                            linkCurrentSchoolIfNeeded()
                        }
                        openStoredSchoolOrLogin()
                    } catch (error: CancellationException) {
                        identityBoundaryToken?.let(::finishGradeyIdentityBoundaryChange)
                        throw error
                    } catch (error: Throwable) {
                        identityBoundaryToken?.let(::finishGradeyIdentityBoundaryChange)
                        authError = error.userFacingMessage(context)
                    } finally {
                        isLoading = false
                    }
                }
            },
            onContinueWithoutAccount = {
                scope.launch {
                    isLoading = true
                    authError = null
                    graph.guestModeStore.isEnabled = true
                    isGuestMode = true
                    account = null
                    try {
                        signOutGradeyIdentity()
                        clearLinkedAccountsForLocalMode()
                        openStoredSchoolOrLogin()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        authError = error.userFacingMessage(context)
                    } finally {
                        isLoading = false
                    }
                }
            },
            onOpenHelp = {
                val language = helpCenterLanguageCode(activeLanguageCode)
                runCatching {
                    activity.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://help.bukovinafilip.com/$language"),
                        ),
                    )
                }
            },
            onOpenGitHub = {
                runCatching {
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/FBukovina/Gradely")),
                    )
                }
            },
        )

        AppPhase.NEEDS_SCHOOL -> SchoolLoginScreen(
            isLoading = isLoading,
            initialSchoolURL = reconnectSchoolURL,
            initialSchoolName = reconnectSchoolName,
            initialUsername = reconnectSchoolUsername,
            stateScopeKey = when {
                reconnectLinkedAccountID != null -> "reconnect:${reconnectLinkedAccountID.orEmpty()}"
                isAddingSchool -> "add-school"
                else -> "school-login"
            },
            title = if (reconnectLinkedAccount == null) {
                context.getString(R.string.connect_bakalari)
            } else {
                context.getString(R.string.reconnect_school, reconnectLinkedAccount?.displayName.orEmpty())
            },
            subtitle = if (reconnectLinkedAccount == null) {
                context.getString(R.string.connect_bakalari_subtitle)
            } else {
                context.getString(R.string.reconnect_school_subtitle)
            },
            errorMessage = schoolLoginError,
            directorySchools = directorySchools,
            isDirectoryLoading = isSchoolDirectoryLoading,
            directoryErrorMessage = schoolDirectoryError,
            onLoadDirectory = { scope.launch { loadSchoolDirectory() } },
            onRetryDirectory = { scope.launch { loadSchoolDirectory(forceRefresh = true) } },
            onOpenHelp = {
                val language = helpCenterLanguageCode(activeLanguageCode)
                runCatching {
                    activity.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://help.bukovinafilip.com/$language"),
                        ),
                    )
                }
            },
            onOpenGitHub = {
                runCatching {
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/FBukovina/Gradely")),
                    )
                }
            },
            onLogin = { school, username, password ->
                launchSchoolLogin {
                    val reconnectTarget = reconnectLinkedAccount
                    if (reconnectTarget != null) {
                        val reconnectError = reconnectLinkedAccountWithCredentials(
                            reconnectTarget,
                            school,
                            username,
                            password,
                        )
                        if (reconnectError != null) {
                            schoolLoginError = reconnectError
                        } else {
                            val loginOwner = currentOnboardingIdentityOwner()
                                ?: return@launchSchoolLogin
                            isAddingSchool = false
                            reconnectLinkedAccountID = null
                            resetSignedInNavigation()
                            phase = AppPhase.SIGNED_IN
                            loadCachedSignedInData(isStillCurrent = { loginOwner.isCurrent() })
                            if (!loginOwner.isCurrent()) return@launchSchoolLogin
                            refreshSignedInData()
                        }
                    } else {
                        val schoolSession = loginReplacingSchoolSession(school, username, password)
                        val loginOwner = currentOnboardingIdentityOwner()
                            ?: return@launchSchoolLogin
                        dashboardViewModel.refresh(
                            scopeKey = schoolSession.cacheScope,
                            forceRefresh = false,
                            load = graph.schoolRepository::loadDashboard,
                        )
                        if (!loginOwner.isCurrent()) return@launchSchoolLogin
                        linkCurrentSchoolIfNeeded()
                        if (!loginOwner.isCurrent()) return@launchSchoolLogin
                        isAddingSchool = false
                        reconnectLinkedAccountID = null
                        resetSignedInNavigation()
                        phase = AppPhase.SIGNED_IN
                        loadCachedSignedInData(isStillCurrent = { loginOwner.isCurrent() })
                        if (!loginOwner.isCurrent()) return@launchSchoolLogin
                        refreshSignedInData()
                    }
                }
            },
            onCancelLogin = ::cancelSchoolLogin,
            onInputChanged = { schoolLoginError = null },
            onBack = if (reconnectLinkedAccount == null && !isAddingSchool) {
                null
            } else {
                {
                    reconnectLinkedAccount = null
                    reconnectLinkedAccountID = null
                    applyReconnectPrefill(null)
                    isAddingSchool = false
                    schoolLoginError = null
                    phase = AppPhase.SIGNED_IN
                    navigationViewModel.requestDestination(MainDestination.ACCOUNT)
                }
            },
        )

        AppPhase.SIGNED_IN -> Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        ) {
            val standardScreenModifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(bottom = 96.dp)
            val currentDashboard = dashboardState.dashboard
            val currentAbsence = absence
            val effectiveAbsence = currentAbsence ?: currentDashboard?.let {
                AbsenceResponse(absencesPerSubject = it.absencesPerSubject)
            }
            val isDashboardLoading = isLoading || dashboardState.isLoading
            val todayPresentationState = TodayPresentationStates.resolve(
                hasDashboard = currentDashboard != null,
                hasSubjects = currentDashboard?.marksResponse?.subjects?.isNotEmpty() == true,
                isLoading = isDashboardLoading,
                hasError = dataError != null || dashboardState.failure != null,
            )
            val absencePresentationState = AbsencePresentationStates.resolve(
                hasResponse = currentAbsence != null,
                hasRecords = currentAbsence?.let {
                    it.absences.isNotEmpty() || it.absencesPerSubject.isNotEmpty()
                } == true,
                isLoading = isLoading,
                hasError = absenceRefreshError != null,
            )
            SignedInNavHost(
                navController = signedInNavController,
                modifier = Modifier.fillMaxSize(),
                todayContent = {
                    when (todayPresentationState) {
                    TodayPresentationState.INITIAL_LOADING,
                    TodayPresentationState.FIRST_LOAD_ERROR,
                    -> TodayStateScreen(
                        state = todayPresentationState,
                        errorMessage = dataError,
                        onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                        modifier = standardScreenModifier,
                    )

                    else -> if (currentDashboard != null && effectiveAbsence != null) {
                        TodayScreen(
                            dashboard = currentDashboard,
                            absence = effectiveAbsence,
                            timetable = timetable,
                            stravaMenu = stravaMenu.takeIf { showMealsTab },
                            isMealsConnected = showMealsTab && stravaSession != null,
                            activeLinkedAccountDisplayName = linkedAccounts
                                .firstOrNull { it.id == activeLinkedAccountID }
                                ?.displayName,
                            linkedSchoolAccounts = linkedAccounts,
                            activeLinkedAccountID = activeLinkedAccountID,
                            mutatingLinkedAccountID = mutatingLinkedAccountID,
                            cloudNewMarkEvents = gradeHistorySnapshot
                                ?.takeIf { it.linkedAccountID == activeLinkedAccountID }
                                ?.recentNewMarkEvents
                                .orEmpty(),
                            gradeTrends = gradeHistorySnapshot
                                ?.takeIf { it.linkedAccountID == activeLinkedAccountID }
                                ?.trends
                                .orEmpty(),
                            isRefreshing = todayPresentationState == TodayPresentationState.REFRESHING,
                            onRefresh = {
                                if (!isLoading) {
                                    scope.launch {
                                        isLoading = true
                                        try {
                                            refreshSignedInData(forceRefresh = true)
                                        } finally {
                                            isLoading = false
                                        }
                                    }
                                }
                            },
                            onOpenAccount = {
                                signedInNavController.navigateToMainDestination(MainDestination.ACCOUNT)
                            },
                            onOpenGradeyTools = {
                                signedInNavController.navigateToMainDestination(MainDestination.GRADEY_AI)
                            },
                            onOpenMarks = {
                                signedInNavController.navigateToMainDestination(MainDestination.SUBJECTS)
                            },
                            onOpenAbsence = {
                                signedInNavController.navigateToMainDestination(MainDestination.ABSENCE)
                            },
                            onOpenTimetable = {
                                signedInNavController.navigateToMainDestination(MainDestination.TIMETABLE)
                            },
                            onOpenMeals = {
                                if (!showMealsTab) {
                                    graph.mealsTabPreferenceStore.isVisible = true
                                    showMealsTab = true
                                }
                                signedInNavController.navigateToMainDestination(MainDestination.MEALS)
                            },
                            onActivateLinkedAccount = { linked ->
                                scope.launch {
                                    if (activateLinkedAccount(linked)) refreshSignedInData()
                                }
                            },
                            onReconnectPrefill = { linked -> reconnectPrefillFor(linked) },
                            onReconnectLinkedAccount = { linked, school, username, password ->
                                val error = reconnectLinkedAccountWithCredentials(linked, school, username, password)
                                if (error == null) refreshSignedInData()
                                error
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        TodayStateScreen(
                            state = TodayPresentationState.FIRST_LOAD_ERROR,
                            errorMessage = dataError,
                            onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                            modifier = standardScreenModifier,
                        )
                    }
                    }
                },
                subjectsContent = {
                    if (currentDashboard != null && effectiveAbsence != null) SubjectsScreen(
                    subjects = currentDashboard.marksResponse.subjects,
                    absence = effectiveAbsence,
                    gradeTrends = gradeHistorySnapshot
                        ?.takeIf { it.linkedAccountID == activeLinkedAccountID }
                        ?.trends
                        .orEmpty(),
                    onPredictSubjectAverage = { subject, markText, weight ->
                        withSchoolSessionRecovery {
                            graph.schoolRepository.predictSubjectAverage(subject, markText, weight)
                        }
                    },
                    refreshErrorMessage = marksRefreshError,
                    isRefreshing = isDashboardLoading,
                    onRefresh = {
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    refreshSignedInData(forceRefresh = true)
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onOpenAccount = {
                        signedInNavController.navigateToMainDestination(MainDestination.ACCOUNT)
                    },
                    onOpenGradeyTools = {
                        signedInNavController.navigateToMainDestination(MainDestination.GRADEY_AI)
                    },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = context.getString(R.string.tab_marks),
                    isLoading = isDashboardLoading,
                    errorMessage = dataError,
                    onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                    modifier = standardScreenModifier,
                    )
                },
                absenceContent = {
                    when (absencePresentationState) {
                    AbsencePresentationState.INITIAL_LOADING,
                    AbsencePresentationState.FIRST_LOAD_ERROR,
                    -> AbsenceStateScreen(
                        state = absencePresentationState,
                        errorMessage = absenceRefreshError,
                        onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                        modifier = standardScreenModifier,
                    )

                    else -> if (currentAbsence != null) {
                        AbsenceScreen(
                            response = currentAbsence,
                            studentName = currentDashboard?.user?.fullName
                                ?: context.getString(R.string.student_fallback),
                            isRefreshing = absencePresentationState == AbsencePresentationState.REFRESHING,
                            isResolvingSubjects = isResolvingAbsenceSubjects,
                            subjectResolutionProgress = absenceSubjectProgress,
                            subjectResolutionWarning = absenceSubjectWarning,
                            subjectResolutionError = absenceSubjectError,
                            unresolvedPartialDays = absencePartialDays,
                            onRefresh = {
                                if (!isLoading) {
                                    scope.launch {
                                        isLoading = true
                                        try {
                                            refreshSignedInData(forceRefresh = true)
                                        } finally {
                                            isLoading = false
                                        }
                                    }
                                }
                            },
                            onRetrySubjectResolution = {
                                absenceSourceResponse?.let(::startAbsenceSubjectResolution)
                            },
                            onSaveManualSelections = ::saveManualAbsenceSelections,
                            predictorScopeKey = "$currentSchoolBaseURL:${activeLinkedAccountID.orEmpty()}",
                            onLoadPredictionLessons = { date ->
                                withSchoolSessionRecovery {
                                    graph.schoolRepository.loadAbsencePredictionLessons(date)
                                }
                            },
                            onOpenAccount = {
                                signedInNavController.navigateToMainDestination(MainDestination.ACCOUNT)
                            },
                            onOpenGradeyTools = {
                                signedInNavController.navigateToMainDestination(MainDestination.GRADEY_AI)
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        AbsenceStateScreen(
                            state = AbsencePresentationState.FIRST_LOAD_ERROR,
                            errorMessage = absenceRefreshError,
                            onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                            modifier = standardScreenModifier,
                        )
                    }
                    }
                },
                timetableContent = {
                    if (timetable != null) TimetableScreen(
                    week = timetable,
                    isRefreshing = isLoading,
                    errorMessage = timetableError,
                    onRefresh = {
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    timetableError = null
                                    timetableError = loadTimetable(timetable?.weekStart ?: timetableRequestedWeek)?.userFacingMessage(context)
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onChangeWeek = { weekContaining ->
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    timetableError = null
                                    timetableError = loadTimetableCacheFirst(weekContaining)?.userFacingMessage(context)
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onOpenAccount = {
                        signedInNavController.navigateToMainDestination(MainDestination.ACCOUNT)
                    },
                    onOpenGradeyTools = {
                        signedInNavController.navigateToMainDestination(MainDestination.GRADEY_AI)
                    },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = context.getString(TimetableR.string.timetable_title),
                    isLoading = isLoading,
                    errorMessage = timetableError,
                    onRetry = {
                        scope.launch {
                            runWithLoading {
                                timetableError = null
                                timetableError = loadTimetableCacheFirst(timetableRequestedWeek)?.userFacingMessage(context)
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                    )
                },
                mealsContent = {
                    StravaCZScreen(
                    session = stravaSession,
                    menu = stravaMenu,
                    isLoading = isStravaLoading,
                    isRefreshing = isStravaRefreshing,
                    submittingMealID = submittingStravaMealID,
                    errorMessage = stravaError,
                    onConnect = { canteenNumber, username, password ->
                        scope.launch { connectStravaCZ(canteenNumber, username, password) }
                    },
                    onRefresh = { scope.launch { refreshStravaCZ() } },
                    onSetMeal = { meal, ordered ->
                        scope.launch { setStravaCZMeal(meal, ordered) }
                    },
                    onDisconnect = { scope.launch { disconnectStravaCZ() } },
                    onOpenAccount = {
                        signedInNavController.navigateToMainDestination(MainDestination.ACCOUNT)
                    },
                    onOpenGradeyTools = {
                        signedInNavController.navigateToMainDestination(MainDestination.GRADEY_AI)
                    },
                    modifier = Modifier.fillMaxSize(),
                    )
                },
                supportContent = {
                    SupportScreen(
                        catalog = supportCatalog,
                        isSignedIn = account != null && !isGuestMode,
                        isConfigured = supportService.isConfigured,
                        isLoading = isSupportLoading,
                        purchasingOptionID = purchasingSupportOptionID,
                        isRestoring = isRestoringSupport,
                        message = supportMessage,
                        appVersion = BuildConfig.VERSION_NAME,
                        appBuild = BuildConfig.VERSION_CODE.toString(),
                        onBack = { signedInNavController.popBackStack() },
                        onReload = { scope.launch { loadSupportCatalog() } },
                        onPurchasePlan = { plan: SupportPlanOption ->
                            scope.launch {
                                purchaseSupportOption(
                                    plan.id,
                                    requiresGradeyID = true,
                                    requestedPlan = plan,
                                )
                            }
                        },
                        onPurchaseTip = { optionID ->
                            scope.launch { purchaseSupportOption(optionID, requiresGradeyID = false) }
                        },
                        onRestore = { scope.launch { restoreSupportPurchases() } },
                        onManageSubscription = {
                            val url = supportCatalog?.managementURL
                                ?: "https://play.google.com/store/account/subscriptions?package=${activity.packageName}"
                            runCatching {
                                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            }
                        },
                        onOpenHelpCenter = {
                            val language = helpCenterLanguageCode(activeLanguageCode)
                            runCatching {
                                activity.startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://help.bukovinafilip.com/$language"),
                                    ),
                                )
                            }
                        },
                        onEmailDeveloper = {
                            runCatching {
                                activity.startActivity(
                                    Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:filip@openside.tech")),
                                )
                            }
                        },
                        onOpenGitHub = {
                            runCatching {
                                activity.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/FBukovina/Gradely")),
                                )
                            }
                        },
                        onOpenPrivacyPolicy = {
                            runCatching {
                                activity.startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse(privacyPolicyUrl(activeLanguageCode)),
                                    ),
                                )
                            }
                        },
                        onOpenTermsOfUse = {
                            val language = helpCenterLanguageCode(activeLanguageCode)
                            runCatching {
                                activity.startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://help.bukovinafilip.com/$language/articles/11-terms-and-conditions"),
                                    ),
                                )
                            }
                        },
                        onOpenOpenSide = {
                            runCatching {
                                activity.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse("https://openside.tech")),
                                )
                            }
                        },
                        onEmailGraphics = {
                            runCatching {
                                activity.startActivity(
                                    Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:tom@openside.tech")),
                                )
                            }
                        },
                        onOpenDeveloperInstagram = {
                            runCatching {
                                activity.startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://www.instagram.com/bukovinafilip"),
                                    ),
                                )
                            }
                        },
                        onClearCache = {
                            scope.launch {
                                val retainedSchoolScope = graph.schoolRepository
                                    .currentStoredSession()
                                    ?.cacheScope
                                graph.cache?.clearAll()
                                dashboardViewModel.clear(scopeKey = retainedSchoolScope)
                                absence = null
                                resetAbsenceSubjectResolution()
                                resetTimetableState()
                                gradeHistorySnapshot = null
                                stravaMenu = null
                                try {
                                    updateNextLessonWidgets(context.applicationContext)
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (_: Throwable) {
                                    // Cache clearing is complete even if a widget host cannot refresh.
                                }
                                supportMessage = context.getString(
                                    com.bukovinafilip.gradey.feature.account.R.string.support_cache_cleared,
                                )
                            }
                        },
                        onRestartOnboarding = {
                            scope.launch {
                                val journey = if (graph.schoolRepository.currentStoredSession() == null) {
                                    OnboardingJourney.NEW_USER
                                } else {
                                    OnboardingJourney.UPGRADE
                                }
                                val restarted = OnboardingProgress.initial(journey)
                                graph.onboardingProgressStore.restart(restarted)
                                clearOnboardingNotificationRecovery()
                                signedInNavController.popBackStack()
                                onboardingProgress = restarted
                            }
                        },
                        gradeyAccountID = account?.id,
                        revenueCatAppUserID = supportService.diagnosticAppUserID,
                        revenueCatOriginalAppUserID = supportService.diagnosticOriginalAppUserID,
                        linkedSchoolAccountID = activeLinkedAccountID,
                        isGuestMode = isGuestMode,
                        hasCompletedOnboardingV2 = graph.onboardingProgressStore.isCompleted,
                        onboardingProgress = graph.onboardingProgressStore.loadProgress()?.let { progress ->
                            "${progress.journey.name}/${progress.step.name}"
                        },
                        onDebugRestartNewUser = {
                            val restarted = OnboardingProgress.initial(OnboardingJourney.NEW_USER)
                            graph.onboardingProgressStore.restart(restarted)
                            clearOnboardingNotificationRecovery()
                            signedInNavController.popBackStack()
                            onboardingProgress = restarted
                        },
                        onDebugRestartUpgrade = {
                            val restarted = OnboardingProgress.initial(OnboardingJourney.UPGRADE)
                            graph.onboardingProgressStore.restart(restarted)
                            clearOnboardingNotificationRecovery()
                            signedInNavController.popBackStack()
                            onboardingProgress = restarted
                        },
                        onDebugResetAsNewUser = {
                            scope.launch {
                                try {
                                    signOutAllGradeyState()
                                    graph.cache?.clearAll()
                                    val restarted = OnboardingProgress.initial(OnboardingJourney.NEW_USER)
                                    graph.onboardingProgressStore.restart(restarted)
                                    clearOnboardingNotificationRecovery()
                                    resetSignedInNavigation()
                                    onboardingProgress = restarted
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (error: Throwable) {
                                    supportMessage = error.userFacingMessage(context)
                                }
                            }
                        },
                        onDebugSignOut = {
                            scope.launch {
                                try {
                                    signOutAllGradeyState()
                                    resetSignedInNavigation()
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (error: Throwable) {
                                    supportMessage = error.userFacingMessage(context)
                                }
                            }
                        },
                        modifier = standardScreenModifier,
                    )
                },
                accountContent = {
                    AccountScreen(
                    account = account,
                    linkedAccounts = linkedAccounts,
                    selectedDestination = accountSettingsDestination,
                    hasBakalariConnectionOnDevice = currentSchoolBaseURL.isNotBlank(),
                    appLanguage = appLanguage,
                    activeLinkedAccountID = activeLinkedAccountID,
                    ageAttestationKind = ageAttestationKind,
                    isGuestMode = isGuestMode,
                    isGradeyIdAvailable = graph.isGradeyCloudConfigured,
                    isUpdatingFullName = isUpdatingProfile,
                    profileErrorMessage = profileError,
                    linkedAccountErrorMessage = linkedAccountError,
                    isRefreshingLinkedAccounts = isRefreshingLinkedAccounts,
                    mutatingLinkedAccountID = mutatingLinkedAccountID,
                    showMealsTab = showMealsTab,
                    isStravaConnectedOnDevice = stravaSession != null,
                    isRetryingStravaCloudLink = isRetryingStravaCloudLink,
                    notificationPreferences = notificationPreferences,
                    notificationPermissionGranted = notificationPermissionGranted,
                    isUpdatingNotificationPreferences = isUpdatingNotificationPreferences,
                    notificationPreferencesErrorMessage = notificationPreferencesError,
                    isExportingData = isExportingData,
                    isDeletingAccount = isDeletingAccount,
                    privacyDataErrorMessage = privacyDataError,
                    onUpdateFullName = { fullName ->
                        scope.launch {
                            val updateOwner = currentGradeyIdentityOwner() ?: return@launch
                            isUpdatingProfile = true
                            profileError = null
                            try {
                                val updatedAccount = graph.gradeyAuthRepository.updateFullName(fullName)
                                updateOwner.requireCurrent()
                                account = updatedAccount
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: GradeySessionExpiredException) {
                                if (updateOwner.isCurrent()) {
                                    expireGradeyIdentity(error)
                                    resetSignedInNavigation()
                                }
                            } catch (error: Throwable) {
                                if (updateOwner.isCurrent()) {
                                    profileError = error.userFacingMessage(context)
                                }
                            } finally {
                                if (updateOwner.isCurrent()) isUpdatingProfile = false
                            }
                        }
                    },
                    onSelectedDestinationChange = { accountSettingsDestination = it },
                    onConnectGradeyId = {
                        graph.guestModeStore.isEnabled = false
                        isGuestMode = false
                        account = null
                        authError = null
                        profileError = null
                        resetSignedInNavigation()
                        phase = AppPhase.SIGNED_OUT
                    },
                    onRefreshLinkedAccounts = {
                        scope.launch { refreshLinkedAccountSnapshot() }
                    },
                    onAddSchool = {
                        isAddingSchool = true
                        reconnectLinkedAccount = null
                        reconnectLinkedAccountID = null
                        applyReconnectPrefill(null)
                        schoolLoginError = null
                        phase = AppPhase.NEEDS_SCHOOL
                    },
                    onActivateLinkedAccount = { linked ->
                        scope.launch {
                            if (activateLinkedAccount(linked)) refreshSignedInData()
                        }
                    },
                    onReconnectLinkedAccount = { linked ->
                        scope.launch {
                            isAddingSchool = false
                            reconnectLinkedAccount = linked
                            reconnectLinkedAccountID = linked.id
                            applyReconnectPrefill(reconnectPrefillFor(linked))
                            schoolLoginError = null
                            phase = AppPhase.NEEDS_SCHOOL
                        }
                    },
                    onToggleLinkedNotifications = { linked, enabled ->
                        scope.launch { updateLinkedAccountNotifications(linked, enabled) }
                    },
                    onOpenNotificationSettings = {
                        currentOnboardingIdentityOwner()?.let { notificationOwner ->
                            notificationSettingsRequestOwner = notificationOwner
                            notificationSettingsLauncher.launch(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                                    Settings.EXTRA_APP_PACKAGE,
                                    context.packageName,
                                ),
                            )
                        }
                    },
                    onUpdateNotificationPreferences = { preferences ->
                        scope.launch { updateNotificationPreferences(preferences) }
                    },
                    onOpenMeals = {
                        if (!showMealsTab) {
                            graph.mealsTabPreferenceStore.isVisible = true
                            showMealsTab = true
                        }
                        signedInNavController.navigateToMainDestination(MainDestination.MEALS)
                    },
                    onRetryStravaCloudLink = {
                        scope.launch { retryStravaCloudLink() }
                    },
                    onOpenPrivacyPolicy = {
                        runCatching {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse(privacyPolicyUrl(activeLanguageCode)),
                                ),
                            )
                        }
                    },
                    onOpenTermsOfUse = {
                        val language = helpCenterLanguageCode(activeLanguageCode)
                        runCatching {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://help.bukovinafilip.com/$language/articles/11-terms-and-conditions"),
                                ),
                            )
                        }
                    },
                    onExportData = {
                        scope.launch { exportGradeyData() }
                    },
                    onDeleteAccount = {
                        scope.launch { deleteGradeyAccount() }
                    },
                    onOpenSupport = {
                        supportMessage = null
                        signedInNavController.navigateToMainDestination(MainDestination.SUPPORT)
                    },
                    onUnlinkLinkedAccount = { linked ->
                        scope.launch { unlinkLinkedAccount(linked) }
                    },
                    onAppLanguageChange = onAppLanguageChange,
                    onShowMealsTabChange = { visible ->
                        graph.mealsTabPreferenceStore.isVisible = visible
                        showMealsTab = visible
                        val presentingDestination = MainDestination.fromRoute(
                            signedInNavController.previousBackStackEntry?.destination?.route,
                        )
                        if (!visible && presentingDestination == MainDestination.MEALS) {
                            resetSignedInNavigation()
                        }
                    },
                    onSignOut = {
                        scope.launch {
                            try {
                                if (isGuestMode || !graph.isGradeyCloudConfigured) {
                                    disconnectSchool()
                                    phase = AppPhase.NEEDS_SCHOOL
                                    return@launch
                                }

                                signOutAllGradeyState()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                profileError = error.userFacingMessage(context)
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                )
                },
                gradeyAiContent = {
                    GradeyAIScreen(
                        repository = graph.gradeyAIRepository,
                        contextBuilder = graph.gradeyAIContextBuilder,
                        isGradeyCloudConfigured = graph.isGradeyCloudConfigured,
                        hasGradeyAccount = account != null,
                        isGuestMode = isGuestMode,
                        supportTier = supportTier,
                        onOpenAccount = {
                            signedInNavController.navigateFromGradeyAiToAccount()
                        },
                        onOpenSupport = {
                            supportMessage = null
                            signedInNavController.navigateFromGradeyAiToSupport()
                        },
                        onClose = { signedInNavController.popBackStack() },
                        modifier = Modifier.fillMaxSize(),
                    )
                },
            )

            val selectedDestinationHasUsableContent = when (currentMainDestination) {
                MainDestination.TODAY, MainDestination.SUBJECTS -> currentDashboard != null
                MainDestination.ABSENCE -> currentAbsence != null
                MainDestination.TIMETABLE -> timetable != null
                MainDestination.MEALS -> stravaMenu != null
                MainDestination.ACCOUNT,
                MainDestination.SUPPORT,
                MainDestination.GRADEY_AI,
                -> false
            }
            val selectedDestinationRefreshError = when (currentMainDestination) {
                MainDestination.ABSENCE -> absenceRefreshError
                MainDestination.MEALS,
                MainDestination.ACCOUNT,
                MainDestination.SUPPORT,
                MainDestination.GRADEY_AI,
                -> null
                MainDestination.TODAY, MainDestination.SUBJECTS ->
                    dataError ?: gradeHistoryRefreshError
                MainDestination.TIMETABLE -> dataError
            }
            if (
                currentMainDestination.isPrimary &&
                selectedDestinationRefreshError != null &&
                selectedDestinationHasUsableContent
            ) {
                DataRefreshWarning(
                    message = selectedDestinationRefreshError.orEmpty(),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(start = 16.dp, end = 16.dp, bottom = 88.dp),
                )
            }

            if (currentMainDestination.isPrimary) {
                GradeyBottomNavigation(
                    selectedDestination = currentMainDestination,
                    showMealsTab = showMealsTab,
                    onSelect = { destination ->
                        signedInNavController.navigateToMainDestination(destination)
                        dataError = null
                    },
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }
        }
    }
}

internal fun helpCenterLanguageCode(languageCode: String?): String =
    if (languageCode.equals("cs", ignoreCase = true)) "cs" else "en"

internal fun privacyPolicyUrl(languageCode: String?): String =
    "https://help.bukovinafilip.com/${helpCenterLanguageCode(languageCode)}/articles/10-privacy-policy"

private suspend fun requestGoogleCredential(
    context: android.content.Context,
    serverClientId: String,
): GoogleIdTokenCredential {
    if (serverClientId.isBlank()) {
        throw AppAuthException(AppAuthError.GOOGLE_NOT_CONFIGURED)
    }
    val option = GetSignInWithGoogleOption.Builder(serverClientId).build()
    val request = GetCredentialRequest.Builder()
        .addCredentialOption(option)
        .build()
    val credential = CredentialManager.create(context).getCredential(context, request).credential
    if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
        throw AppAuthException(AppAuthError.GOOGLE_UNSUPPORTED_CREDENTIAL)
    }
    return GoogleIdTokenCredential.createFrom(credential.data)
}

@Composable
private fun DataRefreshWarning(message: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.errorContainer,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = GradeyIcons.ErrorCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(20.dp),
            )
            Column {
                Text(
                    text = stringResource(R.string.data_refresh_partial),
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    fontSize = 12.sp,
                )
            }
        }
    }
}

@Composable
private fun CoreDataUnavailableScreen(
    title: String,
    isLoading: Boolean,
    errorMessage: String?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier) {
        GradeyHero(title = title, subtitle = stringResource(R.string.core_data_subtitle))
        GradeySectionCard {
            if (isLoading) {
                CircularProgressIndicator()
                Text(stringResource(R.string.core_data_loading))
            } else {
                Text(
                    errorMessage ?: stringResource(R.string.core_data_empty),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = onRetry) {
                    Text(stringResource(R.string.action_try_again))
                }
            }
        }
    }
}

private val MarksTabs = MainDestination.primaryDestinations

@Composable
private fun MainDestination.icon() = when (this) {
    MainDestination.TODAY -> GradeyIcons.Sun
    MainDestination.SUBJECTS -> GradeyIcons.CheckmarkBadge
    MainDestination.ABSENCE -> GradeyIcons.Calendar
    MainDestination.TIMETABLE -> GradeyIcons.Calendar
    MainDestination.MEALS -> GradeyIcons.Restaurant
    MainDestination.ACCOUNT,
    MainDestination.SUPPORT,
    MainDestination.GRADEY_AI,
    -> GradeyIcons.User
}

private fun MainDestination.labelResource(): Int = when (this) {
    MainDestination.TODAY -> R.string.tab_today
    MainDestination.SUBJECTS -> R.string.tab_marks
    MainDestination.ABSENCE -> R.string.tab_absence
    MainDestination.TIMETABLE -> R.string.tab_timetable
    MainDestination.MEALS -> R.string.tab_meals
    MainDestination.ACCOUNT -> R.string.tab_account
    MainDestination.SUPPORT, MainDestination.GRADEY_AI -> error("Not a bottom destination")
}

@Composable
private fun GradeyBottomNavigation(
    selectedDestination: MainDestination,
    showMealsTab: Boolean,
    onSelect: (MainDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val visibleTabs = MarksTabs.filter { showMealsTab || it != MainDestination.MEALS }
    Box(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 21.dp),
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(62.dp),
            shape = RoundedCornerShape(31.dp),
            color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.96f),
            shadowElevation = 8.dp,
        ) {
            Row(
                modifier = Modifier.padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                visibleTabs.forEach { tab ->
                    BottomNavigationItem(
                        tab = tab,
                        selected = selectedDestination == tab,
                        onClick = { onSelect(tab) },
                    )
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.BottomNavigationItem(
    tab: MainDestination,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val label = stringResource(tab.labelResource())
    val foreground = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        selected = selected,
        onClick = onClick,
        modifier = Modifier
            .weight(1f)
            .height(54.dp)
            .semantics { role = Role.Tab },
        shape = RoundedCornerShape(27.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.surfaceVariant
        } else {
            MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0f)
        },
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                modifier = Modifier.size(26.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = tab.icon(),
                    contentDescription = null,
                    tint = foreground,
                    modifier = Modifier.size(24.dp),
                )
                if (tab == MainDestination.ABSENCE) {
                    Icon(
                        imageVector = GradeyIcons.ErrorCircle,
                        contentDescription = null,
                        tint = foreground,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(11.dp),
                    )
                }
            }
            Text(
                text = label,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                fontSize = 12.sp,
                lineHeight = 14.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                maxLines = 1,
            )
        }
    }
}
