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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Verified
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bukovinafilip.gradey.feature.absence.AbsenceScreen
import com.bukovinafilip.gradey.feature.absence.AbsenceStateScreen
import com.bukovinafilip.gradey.feature.absence.R as AbsenceR
import com.bukovinafilip.gradey.feature.account.AccountScreen
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
import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeyStartupDestination
import com.bukovinafilip.gradey.domain.AbsencePresentationState
import com.bukovinafilip.gradey.domain.AbsencePresentationStates
import com.bukovinafilip.gradey.domain.AbsencePartialDayCandidate
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionFailure
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionProgress
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.domain.TodayPresentationStates
import com.bukovinafilip.gradey.domain.WearPayloadBuilder
import com.bukovinafilip.gradey.domain.refreshRetainingContent
import com.bukovinafilip.gradey.domain.reconcileOnboardingProgress
import com.bukovinafilip.gradey.domain.selectGradeyStartupDestination
import com.bukovinafilip.gradey.domain.selectRestorableSchoolAccount
import com.bukovinafilip.gradey.domain.selectSchoolAccountRequiringReconnect
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.push.GradeyPushRegistration
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
import java.time.ZoneId

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
                        appLanguage = appLanguage,
                        onAppLanguageChange = { selection ->
                            graph.appLanguageStore.selection = selection
                            appLanguage = selection
                        },
                        initialTab = gradeyDeepLinkDestination(intent?.dataString).toAppTab() ?: AppTab.TODAY,
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
        deepLinkRequests.value = DeepLinkRequest(deepLinkSequence, intent?.dataString)
    }
}

private enum class AppPhase {
    CHECKING,
    SIGNED_OUT,
    NEEDS_SCHOOL,
    SIGNED_IN,
}

private enum class AppTab(val label: String) {
    TODAY("Today"),
    SUBJECTS("Marks"),
    ABSENCE("Absence"),
    TIMETABLE("Timetable"),
    STRAVACZ("Meals"),
    ACCOUNT("Account"),
}

