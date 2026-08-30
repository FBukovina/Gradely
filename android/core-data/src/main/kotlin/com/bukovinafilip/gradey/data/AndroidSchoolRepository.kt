package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.EduPageClient
import com.bukovinafilip.gradey.domain.EduPageURLNormalizer
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.SchoolLoginStep
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.SchoolURLNormalizer
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TimetableMapper
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.EduPageSessionData
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

class AndroidSchoolRepository(
    private val bakalariClient: BakalariClient,
    private val eduPageClient: EduPageClient,
    private val sessionStore: SchoolSessionStore,
    private val cache: RoomGradeyCache,
    private val dateProvider: () -> LocalDate = LocalDate::now,
) : SchoolRepository {
    private val refreshMutex = Mutex()
    private var pendingEduPageBaseURL: String? = null

    override suspend fun bootstrapSession(): StoredSession? = sessionStore.load()

    override suspend fun currentStoredSession(): StoredSession? = sessionStore.load()

    override suspend fun beginLogin(provider: SchoolProvider, schoolURL: String, username: String, password: String): SchoolLoginStep {
        require(username.trim().isNotEmpty() && password.isNotEmpty()) { "Missing username or password." }
        return when (provider) {
            SchoolProvider.BAKALARI -> {
                val baseURL = SchoolURLNormalizer.normalizedBaseURL(schoolURL)
                val trimmedUsername = username.trim()
                val response = bakalariClient.login(baseURL, trimmedUsername, password)
                val session = StoredSession(
                    accessToken = response.accessToken,
                    refreshToken = response.refreshToken,
                    tokenType = response.tokenType,
                    expiresAtEpochMillis = System.currentTimeMillis() + response.expiresIn * 1000L,
                    baseURL = baseURL,
                    provider = SchoolProvider.BAKALARI,
                    bakalari = BakalariCredentials(trimmedUsername, password),
                )
                sessionStore.save(session)
                SchoolLoginStep.SignedIn(session)
            }

            SchoolProvider.EDU_PAGE -> {
                val baseURL = EduPageURLNormalizer.normalizedBaseURL(schoolURL)
                pendingEduPageBaseURL = baseURL
                eduPageClient.beginLogin(baseURL, username.trim(), password)
            }
        }
    }

    override suspend fun completeEduPageTwoFactor(code: String): SchoolLoginStep =
        persistEduPageStep(eduPageClient.completeTwoFactor(code))

    override suspend fun completeApprovedEduPageTwoFactor(): SchoolLoginStep =
        persistEduPageStep(eduPageClient.completeApprovedTwoFactor())

    override suspend fun selectEduPageStudent(studentID: String): StoredSession {
        val baseURL = pendingEduPageBaseURL ?: error("No pending EduPage login.")
        val data = eduPageClient.selectStudent(studentID)
        return persistEduPageSession(data, baseURL)
    }

    override suspend fun switchEduPageStudent(studentID: String) {
        val current = sessionStore.load() ?: error("Not signed in.")
        require(current.provider == SchoolProvider.EDU_PAGE)
        val data = current.eduPage ?: error("Missing EduPage session.")
        val updatedData = eduPageClient.switchStudent(studentID, data, current.baseURL)
        val updated = current.copy(accessToken = updatedData.sessionID, eduPage = updatedData)
        cache.clearSchool(current.cacheScope)
        sessionStore.save(updated)
    }

    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession {
        sessionStore.save(session)
        return session
    }

    override suspend fun logout() {
        sessionStore.clear()
    }

    override suspend fun loadCachedDashboard(): DashboardData? =
        sessionStore.load()?.let { cache.loadDashboard(it.cacheScope) }

    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData = coroutineScope {
        val session = validSession()
        if (forceRefresh) cache.clearSchool(session.cacheScope)

        val marks = fetchMarks(session)
        cache.saveMarks(session.cacheScope, marks)
        val absence = async { runCatching { fetchAbsence(session) }.getOrNull() }
        val user = async { runCatching { fetchUser(session) }.getOrNull() }
        val absenceResult = absence.await()
        if (absenceResult != null) cache.saveAbsence(session.cacheScope, absenceResult)
        val data = DashboardData(
            marksResponse = marks,
            absencesPerSubject = absenceResult?.absencesPerSubject.orEmpty(),
            user = user.await()?.resolvedFor(session),
        )
        cache.saveDashboard(session.cacheScope, data)
        data
    }

    override suspend fun loadAbsence(forceRefresh: Boolean): AbsenceResponse {
        val session = validSession()
        if (!forceRefresh) cache.loadAbsence(session.cacheScope)?.let { return it }
        val response = fetchAbsence(session)
        cache.saveAbsence(session.cacheScope, response)
        return response
    }

    override suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek? {
        val session = sessionStore.load() ?: return null
        val monday = TimetableDates.apiDateString(TimetableDates.monday(LocalDate.parse(weekContaining)))
        return cache.loadTimetable(session.cacheScope, monday)
    }

    override suspend fun loadTimetable(weekContaining: String): TimetableWeek {
        val session = validSession()
        val monday = TimetableDates.apiDateString(TimetableDates.monday(LocalDate.parse(weekContaining)))
        val response = fetchTimetable(session, monday)
        cache.saveRawTimetable(session.cacheScope, monday, response)
        val week = TimetableMapper.makeWeek(response, monday, TimetableDates.apiDateString(dateProvider()))
        cache.saveTimetable(session.cacheScope, monday, week)
        return week
    }

    override suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double? {
        val session = validSession()
        if (!session.provider.capabilities.supportsRemoteWhatIf) {
            val value = GradeMath.parseMarkValue(markText) ?: return null
            return GradeMath.theoreticalAverage(subject.marks, subject.averageText, value, weight)
        }
        val predicted = withBakalariRetry(session) { current ->
            bakalariClient.predictSubject(current.baseURL, current.accessToken, subject, markText, weight)
        }
        return GradeMath.parseAverageText(predicted.averageText)
    }

    private suspend fun persistEduPageStep(step: SchoolLoginStep): SchoolLoginStep = when (step) {
        is SchoolLoginStep.SignedIn -> {
            sessionStore.save(step.session)
            step
        }
        else -> step
    }

    private suspend fun persistEduPageSession(data: EduPageSessionData, baseURL: String): StoredSession {
        val session = StoredSession(
            accessToken = data.sessionID,
            refreshToken = "",
            tokenType = "Cookie",
            expiresAtEpochMillis = Long.MAX_VALUE,
            baseURL = baseURL,
            provider = SchoolProvider.EDU_PAGE,
            eduPage = data,
        )
        sessionStore.save(session)
        pendingEduPageBaseURL = null
        return session
    }

    private suspend fun validSession(): StoredSession {
        val session = sessionStore.load() ?: error("Not logged in.")
        if (session.provider != SchoolProvider.BAKALARI || !session.isExpired()) return session
        return refreshMutex.withLock {
            val latest = sessionStore.load() ?: error("Not logged in.")
            if (latest.provider != SchoolProvider.BAKALARI || !latest.isExpired()) latest else refreshBakalari(latest)
        }
    }

    private suspend fun refreshBakalari(session: StoredSession): StoredSession {
        val response = runCatching {
            bakalariClient.refreshToken(session.baseURL, session.refreshToken)
        }.getOrElse {
            val credentials = session.bakalari ?: throw it
            bakalariClient.login(session.baseURL, credentials.username, credentials.password)
        }
        val updated = session.copy(
            accessToken = response.accessToken,
            refreshToken = response.refreshToken,
            tokenType = response.tokenType,
            expiresAtEpochMillis = System.currentTimeMillis() + response.expiresIn * 1000L,
        )
        sessionStore.save(updated)
        return updated
    }

    private suspend fun <T> withBakalariRetry(session: StoredSession, block: suspend (StoredSession) -> T): T =
        runCatching { block(session) }.getOrElse {
            if (session.provider != SchoolProvider.BAKALARI) throw it
            val refreshed = refreshMutex.withLock { refreshBakalari(sessionStore.load() ?: session) }
            block(refreshed)
        }

    private suspend fun fetchMarks(session: StoredSession) = when (session.provider) {
        SchoolProvider.BAKALARI -> withBakalariRetry(session) { bakalariClient.fetchMarks(it.baseURL, it.accessToken) }
        SchoolProvider.EDU_PAGE -> eduPageClient.fetchMarks(session.baseURL, session.eduPage ?: error("Missing EduPage session."))
    }

    private suspend fun fetchAbsence(session: StoredSession) = when (session.provider) {
        SchoolProvider.BAKALARI -> withBakalariRetry(session) { bakalariClient.fetchAbsences(it.baseURL, it.accessToken) }
        SchoolProvider.EDU_PAGE -> eduPageClient.fetchAbsences(session.baseURL, session.eduPage ?: error("Missing EduPage session."))
    }

    private suspend fun fetchUser(session: StoredSession) = when (session.provider) {
        SchoolProvider.BAKALARI -> withBakalariRetry(session) { bakalariClient.fetchUser(it.baseURL, it.accessToken) }
        SchoolProvider.EDU_PAGE -> eduPageClient.fetchUser(session.baseURL, session.eduPage ?: error("Missing EduPage session."))
    }

    private suspend fun fetchTimetable(session: StoredSession, weekStart: String) = when (session.provider) {
        SchoolProvider.BAKALARI -> withBakalariRetry(session) { bakalariClient.fetchTimetable(it.baseURL, it.accessToken, weekStart) }
        SchoolProvider.EDU_PAGE -> eduPageClient.fetchTimetable(session.baseURL, session.eduPage ?: error("Missing EduPage session."), weekStart)
    }

    private fun UserResponse.resolvedFor(session: StoredSession): UserResponse =
        if (schoolName != null) this else copy(schoolName = session.linkedAccountSchoolName)
}

class SchoolSessionStore(
    private val secureJsonStore: SecureJsonStore,
) {
    fun load(): StoredSession? = secureJsonStore.load(KEY, StoredSession.serializer())
    fun save(session: StoredSession) = secureJsonStore.save(KEY, session, StoredSession.serializer())
    fun clear() = secureJsonStore.clear(KEY)

    private companion object {
        const val KEY = "school.session.v1"
    }
}

