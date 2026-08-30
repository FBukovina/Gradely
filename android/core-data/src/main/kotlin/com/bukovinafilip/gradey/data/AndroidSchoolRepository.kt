package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.SchoolURLNormalizer
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TimetableMapper
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StoredSchoolSessionEnvelope
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.BakalariApiException
import kotlinx.coroutines.async
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

class AndroidSchoolRepository(
    private val bakalariClient: BakalariClient,
    private val sessionStore: SchoolSessionStorage,
    private val cache: RoomGradeyCache,
    private val dateProvider: () -> LocalDate = { TimetableDates.today() },
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

    override suspend fun restoreSession(session: StoredSession): StoredSession {
        sessionStore.save(session)
        return session
    }

    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession {
        val existing = sessionStore.load()
        if (
            existing != null &&
            existing.provider == session.provider &&
            existing.baseURL == session.baseURL &&
            existing.linkedAccountID != null &&
            existing.linkedAccountID == session.linkedAccountID
        ) {
            val preserved = existing.copy(
                bakalari = existing.bakalari ?: session.bakalari,
                linkedAccountID = session.linkedAccountID,
                linkedAccountDisplayName = session.linkedAccountDisplayName,
                linkedAccountSchoolName = session.linkedAccountSchoolName,
            )
            sessionStore.save(preserved)
            return preserved
        }

        val credentials = session.bakalari
        val activated = if (credentials != null) {
            val response = bakalariClient.login(
                session.baseURL,
                credentials.username,
                credentials.password,
            )
            session.copy(
                accessToken = response.accessToken,
                refreshToken = response.refreshToken,
                tokenType = response.tokenType,
                expiresAtEpochMillis = System.currentTimeMillis() + response.expiresIn * 1_000L,
            )
        } else {
            session
        }
        sessionStore.save(activated)
        return activated
    }

    override suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession {
        val current = sessionStore.load() ?: throw SchoolSessionExpiredException()
        require(account.provider == LinkedAccountProvider.from(current.provider)) {
            "The linked account provider does not match the current school session."
        }
        val associated = current.copy(
            linkedAccountID = account.id,
            linkedAccountDisplayName = account.displayName,
            linkedAccountSchoolName = account.schoolName,
        )
        sessionStore.save(associated)
        return associated
    }

    override suspend fun disassociateCurrentSession(accountID: String): StoredSession? {
        val current = sessionStore.load() ?: return null
        if (current.linkedAccountID != accountID) return current
        val local = current.copy(
            linkedAccountID = null,
            linkedAccountDisplayName = null,
            linkedAccountSchoolName = null,
        )
        sessionStore.save(local)
        return local
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
        val cachedDashboard = cache.loadDashboard(session.cacheScope)
        val cachedAbsence = cache.loadAbsence(session.cacheScope)

        val marks = fetchMarks(session)
        cache.saveMarks(session.cacheScope, marks)
        val absence = async { optionalAbsence(session) }
        val user = async { optionalUser(session) }
        val absenceResult = absence.await()
        if (absenceResult != null) cache.saveAbsence(session.cacheScope, absenceResult)
        val data = DashboardData(
            marksResponse = marks,
            absencesPerSubject = absenceResult?.absencesPerSubject
                ?: cachedAbsence?.absencesPerSubject
                ?: cachedDashboard?.absencesPerSubject.orEmpty(),
            user = user.await()?.resolvedFor(session) ?: cachedDashboard?.user,
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
        try {
            cache.updateNextLessonSnapshot(week)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Widget publication is best-effort and must not hide a successful timetable refresh.
        }
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
        val session = sessionStore.load() ?: throw SchoolSessionExpiredException()
        if (!session.isExpired()) return session
        return refreshMutex.withLock {
            val latest = sessionStore.load() ?: throw SchoolSessionExpiredException()
            if (!latest.isExpired()) latest else refreshBakalari(latest)
        }
    }

    private suspend fun refreshBakalari(session: StoredSession): StoredSession {
        val response = try {
            bakalariClient.refreshToken(session.baseURL, session.refreshToken)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isRefreshTokenRejected(error)) throw error
            val credentials = session.bakalari ?: expireSession(error)
            try {
                bakalariClient.login(session.baseURL, credentials.username, credentials.password)
            } catch (loginError: CancellationException) {
                throw loginError
            } catch (loginError: Throwable) {
                if (isRefreshTokenRejected(loginError)) expireSession(loginError)
                throw loginError
            }
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
        try {
            block(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isAccessTokenRejected(error)) throw error
            val refreshed = refreshMutex.withLock {
                val latest = sessionStore.load() ?: throw SchoolSessionExpiredException()
                if (latest.accessToken != session.accessToken && !latest.isExpired()) latest else refreshBakalari(latest)
            }
            block(refreshed)
        }

    private fun expireSession(cause: Throwable): Nothing {
        sessionStore.clear()
        throw SchoolSessionExpiredException(cause)
    }

    private suspend fun optionalAbsence(session: StoredSession): AbsenceResponse? =
        try {
            fetchAbsence(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
            throw error
        } catch (_: Throwable) {
            null
        }

    private suspend fun optionalUser(session: StoredSession): UserResponse? =
        try {
            fetchUser(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
            throw error
        } catch (_: Throwable) {
            null
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
        displaySchoolName?.let { resolved ->
            if (resolved == schoolName) this else copy(schoolName = resolved)
        } ?: copy(schoolName = session.linkedAccountSchoolName)
}

interface SchoolSessionStorage {
    fun load(): StoredSession?
    fun save(session: StoredSession)
    fun clear()
}

internal interface SchoolSessionValueStore {
    fun loadCurrent(): StoredSchoolSessionEnvelope?
    fun loadLegacy(): StoredSession?
    fun saveCurrent(envelope: StoredSchoolSessionEnvelope)
    fun clearCurrent()
    fun clearLegacy()
}

private class EncryptedSchoolSessionValueStore(
    private val secureJsonStore: SecureJsonStore,
) : SchoolSessionValueStore {
    override fun loadCurrent(): StoredSchoolSessionEnvelope? =
        secureJsonStore.loadOrClearInvalid(CURRENT_KEY, StoredSchoolSessionEnvelope.serializer())

    override fun loadLegacy(): StoredSession? =
        secureJsonStore.loadOrClearInvalid(LEGACY_KEY, StoredSession.serializer())

    override fun saveCurrent(envelope: StoredSchoolSessionEnvelope) =
        secureJsonStore.save(CURRENT_KEY, envelope, StoredSchoolSessionEnvelope.serializer())

    override fun clearCurrent() = secureJsonStore.clear(CURRENT_KEY)
    override fun clearLegacy() = secureJsonStore.clear(LEGACY_KEY)

    private companion object {
        const val CURRENT_KEY = "school.session.v2"
        const val LEGACY_KEY = "school.session.v1"
    }
}

class SchoolSessionStore internal constructor(
    private val valueStore: SchoolSessionValueStore,
) : SchoolSessionStorage {
    constructor(secureJsonStore: SecureJsonStore) : this(EncryptedSchoolSessionValueStore(secureJsonStore))

    override fun load(): StoredSession? {
        valueStore.loadCurrent()?.let { envelope ->
            if (envelope.formatVersion == CURRENT_FORMAT_VERSION) return envelope.session
            valueStore.clearCurrent()
            return null
        }

        val legacy = valueStore.loadLegacy() ?: return null
        save(legacy)
        valueStore.clearLegacy()
        return legacy
    }

    override fun save(session: StoredSession) {
        valueStore.saveCurrent(StoredSchoolSessionEnvelope(CURRENT_FORMAT_VERSION, session))
        valueStore.clearLegacy()
    }

    override fun clear() {
        valueStore.clearCurrent()
        valueStore.clearLegacy()
    }

    private companion object {
        const val CURRENT_FORMAT_VERSION = 2
    }
}
