package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.SchoolURLNormalizer
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TimetableMapper
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.BakalariApiException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

class AndroidSchoolRepository(
    private val bakalariClient: BakalariClient,
    private val sessionStore: SchoolSessionStorage,
    private val cache: RoomGradeyCache,
    private val dateProvider: () -> LocalDate = LocalDate::now,
) : SchoolRepository {
    private val refreshMutex = Mutex()

    override suspend fun bootstrapSession(): StoredSession? = sessionStore.load()

    override suspend fun currentStoredSession(): StoredSession? = sessionStore.load()

    override suspend fun login(schoolURL: String, username: String, password: String): StoredSession {
        require(username.trim().isNotEmpty() && password.isNotEmpty()) { "Missing username or password." }
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
        return session
    }

    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession {
        sessionStore.save(session)
        return session
    }

    override suspend fun logout() {
        sessionStore.load()?.let { cache.clearSchool(it.cacheScope) }
        cache.clearNextLessonSnapshot()
        sessionStore.clear()
    }

    override suspend fun loadCachedDashboard(): DashboardData? =
        sessionStore.load()?.let { cache.loadDashboard(it.cacheScope) }

    override suspend fun loadCachedAbsence(): AbsenceResponse? =
        sessionStore.load()?.let { cache.loadAbsence(it.cacheScope) }

    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData = coroutineScope {
        val session = validSession()

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
        val predicted = withBakalariRetry(session) { current ->
            bakalariClient.predictSubject(current.baseURL, current.accessToken, subject, markText, weight)
        }
        return GradeMath.parseAverageText(predicted.averageText)
    }

    private suspend fun validSession(): StoredSession {
        val session = sessionStore.load() ?: error("Not logged in.")
        if (!session.isExpired()) return session
        return refreshMutex.withLock {
            val latest = sessionStore.load() ?: error("Not logged in.")
            if (!latest.isExpired()) latest else refreshBakalari(latest)
        }
    }

    private suspend fun refreshBakalari(session: StoredSession): StoredSession {
        val response = try {
            bakalariClient.refreshToken(session.baseURL, session.refreshToken)
        } catch (error: Throwable) {
            if (!isRefreshTokenRejected(error)) throw error
            val credentials = session.bakalari ?: throw error
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
            if (!isAccessTokenRejected(it)) throw it
            val refreshed = refreshMutex.withLock {
                val latest = sessionStore.load() ?: session
                if (latest.accessToken != session.accessToken && !latest.isExpired()) latest else refreshBakalari(latest)
            }
            block(refreshed)
        }

    private fun isRefreshTokenRejected(error: Throwable): Boolean =
        error is BakalariApiException && (error.statusCode == 400 || error.statusCode == 401)

    private fun isAccessTokenRejected(error: Throwable): Boolean =
        error is BakalariApiException && error.statusCode == 401

    private suspend fun fetchMarks(session: StoredSession) =
        withBakalariRetry(session) { bakalariClient.fetchMarks(it.baseURL, it.accessToken) }

    private suspend fun fetchAbsence(session: StoredSession) =
        withBakalariRetry(session) { bakalariClient.fetchAbsences(it.baseURL, it.accessToken) }

    private suspend fun fetchUser(session: StoredSession) =
        withBakalariRetry(session) { bakalariClient.fetchUser(it.baseURL, it.accessToken) }

    private suspend fun fetchTimetable(session: StoredSession, weekStart: String) =
        withBakalariRetry(session) { bakalariClient.fetchTimetable(it.baseURL, it.accessToken, weekStart) }

    private fun UserResponse.resolvedFor(session: StoredSession): UserResponse =
        if (schoolName != null) this else copy(schoolName = session.linkedAccountSchoolName)
}

interface SchoolSessionStorage {
    fun load(): StoredSession?
    fun save(session: StoredSession)
    fun clear()
}

class SchoolSessionStore(
    private val secureJsonStore: SecureJsonStore,
) : SchoolSessionStorage {
    override fun load(): StoredSession? = secureJsonStore.loadOrClearInvalid(KEY, StoredSession.serializer())
    override fun save(session: StoredSession) = secureJsonStore.save(KEY, session, StoredSession.serializer())
    override fun clear() = secureJsonStore.clear(KEY)

    private companion object {
        const val KEY = "school.session.v1"
    }
}