private fun DeepLinkDestination?.toAppTab(): AppTab? = when (this) {
    DeepLinkDestination.SUBJECTS -> AppTab.SUBJECTS
    DeepLinkDestination.TIMETABLE -> AppTab.TIMETABLE
    null -> null
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
    appLanguage: AppLanguage,
    onAppLanguageChange: (AppLanguage) -> Unit,
    initialTab: AppTab,
    deepLinkRequest: DeepLinkRequest,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf(AppPhase.CHECKING) }
    var selectedTab by rememberSaveable { mutableStateOf(initialTab) }
    var isGradeyAIPresented by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(false) }
    var authError by remember { mutableStateOf<String?>(null) }
    var schoolLoginError by remember { mutableStateOf<String?>(null) }
    var schoolDirectoryError by remember { mutableStateOf<String?>(null) }
    var dataError by remember { mutableStateOf<String?>(null) }
    var marksRefreshError by remember { mutableStateOf<String?>(null) }
    var absenceRefreshError by remember { mutableStateOf<String?>(null) }
    var profileError by remember { mutableStateOf<String?>(null) }
    var isUpdatingProfile by remember { mutableStateOf(false) }
    var ageAttestationKind by remember { mutableStateOf(graph.ageAttestationStore.kind) }
    var isGuestMode by remember { mutableStateOf(graph.guestModeStore.isEnabled) }
    var onboardingProgress by remember { mutableStateOf<OnboardingProgress?>(null) }
    var account by remember { mutableStateOf<GradeyAccount?>(null) }
    var linkedAccounts by remember { mutableStateOf<List<LinkedSchoolAccount>>(emptyList()) }
    var activeLinkedAccountID by remember { mutableStateOf<String?>(null) }
    var currentSchoolBaseURL by remember { mutableStateOf("") }
    var reconnectLinkedAccount by remember { mutableStateOf<LinkedSchoolAccount?>(null) }
    var reconnectSchoolURL by remember { mutableStateOf("") }
    var isAddingSchool by remember { mutableStateOf(false) }
    var linkedAccountError by remember { mutableStateOf<String?>(null) }
    var isRefreshingLinkedAccounts by remember { mutableStateOf(false) }
    var mutatingLinkedAccountID by remember { mutableStateOf<String?>(null) }
    var schoolLoginJob by remember { mutableStateOf<Job?>(null) }
    var schoolLoginAttempt by remember { mutableIntStateOf(0) }
    var directorySchools by remember { mutableStateOf<List<SchoolDirectorySchool>>(emptyList()) }
    var isSchoolDirectoryLoading by remember { mutableStateOf(false) }
    var hasLoadedSchoolDirectory by remember { mutableStateOf(false) }
    var dashboard by remember { mutableStateOf<DashboardData?>(null) }
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
    var notificationPermissionGranted by remember {
        mutableStateOf(context.notificationsAreEnabled())
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        notificationPermissionGranted = granted || context.notificationsAreEnabled()
        if (notificationPermissionGranted) {
            scope.launch { GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph) }
        }
        onboardingProgress?.let { current ->
            val ready = current.copy(step = OnboardingStep.READY)
            graph.onboardingProgressStore.saveProgress(ready)
            onboardingProgress = ready
        }
    }
    val notificationSettingsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        notificationPermissionGranted = context.notificationsAreEnabled()
        if (notificationPermissionGranted) {
            scope.launch { GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph) }
        }
    }

    LaunchedEffect(deepLinkRequest.sequence) {
        gradeyDeepLinkDestination(deepLinkRequest.rawUri).toAppTab()?.let { destination ->
            selectedTab = destination
            isGradeyAIPresented = false
        }
    }

    LaunchedEffect(account?.id, notificationPermissionGranted) {
        if (account != null && notificationPermissionGranted) {
            GradeyPushRegistration.refreshIfEligible(context.applicationContext, graph)
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
                schoolLoginError = error.userFacingMessage()
            } finally {
                if (attempt == schoolLoginAttempt) {
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
            } catch (error: Throwable) {
                if (attempt == absenceSubjectResolutionAttempt) {
                    absenceSubjectError = error.userFacingMessage()
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
    } catch (error: Throwable) {
        error.userFacingMessage()
    }

    suspend fun loadCachedSignedInData() {
        val storedSession = graph.schoolRepository.currentStoredSession()
        activeLinkedAccountID = storedSession?.linkedAccountID
        currentSchoolBaseURL = storedSession?.baseURL.orEmpty()
        graph.schoolRepository.loadCachedDashboard()?.let { dashboard = it }
        graph.schoolRepository.loadCachedAbsence()?.let(::startAbsenceSubjectResolution)
        graph.schoolRepository.loadCachedTimetable(TimetableDates.todayString())?.let {
            timetable = it
            timetableRequestedWeek = it.weekStart
        }
        stravaSession = runCatching { graph.stravaCZRepository.bootstrapSession() }.getOrNull()
        graph.stravaCZRepository.loadCachedMenu()?.let { stravaMenu = it }
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }.getOrDefault(emptyList())
        val linkedAccountID = storedSession?.linkedAccountID
        if (account != null && !isGuestMode && graph.isGradeyCloudConfigured && linkedAccountID != null) {
            graph.historyRepository.loadCachedGradeHistory(linkedAccountID)?.let { history ->
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
        return try {
            // Re-link even when a cached record exists so the cloud receives the current
            // Strava session from this device, matching the iOS reconnect contract.
            graph.linkedAccountRepository.linkStravaCZAccount(session)
            linkedAccounts = graph.linkedAccountRepository.localAccounts()
            linkedAccountError = null
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            // The local meals connection remains usable if optional cloud linking fails.
            linkedAccountError = error.userFacingMessage()
            false
        }
    }

    suspend fun retryStravaCloudLink() {
        val session = stravaSession ?: return
        if (isRetryingStravaCloudLink) return
        isRetryingStravaCloudLink = true
        try {
            linkCurrentStravaAccountIfNeeded(session)
        } finally {
            isRetryingStravaCloudLink = false
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
            stravaError = error.userFacingMessage()
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
            stravaError = error.userFacingMessage()
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
            stravaError = error.userFacingMessage()
            graph.stravaCZRepository.loadCachedMenu()?.let { stravaMenu = it }
            if (graph.stravaCZRepository.bootstrapSession() == null) {
                stravaSession = null
                stravaMenu = null
            }
        } finally {
            submittingStravaMealID = null
        }
    }

    suspend fun disconnectStravaCZ() {
        val mealAccounts = linkedAccounts.filter { it.provider == LinkedAccountProvider.STRAVA_CZ }
        mealAccounts.forEach { linked ->
            try {
                graph.linkedAccountRepository.unlinkAccount(linked.id)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Local disconnect remains authoritative if optional cloud unlink fails.
            }
        }
        graph.stravaCZRepository.logout()
        stravaSession = null
        stravaMenu = null
        stravaError = null
        submittingStravaMealID = null
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }.getOrDefault(
            linkedAccounts.filterNot { it.provider == LinkedAccountProvider.STRAVA_CZ },
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
                schoolDirectoryError =
                    "We couldn't load the Bakaláři school directory. You can still enter the school URL manually."
            }
        } finally {
            isSchoolDirectoryLoading = false
        }
    }

    suspend fun applyFreshTimetable(loaded: TimetableWeek) {
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
        try {
            PhoneWearSyncPublisher.publish(
                context.applicationContext,
                WearPayloadBuilder.signedIn(loaded, dashboard?.user),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // A missing/unpaired watch must not hide a successful timetable refresh.
        }
    }

    suspend fun loadTimetable(weekContaining: String): Throwable? = try {
        timetableRequestedWeek = TimetableDates.apiDateString(
            TimetableDates.monday(TimetableDates.parseApiDate(weekContaining) ?: TimetableDates.today()),
        )
        applyFreshTimetable(graph.schoolRepository.loadTimetable(weekContaining))
        null
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        error
    }

    suspend fun loadTimetableCacheFirst(weekContaining: String): Throwable? {
        val requested = TimetableDates.apiDateString(
            TimetableDates.monday(TimetableDates.parseApiDate(weekContaining) ?: TimetableDates.today()),
        )
        timetableRequestedWeek = requested
        timetableError = null
        return try {
            timetable = graph.schoolRepository.loadCachedTimetable(requested)
            applyFreshTimetable(graph.schoolRepository.loadTimetable(requested))
            null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            error
        }
    }

    fun routeToSchoolReconnect() {
        dashboard = null
        absence = null
        resetAbsenceSubjectResolution()
        resetTimetableState()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        activeLinkedAccountID = null
        currentSchoolBaseURL = ""
        reconnectLinkedAccount = null
        selectedTab = AppTab.TODAY
        isGradeyAIPresented = false
        dataError = null
        marksRefreshError = null
        absenceRefreshError = null
        schoolLoginError = "Your Bakaláři session expired. Please reconnect your school account."
        phase = AppPhase.NEEDS_SCHOOL
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
        dashboard = null
        absence = null
        resetAbsenceSubjectResolution()
        resetTimetableState()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        activeLinkedAccountID = null
        currentSchoolBaseURL = ""
        reconnectLinkedAccount = null
        selectedTab = AppTab.TODAY
        isGradeyAIPresented = false
        dataError = null
        marksRefreshError = null
        absenceRefreshError = null
        schoolLoginError = null
    }

    suspend fun clearLinkedAccountsForLocalMode() {
        try {
            graph.linkedAccountRepository.clearLocalAccounts()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // A damaged optional linked-account snapshot must not block local Bakaláři use.
        }
        linkedAccounts = emptyList()
        gradeHistorySnapshot = null
        gradeHistoryRefreshError = null
        activeLinkedAccountID = null
    }

    suspend fun refreshLinkedAccountSnapshot() {
        linkedAccounts = refreshRetainingContent(linkedAccounts) {
            graph.linkedAccountRepository.localAccounts()
        }.value
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) return

        isRefreshingLinkedAccounts = true
        linkedAccountError = null
        try {
            val snapshot = graph.linkedAccountRepository.refreshAccounts()
            linkedAccounts = snapshot.linkedAccounts
            notificationPreferences = snapshot.notificationPreferences
            graph.notificationPreferencesStore.preferences = snapshot.notificationPreferences
            notificationPreferencesError = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            account = null
            authError = error.userFacingMessage()
            phase = AppPhase.SIGNED_OUT
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
        } finally {
            isRefreshingLinkedAccounts = false
        }
    }

    suspend fun updateNotificationPreferences(updated: NotificationPreferences) {
        if (
            account == null ||
            isGuestMode ||
            !graph.isGradeyCloudConfigured ||
            isUpdatingNotificationPreferences
        ) return

        val previous = notificationPreferences
        val prepared = updated.copy(
            quietHoursStartMinute = updated.quietHoursStartMinute.coerceIn(0, 1439),
            quietHoursEndMinute = updated.quietHoursEndMinute.coerceIn(0, 1439),
            quietHoursTimeZone = ZoneId.systemDefault().id,
        )
        notificationPreferences = prepared
        graph.notificationPreferencesStore.preferences = prepared
        notificationPreferencesError = null
        isUpdatingNotificationPreferences = true
        try {
            val session = graph.gradeyAuthRepository.validSession()
            graph.devicePushTokenClient.updateNotificationPreferences(prepared, session)
        } catch (error: CancellationException) {
            notificationPreferences = previous
            graph.notificationPreferencesStore.preferences = previous
            throw error
        } catch (error: GradeySessionExpiredException) {
            notificationPreferences = previous
            graph.notificationPreferencesStore.preferences = previous
            graph.pushRegistrationStore.clear()
            account = null
            authError = error.userFacingMessage()
            phase = AppPhase.SIGNED_OUT
        } catch (error: Throwable) {
            notificationPreferences = previous
            graph.notificationPreferencesStore.preferences = previous
            notificationPreferencesError = error.userFacingMessage()
        } finally {
            isUpdatingNotificationPreferences = false
        }
    }

    suspend fun refreshGradeHistory() {
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) {
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
            return
        }
        val linkedAccountID = graph.schoolRepository.currentStoredSession()?.linkedAccountID
        if (gradeHistorySnapshot?.linkedAccountID != linkedAccountID) {
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
        }
        val refresh = refreshRetainingContent(gradeHistorySnapshot) {
            val response = graph.historyRepository.gradeHistory(linkedAccountID, days = 400)
            GradeHistorySnapshot(
                linkedAccountID = linkedAccountID,
                trends = GradeHistoryTrends.make(response.events),
                recentNewMarkEvents = response.recentNewMarkEvents,
            )
        }
        gradeHistorySnapshot = refresh.value
        gradeHistoryRefreshError = refresh.failure?.userFacingMessage()
    }

    suspend fun linkCurrentSchoolIfNeeded(): Boolean {
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) return true
        val session = graph.schoolRepository.currentStoredSession() ?: return false
        val cachedAccounts = graph.linkedAccountRepository.localAccounts()
        if (session.linkedAccountID != null && cachedAccounts.any { it.id == session.linkedAccountID }) {
            activeLinkedAccountID = session.linkedAccountID
            linkedAccounts = cachedAccounts
            linkedAccountError = null
            return true
        }

        return try {
            val linked = graph.linkedAccountRepository.linkSchoolAccount(session, dashboard?.user)
            graph.schoolRepository.associateCurrentSession(linked)
            activeLinkedAccountID = linked.id
            linkedAccounts = graph.linkedAccountRepository.localAccounts()
            linkedAccountError = null
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeySessionExpiredException) {
            account = null
            authError = error.userFacingMessage()
            phase = AppPhase.SIGNED_OUT
            false
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
            false
        }
    }

    suspend fun reconnectLinkedAccountWithCredentials(
        linked: LinkedSchoolAccount,
        schoolURL: String,
        username: String,
        password: String,
    ): String? {
        if (mutatingLinkedAccountID != null) {
            return "Another school account change is already in progress."
        }
        val previousSession = graph.schoolRepository.currentStoredSession()

        suspend fun rollback() {
            withContext(NonCancellable) {
                if (previousSession == null) {
                    graph.schoolRepository.logout()
                } else {
                    graph.schoolRepository.restoreSession(previousSession)
                }
            }
        }

        mutatingLinkedAccountID = linked.id
        linkedAccountError = null
        return try {
            val candidateSession = graph.schoolRepository.login(schoolURL, username, password)
            val candidateDashboard = graph.schoolRepository.loadDashboard(forceRefresh = false)
            val updated = graph.linkedAccountRepository.reconnectSchoolAccount(
                linked.id,
                candidateSession,
                candidateDashboard.user,
            )
            val associatedSession = graph.schoolRepository.associateCurrentSession(updated)
            dashboard = candidateDashboard
            absence = null
            resetAbsenceSubjectResolution()
            absenceRefreshError = null
            resetTimetableState()
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
            activeLinkedAccountID = updated.id
            currentSchoolBaseURL = associatedSession.baseURL
            linkedAccounts = linkedAccounts
                .filterNot { it.id == updated.id }
                .plus(updated)
                .sortedBy { it.displayName.lowercase() }
            reconnectLinkedAccount = null
            reconnectSchoolURL = ""
            linkedAccountError = null
            null
        } catch (error: CancellationException) {
            rollback()
            throw error
        } catch (error: Throwable) {
            rollback()
            error.userFacingMessage().also { linkedAccountError = it }
        } finally {
            mutatingLinkedAccountID = null
        }
    }

    suspend fun activateLinkedAccount(linked: LinkedSchoolAccount): Boolean {
        if (mutatingLinkedAccountID != null) return false
        mutatingLinkedAccountID = linked.id
        linkedAccountError = null
        try {
            val activation = graph.linkedAccountRepository.activateSchoolAccount(linked.id)
            graph.schoolRepository.activateLinkedSchoolAccount(
                activation.tokenPayload.makeStoredSession(activation.account),
            )
            dashboard = null
            marksRefreshError = null
            absence = null
            resetAbsenceSubjectResolution()
            absenceRefreshError = null
            resetTimetableState()
            gradeHistorySnapshot = null
            gradeHistoryRefreshError = null
            activeLinkedAccountID = activation.account.id
            selectedTab = AppTab.TODAY
            isGradeyAIPresented = false
            loadCachedSignedInData()
            return true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
            return false
        } finally {
            mutatingLinkedAccountID = null
        }
    }

    suspend fun updateLinkedAccountNotifications(linked: LinkedSchoolAccount, enabled: Boolean) {
        if (mutatingLinkedAccountID != null) return
        mutatingLinkedAccountID = linked.id
        linkedAccountError = null
        try {
            graph.linkedAccountRepository.updateNotificationsEnabled(linked.id, enabled)
            linkedAccounts = graph.linkedAccountRepository.localAccounts()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
        } finally {
            mutatingLinkedAccountID = null
        }
    }

    suspend fun unlinkLinkedAccount(linked: LinkedSchoolAccount) {
        if (mutatingLinkedAccountID != null) return
        mutatingLinkedAccountID = linked.id
        linkedAccountError = null
        try {
            graph.linkedAccountRepository.unlinkAccount(linked.id)
            if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                graph.stravaCZRepository.logout()
                stravaSession = null
                stravaMenu = null
                stravaError = null
                submittingStravaMealID = null
            } else if (activeLinkedAccountID == linked.id) {
                graph.schoolRepository.disassociateCurrentSession(linked.id)
                graph.historyRepository.clearCachedGradeHistory(linked.id)
                gradeHistorySnapshot = null
                gradeHistoryRefreshError = null
                activeLinkedAccountID = null
            }
            linkedAccounts = graph.linkedAccountRepository.localAccounts()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
        } finally {
            mutatingLinkedAccountID = null
        }
    }

    suspend fun refreshSignedInData(forceRefresh: Boolean = false) {
        dataError = null
        marksRefreshError = null
        absenceRefreshError = null
        timetableError = null
        stravaError = null
        val failures = mutableListOf<Throwable>()
        val dashboardRefresh = refreshRetainingContent(dashboard) {
            graph.schoolRepository.loadDashboard(forceRefresh = forceRefresh)
        }
        dashboard = dashboardRefresh.value
        when (val error = dashboardRefresh.failure) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }

            null -> Unit
            else -> {
                failures += error
                marksRefreshError = error.userFacingMessage()
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
                absenceRefreshError = error.userFacingMessage()
            }
        }
        when (val timetableFailure = loadTimetable(TimetableDates.todayString())) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }
            null -> Unit
            else -> {
                failures += timetableFailure
                timetableError = timetableFailure.userFacingMessage()
            }
        }
        val mealsSessionRefresh = refreshRetainingContent(stravaSession) {
            graph.stravaCZRepository.bootstrapSession()
        }
        stravaSession = mealsSessionRefresh.value
        val mealsSessionFailure = mealsSessionRefresh.failure
        if (mealsSessionFailure != null) {
            stravaError = mealsSessionFailure.userFacingMessage()
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
                stravaError = error.userFacingMessage()
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
        dataError = failures.firstOrNull()?.userFacingMessage()
    }

    suspend fun openStoredSchoolOrLogin() {
        val schoolSession = graph.schoolRepository.bootstrapSession()
        if (schoolSession == null) {
            phase = AppPhase.NEEDS_SCHOOL
            return
        }
        phase = AppPhase.SIGNED_IN
        loadCachedSignedInData()
        refreshSignedInData()
    }

    fun persistOnboarding(progress: OnboardingProgress) {
        graph.onboardingProgressStore.saveProgress(progress)
        onboardingProgress = progress
    }

    suspend fun advanceOnboardingAfterAccountChoice() {
        val current = onboardingProgress ?: return
        val hasSchool = graph.schoolRepository.bootstrapSession() != null
        if (hasSchool && account != null && !isGuestMode) {
            graph.schoolRepository.loadCachedDashboard()?.let { dashboard = it }
            if (dashboard == null) {
                dashboard = runCatching {
                    graph.schoolRepository.loadDashboard(forceRefresh = false)
                }.getOrNull()
            }
            linkCurrentSchoolIfNeeded()
        }
        persistOnboarding(
            reconcileOnboardingProgress(
                progress = current.copy(step = OnboardingStep.ACCOUNT),
                isGuestMode = isGuestMode,
                hasGradeySession = account != null,
                hasSchoolSession = hasSchool,
            ),
        )
    }

    suspend fun advanceOnboardingAfterSchoolConnection() {
        val current = onboardingProgress ?: return
        persistOnboarding(
            reconcileOnboardingProgress(
                progress = current.copy(step = OnboardingStep.SCHOOL),
                isGuestMode = isGuestMode,
                hasGradeySession = account != null,
                hasSchoolSession = true,
            ),
        )
    }

    fun goBackInOnboarding() {
        val current = onboardingProgress ?: return
        val previous = when (current.step) {
            OnboardingStep.WELCOME -> return
            OnboardingStep.ACCOUNT -> OnboardingStep.WELCOME
            OnboardingStep.SCHOOL -> OnboardingStep.ACCOUNT
            OnboardingStep.NOTIFICATIONS -> OnboardingStep.SCHOOL
            OnboardingStep.READY -> if (isGuestMode) OnboardingStep.SCHOOL else OnboardingStep.NOTIFICATIONS
            OnboardingStep.SUPPORT -> OnboardingStep.ACCOUNT
        }
        persistOnboarding(current.copy(step = previous))
    }

    suspend fun finishOnboarding() {
        graph.onboardingProgressStore.complete()
        onboardingProgress = null
        openStoredSchoolOrLogin()
    }

    suspend fun signOutGradeyIdentity() {
        try {
            graph.gradeyAuthRepository.signOut()
        } finally {
            graph.pushRegistrationStore.clear()
            graph.notificationPreferencesStore.clear()
            notificationPreferences = NotificationPreferences.Default
            notificationPreferencesError = null
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
                    } catch (_: GradeySessionExpiredException) {
                        null
                    } catch (_: Throwable) {
                        // Profile refresh is opportunistic; retain the encrypted account snapshot.
                        valid
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: GradeySessionExpiredException) {
                    null
                } catch (_: Throwable) {
                    // A temporary cloud outage must not discard the restored account or school session.
                    restored
                }
            }
        } else {
            null
        }
        account = authSession?.account
        var schoolSession = try {
            graph.schoolRepository.bootstrapSession()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        if (authSession != null && !isGuestMode) {
            val snapshot = try {
                graph.linkedAccountRepository.refreshAccounts()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            if (snapshot != null) linkedAccounts = snapshot.linkedAccounts
            if (schoolSession == null) {
                val preferred = selectRestorableSchoolAccount(
                    accounts = snapshot?.linkedAccounts ?: linkedAccounts,
                    preferredAccountID = snapshot?.activeSchoolAccountID,
                )
                if (preferred != null) {
                    schoolSession = try {
                        val activation = graph.linkedAccountRepository.activateSchoolAccount(preferred.id)
                        graph.schoolRepository.activateLinkedSchoolAccount(
                            activation.tokenPayload.makeStoredSession(activation.account),
                        )
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
                }
            }
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
        val resolvedOnboarding = graph.onboardingProgressStore.resolve(
            hasSchoolSession = schoolSession != null,
        )?.let { progress ->
            reconcileOnboardingProgress(
                progress = progress,
                isGuestMode = isGuestMode,
                hasGradeySession = authSession != null,
                hasSchoolSession = schoolSession != null,
            )
        }
        if (resolvedOnboarding != null) {
            graph.onboardingProgressStore.saveProgress(resolvedOnboarding)
        }
        onboardingProgress = resolvedOnboarding

        if (resolvedOnboarding == null && phase == AppPhase.SIGNED_IN) {
            loadCachedSignedInData()
            isLoading = true
            try {
                refreshSignedInData()
            } finally {
                isLoading = false
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
                            Uri.parse("https://help.bukovinafilip.com/en/articles/10-privacy-policy"),
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
                    journey = progress.journey,
                    appLanguage = appLanguage,
                    onAppLanguageChange = onAppLanguageChange,
                    onContinue = {
                        persistOnboarding(progress.copy(step = OnboardingStep.ACCOUNT))
                        if (account != null || isGuestMode) {
                            scope.launch { advanceOnboardingAfterAccountChoice() }
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.ACCOUNT -> GradeyIdLoginScreen(
                    isLoading = isLoading,
                    errorMessage = authError,
                    isGoogleSignInAvailable = graph.isGradeyCloudConfigured,
                    onGoogleSignIn = {
                        scope.launch {
                            isLoading = true
                            authError = null
                            try {
                                val googleCredential = requestGoogleCredential(context, graph.googleWebClientId)
                                account = graph.gradeyAuthRepository.signInWithGoogle(
                                    idToken = googleCredential.idToken,
                                    fullName = googleCredential.displayName,
                                ).account
                                graph.guestModeStore.isEnabled = false
                                isGuestMode = false
                                advanceOnboardingAfterAccountChoice()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                authError = error.userFacingMessage()
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
                                authError = error.userFacingMessage()
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize().statusBarsPadding(),
                )

                OnboardingStep.SCHOOL -> SchoolLoginScreen(
                    isLoading = isLoading,
                    errorMessage = schoolLoginError,
                    directorySchools = directorySchools,
                    isDirectoryLoading = isSchoolDirectoryLoading,
                    directoryErrorMessage = schoolDirectoryError,
                    onLoadDirectory = { scope.launch { loadSchoolDirectory() } },
                    onRetryDirectory = { scope.launch { loadSchoolDirectory(forceRefresh = true) } },
                    onLogin = { school, username, password ->
                        launchSchoolLogin {
                            graph.schoolRepository.login(school, username, password)
                            dashboard = runCatching {
                                graph.schoolRepository.loadDashboard(forceRefresh = false)
                            }.getOrNull()
                            linkCurrentSchoolIfNeeded()
                            phase = AppPhase.SIGNED_IN
                            advanceOnboardingAfterSchoolConnection()
                        }
                    },
                    onCancelLogin = ::cancelSchoolLogin,
                    onInputChanged = { schoolLoginError = null },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize().statusBarsPadding(),
                )

                OnboardingStep.NOTIFICATIONS -> OnboardingNotificationsScreen(
                    onEnable = {
                        if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            !notificationPermissionGranted
                        ) {
                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            persistOnboarding(progress.copy(step = OnboardingStep.READY))
                        }
                    },
                    onNotNow = {
                        persistOnboarding(progress.copy(step = OnboardingStep.READY))
                    },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.READY -> OnboardingReadyScreen(
                    isGuestMode = isGuestMode,
                    notificationsEnabled = notificationPermissionGranted,
                    onFinish = {
                        scope.launch {
                            isLoading = true
                            try {
                                finishOnboarding()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                dataError = error.userFacingMessage()
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize(),
                )

                OnboardingStep.SUPPORT -> OnboardingUpgradeSupportScreen(
                    isGuestMode = isGuestMode,
                    cloudLinkErrorMessage = linkedAccountError,
                    isRetryingCloudLink = isLoading,
                    onRetryCloudLink = {
                        scope.launch {
                            isLoading = true
                            try {
                                linkCurrentSchoolIfNeeded()
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onFinish = {
                        scope.launch {
                            isLoading = true
                            try {
                                finishOnboarding()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                dataError = error.userFacingMessage()
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    onBack = ::goBackInOnboarding,
                    modifier = Modifier.fillMaxSize(),
                )
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
                    try {
                        val googleCredential = requestGoogleCredential(context, graph.googleWebClientId)
                        account = graph.gradeyAuthRepository.signInWithGoogle(
                            idToken = googleCredential.idToken,
                            fullName = googleCredential.displayName,
                        ).account
                        graph.guestModeStore.isEnabled = false
                        isGuestMode = false
                        if (graph.schoolRepository.currentStoredSession() != null) {
                            graph.schoolRepository.loadCachedDashboard()?.let { dashboard = it }
                            if (dashboard == null) {
                                dashboard = runCatching {
                                    graph.schoolRepository.loadDashboard(forceRefresh = false)
                                }.getOrNull()
                            }
                            linkCurrentSchoolIfNeeded()
                        }
                        openStoredSchoolOrLogin()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        authError = error.userFacingMessage()
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
                        authError = error.userFacingMessage()
                    } finally {
                        isLoading = false
                    }
                }
            },
        )

        AppPhase.NEEDS_SCHOOL -> SchoolLoginScreen(
            isLoading = isLoading,
            initialSchoolURL = reconnectSchoolURL,
            title = if (reconnectLinkedAccount == null) "Connect Bakaláři" else "Reconnect ${reconnectLinkedAccount?.displayName}",
            subtitle = if (reconnectLinkedAccount == null) {
                "Sign in with the same school address, username, and password you use for Bakaláři."
            } else {
                "Enter the Bakaláři credentials for this exact linked school account. Gradey will reject credentials for a different student."
            },
            errorMessage = schoolLoginError,
            directorySchools = directorySchools,
            isDirectoryLoading = isSchoolDirectoryLoading,
            directoryErrorMessage = schoolDirectoryError,
            onLoadDirectory = { scope.launch { loadSchoolDirectory() } },
            onRetryDirectory = { scope.launch { loadSchoolDirectory(forceRefresh = true) } },
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
                            isAddingSchool = false
                            phase = AppPhase.SIGNED_IN
                            loadCachedSignedInData()
                            refreshSignedInData()
                        }
                    } else {
                        graph.schoolRepository.login(school, username, password)
                        dashboard = runCatching {
                            graph.schoolRepository.loadDashboard(forceRefresh = false)
                        }.getOrNull()
                        linkCurrentSchoolIfNeeded()
                        isAddingSchool = false
                        phase = AppPhase.SIGNED_IN
                        loadCachedSignedInData()
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
                    reconnectSchoolURL = ""
                    isAddingSchool = false
                    schoolLoginError = null
                    phase = AppPhase.SIGNED_IN
                    selectedTab = AppTab.ACCOUNT
                }
            },
        )

        AppPhase.SIGNED_IN -> Box(modifier = Modifier.fillMaxSize()) {
            val standardScreenModifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(bottom = 96.dp)
            val currentDashboard = dashboard
            val currentAbsence = absence
            val effectiveAbsence = currentAbsence ?: currentDashboard?.let {
                AbsenceResponse(absencesPerSubject = it.absencesPerSubject)
            }
            val todayPresentationState = TodayPresentationStates.resolve(
                hasDashboard = currentDashboard != null,
                hasSubjects = currentDashboard?.marksResponse?.subjects?.isNotEmpty() == true,
                isLoading = isLoading,
                hasError = dataError != null,
            )
            val absencePresentationState = AbsencePresentationStates.resolve(
                hasResponse = currentAbsence != null,
                hasRecords = currentAbsence?.let {
                    it.absences.isNotEmpty() || it.absencesPerSubject.isNotEmpty()
                } == true,
                isLoading = isLoading,
                hasError = absenceRefreshError != null,
            )
            when (selectedTab) {
                AppTab.TODAY -> when (todayPresentationState) {
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
                            currentSchoolBaseURL = currentSchoolBaseURL,
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
                            onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                            onOpenGradeyTools = { isGradeyAIPresented = true },
                            onOpenMarks = { selectedTab = AppTab.SUBJECTS },
                            onOpenAbsence = { selectedTab = AppTab.ABSENCE },
                            onOpenTimetable = { selectedTab = AppTab.TIMETABLE },
                            onOpenMeals = {
                                if (showMealsTab) selectedTab = AppTab.STRAVACZ
                            },
                            onActivateLinkedAccount = { linked ->
                                scope.launch {
                                    if (activateLinkedAccount(linked)) refreshSignedInData()
                                }
                            },
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

                AppTab.SUBJECTS -> if (currentDashboard != null && effectiveAbsence != null) SubjectsScreen(
                    subjects = currentDashboard.marksResponse.subjects,
                    absence = effectiveAbsence,
                    gradeTrends = gradeHistorySnapshot
                        ?.takeIf { it.linkedAccountID == activeLinkedAccountID }
                        ?.trends
                        .orEmpty(),
                    onPredictSubjectAverage = { subject, markText, weight ->
                        graph.schoolRepository.predictSubjectAverage(subject, markText, weight)
                    },
                    refreshErrorMessage = marksRefreshError,
                    isRefreshing = isLoading,
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
                    onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                    onOpenGradeyTools = { isGradeyAIPresented = true },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = "Marks",
                    isLoading = isLoading,
                    errorMessage = dataError,
                    onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                    modifier = standardScreenModifier,
                )
                AppTab.ABSENCE -> when (absencePresentationState) {
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
                            studentName = currentDashboard?.user?.fullName ?: "Student",
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
                            onLoadPredictionLessons = graph.schoolRepository::loadAbsencePredictionLessons,
                            onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                            onOpenGradeyTools = { isGradeyAIPresented = true },
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
                AppTab.TIMETABLE -> if (timetable != null) TimetableScreen(
                    week = timetable,
                    isRefreshing = isLoading,
                    errorMessage = timetableError,
                    onRefresh = {
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    timetableError = null
                                    timetableError = loadTimetable(timetable?.weekStart ?: timetableRequestedWeek)?.userFacingMessage()
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
                                    timetableError = loadTimetableCacheFirst(weekContaining)?.userFacingMessage()
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                    onOpenGradeyTools = { isGradeyAIPresented = true },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = context.getString(TimetableR.string.timetable_title),
                    isLoading = isLoading,
                    errorMessage = timetableError,
                    onRetry = {
                        scope.launch {
                            runWithLoading {
                                timetableError = null
                                timetableError = loadTimetableCacheFirst(timetableRequestedWeek)?.userFacingMessage()
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                )
                AppTab.STRAVACZ -> StravaCZScreen(
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
                    onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                    onOpenGradeyTools = { isGradeyAIPresented = true },
                    modifier = standardScreenModifier,
                )
                AppTab.ACCOUNT -> AccountScreen(
                    account = account,
                    linkedAccounts = linkedAccounts,
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
                    onUpdateFullName = { fullName ->
                        scope.launch {
                            isUpdatingProfile = true
                            profileError = null
                            try {
                                account = graph.gradeyAuthRepository.updateFullName(fullName)
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: GradeySessionExpiredException) {
                                account = null
                                authError = error.userFacingMessage()
                                selectedTab = AppTab.TODAY
                                phase = AppPhase.SIGNED_OUT
                            } catch (error: Throwable) {
                                profileError = error.userFacingMessage()
                            } finally {
                                isUpdatingProfile = false
                            }
                        }
                    },
                    onConnectGradeyId = {
                        graph.guestModeStore.isEnabled = false
                        isGuestMode = false
                        account = null
                        authError = null
                        profileError = null
                        selectedTab = AppTab.TODAY
                        phase = AppPhase.SIGNED_OUT
                    },
                    onRefreshLinkedAccounts = {
                        scope.launch { refreshLinkedAccountSnapshot() }
                    },
                    onAddSchool = {
                        isAddingSchool = true
                        reconnectLinkedAccount = null
                        reconnectSchoolURL = ""
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
                            reconnectLinkedAccount = linked
                            reconnectSchoolURL = graph.schoolRepository.currentStoredSession()
                                ?.takeIf { it.linkedAccountID == linked.id || linkedAccounts.size == 1 }
                                ?.baseURL
                                .orEmpty()
                            schoolLoginError = null
                            phase = AppPhase.NEEDS_SCHOOL
                        }
                    },
                    onToggleLinkedNotifications = { linked, enabled ->
                        scope.launch { updateLinkedAccountNotifications(linked, enabled) }
                    },
                    onOpenNotificationSettings = {
                        notificationSettingsLauncher.launch(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                                Settings.EXTRA_APP_PACKAGE,
                                context.packageName,
                            ),
                        )
                    },
                    onUpdateNotificationPreferences = { preferences ->
                        scope.launch { updateNotificationPreferences(preferences) }
                    },
                    onOpenMeals = {
                        if (!showMealsTab) {
                            graph.mealsTabPreferenceStore.isVisible = true
                            showMealsTab = true
                        }
                        selectedTab = AppTab.STRAVACZ
                    },
                    onRetryStravaCloudLink = {
                        scope.launch { retryStravaCloudLink() }
                    },
                    onOpenPrivacyPolicy = {
                        val language = if (appLanguage.pickerLanguage == AppLanguage.CZECH) "cs" else "en"
                        runCatching {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://help.bukovinafilip.com/$language/articles/10-privacy-policy"),
                                ),
                            )
                        }
                    },
                    onOpenTermsOfUse = {
                        val language = if (appLanguage.pickerLanguage == AppLanguage.CZECH) "cs" else "en"
                        runCatching {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://help.bukovinafilip.com/$language/articles/11-terms-and-conditions"),
                                ),
                            )
                        }
                    },
                    onUnlinkLinkedAccount = { linked ->
                        scope.launch { unlinkLinkedAccount(linked) }
                    },
                    onAppLanguageChange = onAppLanguageChange,
                    onShowMealsTabChange = { visible ->
                        graph.mealsTabPreferenceStore.isVisible = visible
                        showMealsTab = visible
                        if (!visible && selectedTab == AppTab.STRAVACZ) selectedTab = AppTab.TODAY
                    },
                    onSignOut = {
                        scope.launch {
                            try {
                                if (isGuestMode || !graph.isGradeyCloudConfigured) {
                                    disconnectSchool()
                                    phase = AppPhase.NEEDS_SCHOOL
                                    return@launch
                                }

                                disconnectStravaCZ()
                                signOutGradeyIdentity()
                                disconnectSchool()
                                clearLinkedAccountsForLocalMode()
                                try {
                                    CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (_: Throwable) {
                                    // Credential Manager cleanup must not undo completed local sign-out.
                                }
                                graph.guestModeStore.isEnabled = false
                                isGuestMode = false
                                account = null
                                phase = AppPhase.SIGNED_OUT
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                profileError = error.userFacingMessage()
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                )
            }

            val selectedTabHasUsableContent = when (selectedTab) {
                AppTab.TODAY, AppTab.SUBJECTS -> currentDashboard != null
                AppTab.ABSENCE -> currentAbsence != null
                AppTab.TIMETABLE -> timetable != null
                AppTab.STRAVACZ -> stravaMenu != null
                AppTab.ACCOUNT -> false
            }
            val selectedTabRefreshError = when (selectedTab) {
                AppTab.ABSENCE -> absenceRefreshError
                AppTab.STRAVACZ -> null
                AppTab.TODAY, AppTab.SUBJECTS -> dataError ?: gradeHistoryRefreshError
                else -> dataError
            }
            if (
                selectedTab != AppTab.ACCOUNT &&
                selectedTabRefreshError != null &&
                selectedTabHasUsableContent
            ) {
                DataRefreshWarning(
                    message = selectedTabRefreshError.orEmpty(),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(start = 16.dp, end = 16.dp, bottom = 88.dp),
                )
            }

            if (selectedTab != AppTab.ACCOUNT) {
                GradeyBottomNavigation(
                    selectedTab = selectedTab,
                    showMealsTab = showMealsTab,
                    onSelect = {
                        selectedTab = it
                        dataError = null
                    },
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }

            if (isGradeyAIPresented) {
                GradeyAIScreen(
                    repository = graph.gradeyAIRepository,
                    isGuestMode = isGuestMode,
                    onOpenAccount = {
                        isGradeyAIPresented = false
                        selectedTab = AppTab.ACCOUNT
                    },
                    onClose = { isGradeyAIPresented = false },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

private suspend fun requestGoogleCredential(
    context: android.content.Context,
    serverClientId: String,
): GoogleIdTokenCredential {
    if (serverClientId.isBlank()) {
        throw IllegalStateException("Google sign-in is not configured in this build.")
    }
    val option = GetSignInWithGoogleOption.Builder(serverClientId).build()
    val request = GetCredentialRequest.Builder()
        .addCredentialOption(option)
        .build()
    val credential = CredentialManager.create(context).getCredential(context, request).credential
    if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
        throw IllegalStateException("Google sign-in returned an unsupported credential.")
    }
    return GoogleIdTokenCredential.createFrom(credential.data)
}

private fun Throwable.userFacingMessage(): String =
    message?.trim()?.takeIf { it.isNotEmpty() } ?: "Something went wrong. Please try again."

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
                imageVector = Icons.Default.Error,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(20.dp),
            )
            Column {
                Text(
                    text = "Some data could not refresh",
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
        GradeyHero(title = title, subtitle = "Your Bakaláři data will appear here after it loads.")
        GradeySectionCard {
            if (isLoading) {
                CircularProgressIndicator()
                Text("Loading from Bakaláři…")
            } else {
                Text(errorMessage ?: "No data is available yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = onRetry) {
                    Text("Try again")
                }
            }
        }
    }
}

private val MarksTabs = listOf(AppTab.TODAY, AppTab.SUBJECTS, AppTab.ABSENCE, AppTab.TIMETABLE, AppTab.STRAVACZ)

@Composable
private fun AppTab.icon() = when (this) {
    AppTab.TODAY -> Icons.Default.LightMode
    AppTab.SUBJECTS -> Icons.Default.Verified
    AppTab.ABSENCE -> Icons.Default.CalendarMonth
    AppTab.TIMETABLE -> Icons.Default.CalendarMonth
    AppTab.STRAVACZ -> Icons.Default.Restaurant
    AppTab.ACCOUNT -> Icons.Default.Person
}

@Composable
private fun GradeyBottomNavigation(
    selectedTab: AppTab,
    showMealsTab: Boolean,
    onSelect: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val visibleTabs = MarksTabs.filter { showMealsTab || it != AppTab.STRAVACZ }
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
            color = Color(0xFFFDFDFF).copy(alpha = 0.96f),
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
                        selected = selectedTab == tab,
                        onClick = { onSelect(tab) },
                    )
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.BottomNavigationItem(
    tab: AppTab,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val foreground = if (selected) Color(0xFF0DA388) else Color(0xFF19191D)
    Surface(
        modifier = Modifier
            .weight(1f)
            .height(54.dp),
        onClick = onClick,
        shape = RoundedCornerShape(27.dp),
        color = if (selected) Color(0xFFE8E8EC) else Color.Transparent,
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
                    contentDescription = tab.label,
                    tint = foreground,
                    modifier = Modifier.size(24.dp),
                )
                if (tab == AppTab.ABSENCE) {
                    Icon(
                        imageVector = Icons.Default.Error,
                        contentDescription = null,
                        tint = foreground,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(11.dp),
                    )
                }
            }
            Text(
                text = tab.label,
                color = if (selected) Color(0xFF0DA388) else Color.Black,
                fontSize = 12.sp,
                lineHeight = 14.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                maxLines = 1,
            )
        }
    }
}
