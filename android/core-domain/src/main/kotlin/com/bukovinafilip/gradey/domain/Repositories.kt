package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.CachedSchoolDirectory
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.GradeyAccountSettingsSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccountActivation
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.SchoolDirectoryMunicipality
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek

interface BakalariClient {
    suspend fun login(baseURL: String, username: String, password: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun refreshToken(baseURL: String, refreshToken: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse
    suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse
    suspend fun fetchUser(baseURL: String, accessToken: String): com.bukovinafilip.gradey.model.UserResponse
    suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): com.bukovinafilip.gradey.model.TimetableResponse
    suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject
}

interface SchoolDirectoryClient {
    suspend fun fetchMunicipalities(): List<SchoolDirectoryMunicipality>
    suspend fun fetchSchools(municipalityName: String): List<SchoolDirectorySchool>
}

interface SchoolDirectoryRepository {
    suspend fun loadCachedDirectory(): CachedSchoolDirectory?
    suspend fun refreshDirectory(): List<SchoolDirectorySchool>
}

interface SchoolRepository {
    suspend fun bootstrapSession(): StoredSession?
    suspend fun currentStoredSession(): StoredSession?
    suspend fun login(schoolURL: String, username: String, password: String): StoredSession
    suspend fun restoreSession(session: StoredSession): StoredSession
    suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession
    suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession
    suspend fun disassociateCurrentSession(accountID: String): StoredSession?
    suspend fun logout()
    suspend fun loadCachedDashboard(): DashboardData?
    suspend fun loadCachedAbsence(): AbsenceResponse?
    suspend fun loadDashboard(forceRefresh: Boolean = false): DashboardData
    suspend fun loadAbsence(forceRefresh: Boolean = false): AbsenceResponse
    suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek?
    suspend fun loadTimetable(weekContaining: String): TimetableWeek
    suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double?
}

class SchoolSessionExpiredException(
    cause: Throwable? = null,
) : IllegalStateException(
    "Your Bakaláři session expired. Please reconnect your school account.",
    cause,
)

class GradeySessionExpiredException(
    cause: Throwable? = null,
) : IllegalStateException(
    "Your Gradey ID session expired. Please sign in again.",
    cause,
)

interface GradeyAuthRepository {
    suspend fun bootstrapSession(): GradeyAuthSession?
    suspend fun validSession(): GradeyAuthSession
    suspend fun refreshAccount(): GradeyAccount
    suspend fun updateFullName(fullName: String): GradeyAccount
    suspend fun signInWithGoogle(idToken: String, accessToken: String? = null, fullName: String? = null): GradeyAuthSession
    suspend fun signOut()
}

interface LinkedAccountRepository {
    suspend fun localAccounts(): List<LinkedSchoolAccount>
    suspend fun refreshAccounts(): GradeyAccountSettingsSnapshot
    suspend fun linkSchoolAccount(session: StoredSession, user: com.bukovinafilip.gradey.model.UserResponse?): LinkedSchoolAccount
    suspend fun activateSchoolAccount(accountID: String): LinkedSchoolAccountActivation
    suspend fun reconnectSchoolAccount(
        accountID: String,
        session: StoredSession,
        user: com.bukovinafilip.gradey.model.UserResponse?,
    ): LinkedSchoolAccount
    suspend fun updateNotificationsEnabled(accountID: String, enabled: Boolean): LinkedSchoolAccount
    suspend fun unlinkAccount(accountID: String)
    suspend fun clearLocalAccounts()
}

interface GradeyHistoryRepository {
    suspend fun gradeHistory(accountID: String?, days: Int? = 90): GradeHistoryResponse
}

interface DevicePushTokenClient {
    suspend fun registerDeviceToken(token: String, platform: String, environment: String, gradeySession: GradeyAuthSession)
    suspend fun updateNotificationPreferences(preferences: NotificationPreferences, gradeySession: GradeyAuthSession)
}

interface GradeyAIRepository {
    val isConfigured: Boolean

    suspend fun loadStatus(): GradeyAIStatus
    suspend fun acceptConsent(): GradeyAIConsent
}

interface StravaCZRepository {
    suspend fun bootstrapSession(): StravaCZStoredSession?
    suspend fun loadCachedMenu(): StravaCZMenu?
    suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession
    suspend fun loadMenu(forceRefresh: Boolean = false): Pair<StravaCZStoredSession, StravaCZMenu>
    suspend fun setMeal(meal: StravaCZMeal, ordered: Boolean): Pair<StravaCZStoredSession, StravaCZMenu>
    suspend fun logout()
}
