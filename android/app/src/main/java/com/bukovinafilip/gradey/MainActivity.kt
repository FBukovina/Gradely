package com.bukovinafilip.gradey

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import com.bukovinafilip.gradey.feature.absence.AbsenceScreen
import com.bukovinafilip.gradey.feature.account.AccountScreen
import com.bukovinafilip.gradey.feature.auth.GradeyIdLoginScreen
import com.bukovinafilip.gradey.feature.login.SchoolLoginScreen
import com.bukovinafilip.gradey.feature.stravacz.StravaCZScreen
import com.bukovinafilip.gradey.feature.subjects.SubjectsScreen
import com.bukovinafilip.gradey.feature.timetable.TimetableScreen
import com.bukovinafilip.gradey.feature.today.TodayScreen
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.LocalDate

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            GradeyTheme {
                GradeyApp(
                    graph = (application as GradeyApplication).graph,
                    initialTab = if (intent?.data?.host == "timetable" || intent?.data?.path == "/timetable") AppTab.TIMETABLE else AppTab.TODAY,
                )
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
    var account by remember { mutableStateOf<GradeyAccount?>(null) }
    var linkedAccounts by remember { mutableStateOf<List<LinkedSchoolAccount>>(emptyList()) }
    var directorySchools by remember { mutableStateOf<List<SchoolDirectorySchool>>(emptyList()) }
    var isSchoolDirectoryLoading by remember { mutableStateOf(false) }
    var hasLoadedSchoolDirectory by remember { mutableStateOf(false) }
    var dashboard by remember { mutableStateOf<DashboardData?>(null) }
    var absence by remember { mutableStateOf<AbsenceResponse?>(null) }
    var timetable by remember { mutableStateOf<TimetableWeek?>(null) }
    var stravaMenu by remember { mutableStateOf<StravaCZMenu?>(null) }

    suspend fun runWithLoading(block: suspend () -> Unit) {
        if (isLoading) return
        isLoading = true
        try {
            block()
        } finally {
            isLoading = false
        }
    }

    suspend fun loadCachedSignedInData() {
        graph.schoolRepository.loadCachedDashboard()?.let { dashboard = it }
        graph.schoolRepository.loadCachedAbsence()?.let { absence = it }
        graph.schoolRepository.loadCachedTimetable(LocalDate.now().toString())?.let { timetable = it }
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

    suspend fun loadTimetable(weekContaining: String): Throwable? {
        return runCatching { graph.schoolRepository.loadTimetable(weekContaining) }
            .onSuccess { timetable = it }
            .exceptionOrNull()
    }

    suspend fun refreshSignedInData(forceRefresh: Boolean = false) {
        val failures = mutableListOf<Throwable>()
        runCatching { graph.schoolRepository.loadDashboard(forceRefresh = forceRefresh) }
            .onSuccess { dashboard = it }
            .onFailure(failures::add)
        runCatching { graph.schoolRepository.loadAbsence(forceRefresh = forceRefresh) }
            .onSuccess { absence = it }
            .onFailure(failures::add)
        loadTimetable(LocalDate.now().toString())?.let(failures::add)
        if (runCatching { graph.stravaCZRepository.bootstrapSession() }.getOrNull() != null) {
            runCatching { graph.stravaCZRepository.loadMenu(forceRefresh = forceRefresh).second }
                .onSuccess { stravaMenu = it }
        }
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }.getOrDefault(emptyList())
        dataError = failures.firstOrNull()?.userFacingMessage()
    }

    LaunchedEffect(Unit) {
        val authSession = if (graph.isGradeyCloudConfigured) {
            runCatching { graph.gradeyAuthRepository.bootstrapSession() }.getOrNull()
        } else {
            null
        }
        account = authSession?.account
        val schoolSession = runCatching { graph.schoolRepository.bootstrapSession() }.getOrNull()
        phase = when {
            graph.isGradeyCloudConfigured && authSession == null -> AppPhase.SIGNED_OUT
            schoolSession == null -> AppPhase.NEEDS_SCHOOL
            else -> AppPhase.SIGNED_IN
        }
        if (phase == AppPhase.SIGNED_IN) {
            loadCachedSignedInData()
            isLoading = true
            try {
                refreshSignedInData()
            } finally {
                isLoading = false
            }
        }
    }

    when (phase) {
        AppPhase.CHECKING -> GradeyIdLoginScreen(isLoading = true, onGoogleSignIn = {})
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
                        phase = if (graph.schoolRepository.bootstrapSession() == null) {
                            AppPhase.NEEDS_SCHOOL
                        } else {
                            AppPhase.SIGNED_IN
                        }
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
            errorMessage = schoolLoginError,
            directorySchools = directorySchools,
            isDirectoryLoading = isSchoolDirectoryLoading,
            directoryErrorMessage = schoolDirectoryError,
            onLoadDirectory = { scope.launch { loadSchoolDirectory() } },
            onRetryDirectory = { scope.launch { loadSchoolDirectory(forceRefresh = true) } },
            onLogin = { school, username, password ->
                scope.launch {
                    isLoading = true
                    schoolLoginError = null
                    try {
                        graph.schoolRepository.login(school, username, password)
                        phase = AppPhase.SIGNED_IN
                        loadCachedSignedInData()
                        refreshSignedInData()
                    } catch (error: Throwable) {
                        schoolLoginError = error.userFacingMessage()
                    } finally {
                        isLoading = false
                    }
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
            when (selectedTab) {
                AppTab.TODAY -> if (currentDashboard != null && currentAbsence != null) {
                    TodayScreen(
                        dashboard = currentDashboard,
                        absence = currentAbsence,
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

                AppTab.SUBJECTS -> if (currentDashboard != null && currentAbsence != null) SubjectsScreen(
                    subjects = currentDashboard.marksResponse.subjects,
                    absence = currentAbsence,
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
                                    dataError = loadTimetable(timetable?.weekStart ?: LocalDate.now().toString())?.userFacingMessage()
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
                                    dataError = loadTimetable(weekContaining)?.userFacingMessage()
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
                                dataError = loadTimetable(LocalDate.now().toString())?.userFacingMessage()
                            }
                        }
                    },
                    modifier = standardScreenModifier,
                )
                AppTab.STRAVACZ -> StravaCZScreen(stravaMenu, standardScreenModifier)
                AppTab.ACCOUNT -> AccountScreen(
                    account = account,
                    linkedAccounts = linkedAccounts,
                    onSignOut = {
                        scope.launch {
                            graph.stravaCZRepository.logout()
                            graph.gradeyAuthRepository.signOut()
                            graph.schoolRepository.logout()
                            graph.linkedAccountRepository.clearLocalAccounts()
                            runCatching {
                                CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
                            }
                            account = null
                            dashboard = null
                            absence = null
                            timetable = null
                            stravaMenu = null
                            selectedTab = AppTab.TODAY
                            phase = if (graph.isGradeyCloudConfigured) AppPhase.SIGNED_OUT else AppPhase.NEEDS_SCHOOL
                        }
                    },
                    modifier = standardScreenModifier,
                )
            }

            if (selectedTab != AppTab.ACCOUNT) {
                GradeyBottomNavigation(
                    selectedTab = selectedTab,
                    onSelect = { selectedTab = it },
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
