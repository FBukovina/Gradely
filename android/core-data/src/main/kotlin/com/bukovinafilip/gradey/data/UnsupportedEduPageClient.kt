package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.EduPageClient
import com.bukovinafilip.gradey.domain.SchoolLoginStep
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.EduPageSessionData
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.UserResponse

class UnsupportedEduPageClient : EduPageClient {
    override suspend fun beginLogin(baseURL: String, username: String, password: String): SchoolLoginStep =
        throw UnsupportedOperationException("EduPage live client is scaffolded behind this interface.")

    override suspend fun completeTwoFactor(code: String): SchoolLoginStep =
        throw UnsupportedOperationException("EduPage live client is scaffolded behind this interface.")

    override suspend fun completeApprovedTwoFactor(): SchoolLoginStep =
        throw UnsupportedOperationException("EduPage live client is scaffolded behind this interface.")

    override suspend fun isTwoFactorConfirmed(): Boolean = false
    override suspend fun resendTwoFactorNotification() = Unit
    override suspend fun selectStudent(studentID: String): EduPageSessionData =
        throw UnsupportedOperationException("EduPage live client is scaffolded behind this interface.")

    override suspend fun switchStudent(studentID: String, session: EduPageSessionData, baseURL: String): EduPageSessionData = session
    override suspend fun restore(stored: EduPageSessionData, baseURL: String): EduPageSessionData = stored
    override suspend fun fetchMarks(baseURL: String, session: EduPageSessionData): MarksResponse = MarksResponse()
    override suspend fun fetchAbsences(baseURL: String, session: EduPageSessionData): AbsenceResponse = AbsenceResponse()
    override suspend fun fetchUser(baseURL: String, session: EduPageSessionData): UserResponse =
        UserResponse(session.username, session.schoolName, session.activeStudent?.className, session.userID)

    override suspend fun fetchTimetable(baseURL: String, session: EduPageSessionData, weekStart: String): TimetableResponse = TimetableResponse()
}

