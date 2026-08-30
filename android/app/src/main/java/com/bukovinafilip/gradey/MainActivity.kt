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
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.DemoData
import com.bukovinafilip.gradey.domain.SchoolLoginStep
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
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
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
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf(AppPhase.CHECKING) }
    var selectedTab by remember { mutableStateOf(initialTab) }
    var isLoading by remember { mutableStateOf(false) }
    var account by remember { mutableStateOf<GradeyAccount?>(null) }
    var linkedAccounts by remember { mutableStateOf<List<LinkedSchoolAccount>>(emptyList()) }
    var dashboard by remember { mutableStateOf(DemoData.fixture.dashboard) }
    var absence by remember { mutableStateOf(DemoData.absenceResponse) }
    var timetable by remember { mutableStateOf<TimetableWeek?>(null) }
    var stravaMenu by remember { mutableStateOf<StravaCZMenu?>(DemoData.stravaMenu) }

    suspend fun loadTimetable(weekContaining: String) {
        timetable = runCatching { graph.schoolRepository.loadTimetable(weekContaining) }
            .getOrElse { timetable }
    }

    suspend fun refreshSignedInData(forceRefresh: Boolean = false) {
        dashboard = runCatching { graph.schoolRepository.loadDashboard(forceRefresh = forceRefresh) }.getOrElse { DemoData.fixture.dashboard }
        absence = runCatching { graph.schoolRepository.loadAbsence(forceRefresh = forceRefresh) }.getOrElse { DemoData.absenceResponse }
        loadTimetable(LocalDate.now().toString())
        stravaMenu = runCatching { graph.stravaCZRepository.loadMenu().second }.getOrElse { DemoData.stravaMenu }
        linkedAccounts = runCatching { graph.linkedAccountRepository.localAccounts() }.getOrDefault(emptyList())
    }

    LaunchedEffect(Unit) {
        val authSession = graph.gradeyAuthRepository.bootstrapSession()
        account = authSession?.account
        val schoolSession = graph.schoolRepository.bootstrapSession()
        phase = when {
            authSession == null -> AppPhase.SIGNED_OUT
            schoolSession == null -> AppPhase.NEEDS_SCHOOL
            else -> AppPhase.SIGNED_IN
        }
        if (phase == AppPhase.SIGNED_IN) refreshSignedInData()
    }

    when (phase) {
        AppPhase.CHECKING -> GradeyIdLoginScreen(isLoading = true, onGoogleSignIn = {}, onTestingBypass = {})
        AppPhase.SIGNED_OUT -> GradeyIdLoginScreen(
            isLoading = isLoading,
            onGoogleSignIn = {
                scope.launch {
                    isLoading = true
                    account = graph.gradeyAuthRepository.signInWithGoogle(
                        idToken = "demo-google-id-token",
                        fullName = "Demo Student",
                    ).account
                    isLoading = false
                    phase = AppPhase.NEEDS_SCHOOL
                }
            },
            onTestingBypass = {
                scope.launch {
                    account = graph.gradeyAuthRepository.signInWithGoogle("demo-google-id-token", fullName = "Demo Student").account
                    val step = graph.schoolRepository.beginLogin(
                        provider = com.bukovinafilip.gradey.model.SchoolProvider.BAKALARI,
                        schoolURL = "demo.gradey.app",
                        username = "apple-review",
                        password = "GradelyDemo2026!",
                    )
                    if (step is SchoolLoginStep.SignedIn) {
                        refreshSignedInData()
                        phase = AppPhase.SIGNED_IN
                    }
                }
            },
        )

        AppPhase.NEEDS_SCHOOL -> SchoolLoginScreen(
            isLoading = isLoading,
            onLogin = { provider, school, username, password ->
                scope.launch {
                    isLoading = true
                    val step = graph.schoolRepository.beginLogin(provider, school, username, password)
                    isLoading = false
                    if (step is SchoolLoginStep.SignedIn) {
                        refreshSignedInData()
                        phase = AppPhase.SIGNED_IN
                    }
                }
            },
        )

        AppPhase.SIGNED_IN -> Box(modifier = Modifier.fillMaxSize()) {
            val standardScreenModifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(bottom = 96.dp)
            when (selectedTab) {
                AppTab.TODAY -> TodayScreen(
                    dashboard = dashboard,
                    absence = absence,
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

                AppTab.SUBJECTS -> SubjectsScreen(
                    subjects = dashboard.marksResponse.subjects,
                    absence = absence,
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
                )
                AppTab.ABSENCE -> AbsenceScreen(
                    response = absence,
                    studentName = dashboard.user?.fullName ?: "Student",
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
                )
                AppTab.TIMETABLE -> TimetableScreen(
                    week = timetable,
                    isRefreshing = isLoading,
                    onRefresh = {
                        if (!isLoading) {
                            scope.launch {
                                isLoading = true
                                try {
                                    loadTimetable(timetable?.weekStart ?: LocalDate.now().toString())
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
                                    loadTimetable(weekContaining)
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    },
                    onOpenAccount = { selectedTab = AppTab.ACCOUNT },
                    onOpenGradeyTools = { selectedTab = AppTab.STRAVACZ },
                    modifier = Modifier.fillMaxSize(),
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
                            phase = AppPhase.SIGNED_OUT
                        }
                    },
                    modifier = standardScreenModifier,
                )
            }

            GradeyBottomNavigation(
                selectedTab = selectedTab,
                onSelect = { selectedTab = it },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }
}

private val CoreTabs = listOf(AppTab.TODAY, AppTab.SUBJECTS, AppTab.ABSENCE, AppTab.TIMETABLE)
private val MarksTabs = CoreTabs + AppTab.STRAVACZ

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
    val visibleTabs = if (
        selectedTab == AppTab.SUBJECTS ||
        selectedTab == AppTab.TIMETABLE ||
        selectedTab == AppTab.STRAVACZ
    ) MarksTabs else CoreTabs
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
