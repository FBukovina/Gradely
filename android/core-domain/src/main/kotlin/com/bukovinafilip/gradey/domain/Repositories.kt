package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.EduPageSessionData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.SchoolStudentProfile
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek

sealed interface SchoolLoginStep {
    data class SignedIn(val session: StoredSession) : SchoolLoginStep
    data class TwoFactor(val prompt: EduPageTwoFactorPrompt = EduPageTwoFactorPrompt()) : SchoolLoginStep
    data class StudentSelection(val students: List<SchoolStudentProfile>) : SchoolLoginStep
}

data class EduPageTwoFactorPrompt(
    val supportsCode: Boolean = true,
    val supportsDeviceApproval: Boolean = true,
)

interface BakalariClient {
    suspend fun login(baseURL: String, username: String, password: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun refreshToken(baseURL: String, refreshToken: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse
    suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse
    suspend fun fetchUser(baseURL: String, accessToken: String): com.bukovinafilip.gradey.model.UserResponse
    suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): com.bukovinafilip.gradey.model.TimetableResponse
    suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject
}

interface EduPageClient {
    suspend fun beginLogin(baseURL: String, username: String, password: String): SchoolLoginStep
    suspend fun completeTwoFactor(code: String): SchoolLoginStep
    suspend fun completeApprovedTwoFactor(): SchoolLoginStep
    suspend fun isTwoFactorConfirmed(): Boolean
    suspend fun resendTwoFactorNotification()
    suspend fun selectStudent(studentID: String): EduPageSessionData
    suspend fun switchStudent(studentID: String, session: EduPageSessionData, baseURL: String): EduPageSessionData
    suspend fun restore(stored: EduPageSessionData, baseURL: String): EduPageSessionData
    suspend fun fetchMarks(baseURL: String, session: EduPageSessionData): MarksResponse
    suspend fun fetchAbsences(baseURL: String, session: EduPageSessionData): AbsenceResponse
    suspend fun fetchUser(baseURL: String, session: EduPageSessionData): com.bukovinafilip.gradey.model.UserResponse
    suspend fun fetchTimetable(baseURL: String, session: EduPageSessionData, weekStart: String): com.bukovinafilip.gradey.model.TimetableResponse
}

interface SchoolRepository {
    suspend fun bootstrapSession(): StoredSession?
    suspend fun currentStoredSession(): StoredSession?
    suspend fun beginLogin(provider: SchoolProvider, schoolURL: String, username: String, password: String): SchoolLoginStep
    suspend fun completeEduPageTwoFactor(code: String): SchoolLoginStep
    suspend fun completeApprovedEduPageTwoFactor(): SchoolLoginStep
    suspend fun selectEduPageStudent(studentID: String): StoredSession
    suspend fun switchEduPageStudent(studentID: String)
    suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession
    suspend fun logout()
    suspend fun loadCachedDashboard(): DashboardData?
    suspend fun loadDashboard(forceRefresh: Boolean = false): DashboardData
    suspend fun loadAbsence(forceRefresh: Boolean = false): AbsenceResponse
    suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek?
    suspend fun loadTimetable(weekContaining: String): TimetableWeek
    suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double?
}

interface GradeyAuthRepository {
    suspend fun bootstrapSession(): GradeyAuthSession?
    suspend fun signInWithGoogle(idToken: String, accessToken: String? = null, fullName: String? = null): GradeyAuthSession
    suspend fun signOut()
}

interface LinkedAccountRepository {
    suspend fun localAccounts(): List<LinkedSchoolAccount>
    suspend fun linkSchoolAccount(session: StoredSession, displayName: String): LinkedSchoolAccount
    suspend fun unlinkAccount(accountID: String)
    suspend fun clearLocalAccounts()
}

interface GradeyHistoryRepository {
    suspend fun gradeHistory(accountID: String?): List<GradeHistoryTrend>
}

data class GradeHistoryTrend(
    val subjectID: String,
    val subjectName: String,
    val averageDelta: Double,
    val markCountDelta: Int,
)

interface DevicePushTokenClient {
    suspend fun registerDeviceToken(token: String, platform: String, environment: String, gradeySession: GradeyAuthSession)
    suspend fun updateNotificationPreferences(preferences: NotificationPreferences, gradeySession: GradeyAuthSession)
}

interface StravaCZRepository {
    suspend fun bootstrapSession(): StravaCZStoredSession?
    suspend fun loadCachedMenu(): StravaCZMenu?
    suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession
    suspend fun loadMenu(forceRefresh: Boolean = false): Pair<StravaCZStoredSession, StravaCZMenu>
    suspend fun setMeal(meal: StravaCZMeal, ordered: Boolean): Pair<StravaCZStoredSession, StravaCZMenu>
    suspend fun logout()
}

