package com.bukovinafilip.gradey

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
import androidx.core.content.ContextCompat
import com.bukovinafilip.gradey.feature.absence.AbsenceScreen
import com.bukovinafilip.gradey.feature.account.AccountScreen
import com.bukovinafilip.gradey.feature.auth.AgeAttestationScreen
import com.bukovinafilip.gradey.feature.auth.GradeyCheckingScreen
import com.bukovinafilip.gradey.feature.auth.GradeyIdLoginScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingNotificationsScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingReadyScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingUpgradeSupportScreen
import com.bukovinafilip.gradey.feature.auth.OnboardingWelcomeScreen
import com.bukovinafilip.gradey.feature.login.SchoolLoginScreen
import com.bukovinafilip.gradey.feature.stravacz.StravaCZScreen
import com.bukovinafilip.gradey.feature.subjects.SubjectsScreen
import com.bukovinafilip.gradey.feature.timetable.TimetableScreen
import com.bukovinafilip.gradey.feature.today.TodayScreen
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.domain.GradeyStartupDestination
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.WearPayloadBuilder
import com.bukovinafilip.gradey.domain.loadCacheFirst
import com.bukovinafilip.gradey.domain.reconcileOnboardingProgress
import com.bukovinafilip.gradey.domain.selectGradeyStartupDestination
import com.bukovinafilip.gradey.domain.selectRestorableSchoolAccount
import com.bukovinafilip.gradey.domain.selectSchoolAccountRequiringReconnect
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.widgets.updateNextLessonWidgets
import com.bukovinafilip.gradey.wear.PhoneWearSyncPublisher
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val graph = (application as GradeyApplication).graph
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
                        initialTab = if (intent?.data?.host == "timetable" || intent?.data?.path == "/timetable") AppTab.TIMETABLE else AppTab.TODAY,
                    )
                }
            }
        }
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

