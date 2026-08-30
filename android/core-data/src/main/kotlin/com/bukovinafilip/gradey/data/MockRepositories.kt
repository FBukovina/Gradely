package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.GradeHistoryTrend
import com.bukovinafilip.gradey.domain.LinkedAccountRepository
import com.bukovinafilip.gradey.domain.SchoolLoginStep
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.StravaCZRepository
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

class MockSchoolRepository : SchoolRepository {
    private var session: StoredSession? = null

    override suspend fun bootstrapSession(): StoredSession? = session
    override suspend fun currentStoredSession(): StoredSession? = session

    override suspend fun beginLogin(provider: SchoolProvider, schoolURL: String, username: String, password: String): SchoolLoginStep {
        session = StoredSession(
            accessToken = "demo-access",
            refreshToken = "demo-refresh",
            tokenType = "Bearer",
            expiresAtEpochMillis = System.currentTimeMillis() + 86_400_000,
            baseURL = schoolURL.ifBlank { "https://demo.gradey.app" },
            provider = provider,
        )
        return SchoolLoginStep.SignedIn(session!!)
    }

    override suspend fun completeEduPageTwoFactor(code: String): SchoolLoginStep = SchoolLoginStep.SignedIn(session!!)
    override suspend fun completeApprovedEduPageTwoFactor(): SchoolLoginStep = SchoolLoginStep.SignedIn(session!!)
    override suspend fun selectEduPageStudent(studentID: String): StoredSession = session ?: error("Not signed in")
    override suspend fun switchEduPageStudent(studentID: String) = Unit
    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession = session.also { this.session = it }
    override suspend fun logout() { session = null }
    override suspend fun loadCachedDashboard(): DashboardData = com.bukovinafilip.gradey.domain.DemoData.fixture.dashboard
    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData = com.bukovinafilip.gradey.domain.DemoData.fixture.dashboard
    override suspend fun loadAbsence(forceRefresh: Boolean): AbsenceResponse = com.bukovinafilip.gradey.domain.DemoData.absenceResponse
    override suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek =
        com.bukovinafilip.gradey.domain.DemoData.timetableFor(weekContaining)
    override suspend fun loadTimetable(weekContaining: String): TimetableWeek =
        com.bukovinafilip.gradey.domain.DemoData.timetableFor(weekContaining)
    override suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double? =
        com.bukovinafilip.gradey.domain.GradeMath.parseMarkValue(markText)?.let {
            com.bukovinafilip.gradey.domain.GradeMath.theoreticalAverage(subject.marks, subject.averageText, it, weight)
        }
}

class MockGradeyAuthRepository : GradeyAuthRepository {
    private var session: GradeyAuthSession? = GradeyAuthSession(
        accessToken = "demo-gradey-access",
        account = GradeyAccount(id = "demo-account", email = "demo@gradey.app", fullName = "Demo Student"),
    )

    override suspend fun bootstrapSession(): GradeyAuthSession? = session
    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?): GradeyAuthSession =
        GradeyAuthSession("demo-gradey-access", account = GradeyAccount("demo-account", fullName = fullName ?: "Demo Student")).also { session = it }

    override suspend fun signOut() {
        session = null
    }
}

class MockLinkedAccountRepository : LinkedAccountRepository {
    private val accounts = MutableStateFlow(
        listOf(
            LinkedSchoolAccount("demo-linked", SchoolProvider.BAKALARI, "Demo school account", "Gradey Demo School"),
        ),
    )

    override suspend fun localAccounts(): List<LinkedSchoolAccount> = accounts.value
    override suspend fun linkSchoolAccount(session: StoredSession, displayName: String): LinkedSchoolAccount {
        val account = LinkedSchoolAccount("linked-${System.currentTimeMillis()}", session.provider, displayName, session.linkedAccountSchoolName)
        accounts.update { it + account }
        return account
    }

    override suspend fun unlinkAccount(accountID: String) {
        accounts.update { it.filterNot { account -> account.id == accountID } }
    }

    override suspend fun clearLocalAccounts() {
        accounts.value = emptyList()
    }
}

class MockGradeyHistoryRepository : GradeyHistoryRepository {
    override suspend fun gradeHistory(accountID: String?): List<GradeHistoryTrend> = listOf(
        GradeHistoryTrend("math", "Mathematics", averageDelta = -0.62, markCountDelta = 2),
        GradeHistoryTrend("czech", "Czech Language", averageDelta = 0.4, markCountDelta = 1),
    )
}

class MockDevicePushTokenClient : DevicePushTokenClient {
    val registeredTokens = mutableListOf<String>()
    var preferences: NotificationPreferences = NotificationPreferences.Default

    override suspend fun registerDeviceToken(token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) {
        registeredTokens += token
    }

    override suspend fun updateNotificationPreferences(preferences: NotificationPreferences, gradeySession: GradeyAuthSession) {
        this.preferences = preferences
    }
}

class MockStravaCZRepository : StravaCZRepository {
    private var session: StravaCZStoredSession? = StravaCZStoredSession("demo-strava", "0000", "demo", "100.00")

    override suspend fun bootstrapSession(): StravaCZStoredSession? = session
    override suspend fun loadCachedMenu(): StravaCZMenu = com.bukovinafilip.gradey.domain.DemoData.stravaMenu
    override suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession =
        StravaCZStoredSession("demo-strava", canteenNumber, username, "100.00").also { session = it }

    override suspend fun loadMenu(forceRefresh: Boolean): Pair<StravaCZStoredSession, StravaCZMenu> =
        (session ?: login("0000", "demo", "demo")) to com.bukovinafilip.gradey.domain.DemoData.stravaMenu

    override suspend fun setMeal(meal: StravaCZMeal, ordered: Boolean): Pair<StravaCZStoredSession, StravaCZMenu> =
        loadMenu(forceRefresh = true)

    override suspend fun logout() {
        session = null
    }
}