@Composable
private fun GradeyApp(
    graph: com.bukovinafilip.gradey.data.AndroidGradeyGraph,
    appLanguage: AppLanguage,
    onAppLanguageChange: (AppLanguage) -> Unit,
    initialTab: AppTab,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf(AppPhase.CHECKING) }
    var selectedTab by remember { mutableStateOf(initialTab) }
    var isLoading by remember { mutableStateOf(false) }
    var authError by remember { mutableStateOf<String?>(null) }
    var schoolLoginError by remember { mutableStateOf<String?>(null) }
    var schoolDirectoryError by remember { mutableStateOf<String?>(null) }
    var dataError by remember { mutableStateOf<String?>(null) }
    var profileError by remember { mutableStateOf<String?>(null) }
    var isUpdatingProfile by remember { mutableStateOf(false) }
    var ageAttestationKind by remember { mutableStateOf(graph.ageAttestationStore.kind) }
    var isGuestMode by remember { mutableStateOf(graph.guestModeStore.isEnabled) }
    var onboardingProgress by remember { mutableStateOf<OnboardingProgress?>(null) }
    var account by remember { mutableStateOf<GradeyAccount?>(null) }
    var linkedAccounts by remember { mutableStateOf<List<LinkedSchoolAccount>>(emptyList()) }
    var activeLinkedAccountID by remember { mutableStateOf<String?>(null) }
    var reconnectLinkedAccount by remember { mutableStateOf<LinkedSchoolAccount?>(null) }
    var reconnectSchoolURL by remember { mutableStateOf("") }
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
    var timetable by remember { mutableStateOf<TimetableWeek?>(null) }
    var stravaMenu by remember { mutableStateOf<StravaCZMenu?>(null) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        val current = onboardingProgress ?: return@rememberLauncherForActivityResult
        val ready = current.copy(step = OnboardingStep.READY)
        graph.onboardingProgressStore.saveProgress(ready)
        onboardingProgress = ready
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

    suspend fun loadCachedSignedInData() {
        activeLinkedAccountID = graph.schoolRepository.currentStoredSession()?.linkedAccountID
        graph.schoolRepository.loadCachedDashboard()?.let { dashboard = it }
        graph.schoolRepository.loadCachedAbsence()?.let { absence = it }
        graph.schoolRepository.loadCachedTimetable(TimetableDates.todayString())?.let { timetable = it }
        graph.stravaCZRepository.loadCachedMenu()?.let { stravaMenu = it }
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }.getOrDefault(emptyList())
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
        applyFreshTimetable(graph.schoolRepository.loadTimetable(weekContaining))
        null
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        error
    }

    suspend fun loadTimetableCacheFirst(weekContaining: String): Throwable? = loadCacheFirst(
        loadCached = { graph.schoolRepository.loadCachedTimetable(weekContaining) },
        loadFresh = { graph.schoolRepository.loadTimetable(weekContaining) },
        onCached = { timetable = it },
        onFresh = { applyFreshTimetable(it) },
    )

    fun routeToSchoolReconnect() {
        dashboard = null
        absence = null
        timetable = null
        stravaMenu = null
        activeLinkedAccountID = null
        reconnectLinkedAccount = null
        selectedTab = AppTab.TODAY
        dataError = null
        schoolLoginError = "Your Bakaláři session expired. Please reconnect your school account."
        phase = AppPhase.NEEDS_SCHOOL
    }

    suspend fun disconnectSchool() {
        graph.schoolRepository.logout()
        try {
            graph.stravaCZRepository.logout()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Bakaláři disconnect remains complete if the optional meals provider is unavailable.
        }
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
        timetable = null
        stravaMenu = null
        activeLinkedAccountID = null
        reconnectLinkedAccount = null
        selectedTab = AppTab.TODAY
        dataError = null
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
        activeLinkedAccountID = null
    }

    suspend fun refreshLinkedAccountSnapshot() {
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }
            .getOrDefault(linkedAccounts)
        if (account == null || isGuestMode || !graph.isGradeyCloudConfigured) return

        isRefreshingLinkedAccounts = true
        linkedAccountError = null
        try {
            linkedAccounts = graph.linkedAccountRepository.refreshAccounts().linkedAccounts
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

    suspend fun reconnectCurrentSchool(linked: LinkedSchoolAccount): Boolean {
        val session = graph.schoolRepository.currentStoredSession() ?: return false
        return try {
            val updated = graph.linkedAccountRepository.reconnectSchoolAccount(
                linked.id,
                session,
                dashboard?.user,
            )
            graph.schoolRepository.associateCurrentSession(updated)
            activeLinkedAccountID = updated.id
            linkedAccounts = graph.linkedAccountRepository.localAccounts()
            reconnectLinkedAccount = null
            reconnectSchoolURL = ""
            linkedAccountError = null
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            linkedAccountError = error.userFacingMessage()
            false
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
            absence = null
            timetable = null
            stravaMenu = null
            activeLinkedAccountID = activation.account.id
            selectedTab = AppTab.TODAY
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
            if (activeLinkedAccountID == linked.id) {
                graph.schoolRepository.disassociateCurrentSession(linked.id)
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
        val failures = mutableListOf<Throwable>()
        try {
            dashboard = graph.schoolRepository.loadDashboard(forceRefresh = forceRefresh)
        } catch (error: CancellationException) {
            throw error
        } catch (_: SchoolSessionExpiredException) {
            routeToSchoolReconnect()
            return
        } catch (error: Throwable) {
            failures += error
        }
        try {
            absence = graph.schoolRepository.loadAbsence(forceRefresh = forceRefresh)
        } catch (error: CancellationException) {
            throw error
        } catch (_: SchoolSessionExpiredException) {
            routeToSchoolReconnect()
            return
        } catch (error: Throwable) {
            failures += error
        }
        when (val timetableFailure = loadTimetable(TimetableDates.todayString())) {
            is SchoolSessionExpiredException -> {
                routeToSchoolReconnect()
                return
            }
            null -> Unit
            else -> failures += timetableFailure
        }
        if (runCatching { graph.stravaCZRepository.bootstrapSession() }.getOrNull() != null) {
            runCatching { graph.stravaCZRepository.loadMenu(forceRefresh = forceRefresh).second }
                .onSuccess { stravaMenu = it }
        }
        refreshLinkedAccountSnapshot()
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

    fun notificationsAreEnabled(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    LaunchedEffect(ageAttestationKind) {
        if (ageAttestationKind == null) return@LaunchedEffect
        if (isGuestMode) {
            try {
                graph.gradeyAuthRepository.signOut()
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
                                graph.gradeyAuthRepository.signOut()
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
                            !notificationsAreEnabled()
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
                    notificationsEnabled = notificationsAreEnabled(),
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
                        graph.gradeyAuthRepository.signOut()
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
                    graph.schoolRepository.login(school, username, password)
                    dashboard = runCatching {
                        graph.schoolRepository.loadDashboard(forceRefresh = false)
                    }.getOrNull()
                    val reconnectTarget = reconnectLinkedAccount
                    if (reconnectTarget != null && !reconnectCurrentSchool(reconnectTarget)) {
                        schoolLoginError = linkedAccountError
                            ?: "Gradey could not reconnect this school account. Please try again."
                    } else {
                        if (reconnectTarget == null) linkCurrentSchoolIfNeeded()
                        phase = AppPhase.SIGNED_IN
                        loadCachedSignedInData()
                        refreshSignedInData()
                    }
                }
            },
            onCancelLogin = ::cancelSchoolLogin,
            onInputChanged = { schoolLoginError = null },
            onBack = if (reconnectLinkedAccount == null) {
                null
            } else {
                {
                    reconnectLinkedAccount = null
                    reconnectSchoolURL = ""
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
            when (selectedTab) {
                AppTab.TODAY -> if (currentDashboard != null && effectiveAbsence != null) {
                    TodayScreen(
                        dashboard = currentDashboard,
                        absence = effectiveAbsence,
                        timetable = timetable,
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
                        onOpenGradeyTools = { selectedTab = AppTab.STRAVACZ },
                        onOpenMarks = { selectedTab = AppTab.SUBJECTS },
                        onOpenAbsence = { selectedTab = AppTab.ABSENCE },
                        onOpenTimetable = { selectedTab = AppTab.TIMETABLE },
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    CoreDataUnavailableScreen(
                        title = "Today",
                        isLoading = isLoading,
                        errorMessage = dataError,
                        onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                        modifier = standardScreenModifier,
                    )
                }

                AppTab.SUBJECTS -> if (currentDashboard != null && effectiveAbsence != null) SubjectsScreen(
                    subjects = currentDashboard.marksResponse.subjects,
                    absence = effectiveAbsence,
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
                    onOpenGradeyTools = { selectedTab = AppTab.STRAVACZ },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = "Marks",
                    isLoading = isLoading,
                    errorMessage = dataError,
                    onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                    modifier = standardScreenModifier,
                )
                AppTab.ABSENCE -> if (currentAbsence != null) AbsenceScreen(
                    response = currentAbsence,
                    studentName = currentDashboard?.user?.fullName ?: "Student",
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
                    onOpenGradeyTools = { selectedTab = AppTab.STRAVACZ },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = "Absence",
                    isLoading = isLoading,
                    errorMessage = dataError,
                    onRetry = { scope.launch { runWithLoading { refreshSignedInData(true) } } },
                    modifier = standardScreenModifier,
                )
                AppTab.TIMETABLE -> if (timetable != null) TimetableScreen(
                    week = timetable,
                    isRefreshing = isLoading,
                    onRefresh = {
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    dataError = null
                                    dataError = loadTimetable(timetable?.weekStart ?: TimetableDates.todayString())?.userFacingMessage()
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
                                    dataError = null
                                    dataError = loadTimetableCacheFirst(weekContaining)?.userFacingMessage()
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                    onOpenGradeyTools = { selectedTab = AppTab.STRAVACZ },
                    modifier = Modifier.fillMaxSize(),
                ) else CoreDataUnavailableScreen(
                    title = "Timetable",
                    isLoading = isLoading,
                    errorMessage = dataError,
                    onRetry = {
                        scope.launch {
                            runWithLoading {
                                dataError = null
                                dataError = loadTimetableCacheFirst(TimetableDates.todayString())?.userFacingMessage()
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                )
                AppTab.STRAVACZ -> StravaCZScreen(stravaMenu, standardScreenModifier)
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
                    onUnlinkLinkedAccount = { linked ->
                        scope.launch { unlinkLinkedAccount(linked) }
                    },
                    onAppLanguageChange = onAppLanguageChange,
                    onSignOut = {
                        scope.launch {
                            try {
                                if (isGuestMode || !graph.isGradeyCloudConfigured) {
                                    disconnectSchool()
                                    phase = AppPhase.NEEDS_SCHOOL
                                    return@launch
                                }

                                graph.gradeyAuthRepository.signOut()
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
            if (
                selectedTab != AppTab.ACCOUNT &&
                dataError != null &&
                selectedTabHasUsableContent
            ) {
                DataRefreshWarning(
                    message = dataError.orEmpty(),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(start = 16.dp, end = 16.dp, bottom = 88.dp),
                )
            }

            if (selectedTab != AppTab.ACCOUNT) {
                GradeyBottomNavigation(
                    selectedTab = selectedTab,
                    onSelect = {
                        selectedTab = it
                        dataError = null
                    },
                    modifier = Modifier.align(Alignment.BottomCenter),
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
    onSelect: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val visibleTabs = MarksTabs
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
