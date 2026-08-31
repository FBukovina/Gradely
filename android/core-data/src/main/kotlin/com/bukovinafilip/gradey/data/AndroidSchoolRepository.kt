package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.AbsenceSubjectFallback
import com.bukovinafilip.gradey.domain.AbsenceLessonCandidate
import com.bukovinafilip.gradey.domain.AbsenceLessonSelections
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolution
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionFailure
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionProgress
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionSource
import com.bukovinafilip.gradey.domain.AbsenceTerms
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
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.BakalariApiException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.time.LocalDate

class AndroidSchoolRepository(
    private val bakalariClient: BakalariClient,
    private val sessionStore: SchoolSessionStorage,
    private val cache: RoomGradeyCache,
    private val dateProvider: () -> LocalDate = { TimetableDates.today() },
    private val timetableFallbackTimeoutMillis: Long = 12_000L,
    private val timetableFallbackBatchSize: Int = 4,
) : SchoolRepository {
    // Token rotation and explicit session changes share one ordering boundary so
    // a late refresh cannot restore a signed-out or previously active account.
    private val sessionMutationMutex = Mutex()

    override suspend fun bootstrapSession(): StoredSession? = sessionStore.load()

    override suspend fun currentStoredSession(): StoredSession? = sessionStore.load()

    override suspend fun login(schoolURL: String, username: String, password: String): StoredSession =
        sessionMutationMutex.withLock {
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
            saveReplacingSchoolScope(session)
            session
        }

    override suspend fun restoreSession(session: StoredSession): StoredSession =
        sessionMutationMutex.withLock {
            saveReplacingSchoolScope(session)
            session
        }

    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession =
        sessionMutationMutex.withLock {
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
                saveReplacingSchoolScope(preserved)
                return@withLock preserved
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
            saveReplacingSchoolScope(activated)
            activated
        }

    override suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession =
        sessionMutationMutex.withLock {
            val current = sessionStore.load() ?: throw SchoolSessionExpiredException()
            require(account.provider == LinkedAccountProvider.from(current.provider)) {
                "The linked account provider does not match the current school session."
            }
            val associated = current.copy(
                linkedAccountID = account.id,
                linkedAccountDisplayName = account.displayName,
                linkedAccountSchoolName = account.schoolName,
            )
            // This only relabels the same provider session; its widget data still belongs to this student.
            sessionStore.save(associated)
            associated
        }

    override suspend fun disassociateCurrentSession(accountID: String): StoredSession? =
        sessionMutationMutex.withLock {
            val current = sessionStore.load() ?: return@withLock null
            if (current.linkedAccountID != accountID) return@withLock current
            val local = current.copy(
                linkedAccountID = null,
                linkedAccountDisplayName = null,
                linkedAccountSchoolName = null,
            )
            // Detaching cloud metadata does not change the underlying local student.
            sessionStore.save(local)
            local
        }

    override suspend fun logout() = sessionMutationMutex.withLock {
        sessionStore.clear()
        clearLocalCaches()
    }

    override suspend fun clearLocalCaches() = cache.clearAllSchoolData()

    override suspend fun loadCachedDashboard(): DashboardData? =
        sessionStore.load()?.let { cache.loadDashboard(it.cacheScope) }

    override suspend fun loadCachedAbsence(): AbsenceResponse? =
        sessionStore.load()?.let { cache.loadAbsence(it.cacheScope) }

    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData = coroutineScope {
        val session = validSession()
        val cachedDashboard = cache.loadDashboard(session.cacheScope)
        val cachedAbsence = cache.loadAbsence(session.cacheScope)

        val marks = fetchMarks(session)
        val absence = async { optionalAbsence(session) }
        val user = async { optionalUser(session) }
        val absenceResult = absence.await()
        val data = DashboardData(
            marksResponse = marks,
            absencesPerSubject = absenceResult?.absencesPerSubject
                ?: cachedAbsence?.absencesPerSubject
                ?: cachedDashboard?.absencesPerSubject.orEmpty(),
            user = user.await()?.resolvedFor(session) ?: cachedDashboard?.user,
        )
        publishForActiveSession(session) {
            cache.saveMarks(session.cacheScope, marks)
            if (absenceResult != null) cache.saveAbsence(session.cacheScope, absenceResult)
            cache.saveDashboard(session.cacheScope, data)
        }
        data
    }

    override suspend fun loadAbsence(forceRefresh: Boolean): AbsenceResponse {
        val session = validSession()
        val response = fetchAbsence(session)
        publishForActiveSession(session) {
            cache.saveAbsence(session.cacheScope, response)
        }
        return response
    }

    override suspend fun resolveAbsenceSubjects(
        response: AbsenceResponse,
        onProgress: suspend (AbsenceSubjectResolutionProgress) -> Unit,
    ): AbsenceSubjectResolution {
        if (response.absencesPerSubject.isNotEmpty()) {
            return AbsenceSubjectResolution(
                subjects = response.absencesPerSubject,
                source = AbsenceSubjectResolutionSource.OFFICIAL,
            )
        }
        if (response.absences.isEmpty()) {
            return AbsenceSubjectResolution(emptyList(), AbsenceSubjectResolutionSource.UNAVAILABLE)
        }

        val session = validSession()
        val term = AbsenceTerms.resolve(response, dateProvider())
        val markSubjects = try {
            cache.loadMarks(session.cacheScope)?.subjects ?: fetchMarks(session).also {
                publishForActiveSession(session) {
                    cache.saveMarks(session.cacheScope, it)
                }
            }.subjects
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            emptyList()
        }
        val timetableLoad = loadTermTimetables(term.weekStarts, session, onProgress)
        if (timetableLoad.responses.isEmpty()) {
            return AbsenceSubjectResolution(
                subjects = emptyList(),
                source = AbsenceSubjectResolutionSource.UNAVAILABLE,
                loadedWeeks = 0,
                totalWeeks = term.weekStarts.size,
                failure = AbsenceSubjectResolutionFailure.NO_USABLE_TIMETABLE,
            )
        }

        val manualSelections = cache.loadAbsenceLessonSelections(session.cacheScope) ?: AbsenceLessonSelections()
        val fallback = AbsenceSubjectFallback.makeResult(
            response = response,
            timetables = timetableLoad.responses,
            markSubjects = markSubjects,
            validDateRange = term.start..term.endInclusive,
            manualSelections = manualSelections,
        )
        val source = when {
            fallback.subjects.isEmpty() -> AbsenceSubjectResolutionSource.UNAVAILABLE
            timetableLoad.failedWeeks > 0 -> AbsenceSubjectResolutionSource.PARTIAL_SYNTHESIZED
            else -> AbsenceSubjectResolutionSource.SYNTHESIZED
        }
        return AbsenceSubjectResolution(
            subjects = fallback.subjects,
            source = source,
            loadedWeeks = timetableLoad.responses.size,
            totalWeeks = term.weekStarts.size,
            unresolvedPartialDays = fallback.unresolvedPartialDays,
            appliedManualSelectionCount = fallback.appliedManualSelectionCount,
        )
    }

    override suspend fun saveManualAbsenceLessonSelections(selections: Map<String, Set<String>>) {
        val session = validSession()
        publishForActiveSession(session) {
            val current = cache.loadAbsenceLessonSelections(session.cacheScope) ?: AbsenceLessonSelections()
            val merged = current.selectedLessonIDsByDate.toMutableMap()
            selections.forEach { (dateKey, lessonIDs) ->
                merged[dateKey] = lessonIDs.sorted()
            }
            cache.saveAbsenceLessonSelections(
                session.cacheScope,
                AbsenceLessonSelections(merged.toSortedMap()),
            )
        }
    }

    override suspend fun loadAbsencePredictionLessons(on: String): List<AbsenceLessonCandidate> {
        val date = LocalDate.parse(on)
        val session = validSession()
        val weekStart = TimetableDates.apiDateString(TimetableDates.monday(date))
        val timetable = cache.loadRawTimetable(session.cacheScope, weekStart) ?: fetchTimetable(session, weekStart).also {
            publishForActiveSession(session) {
                cache.saveRawTimetable(session.cacheScope, weekStart, it)
            }
        }
        val markSubjects = try {
            cache.loadMarks(session.cacheScope)?.subjects ?: fetchMarks(session).also {
                publishForActiveSession(session) {
                    cache.saveMarks(session.cacheScope, it)
                }
            }.subjects
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            emptyList()
        }
        return AbsenceSubjectFallback.lessonCandidates(date, timetable, markSubjects)
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
        val week = TimetableMapper.makeWeek(response, monday, TimetableDates.apiDateString(dateProvider()))
        publishForActiveSession(session) {
            cache.saveRawTimetable(session.cacheScope, monday, response)
            cache.saveTimetable(session.cacheScope, monday, week)
            try {
                cache.updateNextLessonSnapshot(week)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Widget publication is best-effort and must not hide a successful timetable refresh.
            }
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

    private suspend fun saveReplacingSchoolScope(session: StoredSession) {
        if (sessionStore.load()?.cacheScope != session.cacheScope) {
            cache.clearNextLessonSnapshot()
        }
        sessionStore.save(session)
    }

    private suspend fun <T> publishForActiveSession(
        session: StoredSession,
        publication: suspend () -> T,
    ): T = sessionMutationMutex.withLock {
        val active = sessionStore.load()
        if (active == null || active.cacheScope != session.cacheScope) {
            throw CancellationException("The active school account changed before data publication.")
        }
        publication()
    }

    private suspend fun validSession(): StoredSession {
        val session = sessionStore.load() ?: throw SchoolSessionExpiredException()
        if (!session.isExpired()) return session
        return sessionMutationMutex.withLock {
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
            val refreshed = sessionMutationMutex.withLock {
                val latest = sessionStore.load() ?: throw SchoolSessionExpiredException()
                if (latest.cacheScope != session.cacheScope) {
                    throw CancellationException("The active school account changed during a retry.")
                }
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

    private suspend fun loadTermTimetables(
        weekStarts: List<LocalDate>,
        session: StoredSession,
        onProgress: suspend (AbsenceSubjectResolutionProgress) -> Unit,
    ): TermTimetableLoadResult {
        val loaded = linkedMapOf<LocalDate, TimetableResponse>()
        val missing = mutableListOf<LocalDate>()
        weekStarts.forEach { weekStart ->
            val key = TimetableDates.apiDateString(weekStart)
            cache.loadRawTimetable(session.cacheScope, key)?.let { loaded[weekStart] = it }
                ?: missing.add(weekStart)
        }

        var completedWeeks = loaded.size
        var failedWeeks = 0
        onProgress(AbsenceSubjectResolutionProgress(loaded.size, completedWeeks, weekStarts.size))

        missing.chunked(timetableFallbackBatchSize.coerceAtLeast(1)).forEach { batch ->
            val outcomes = coroutineScope {
                batch.map { weekStart ->
                    async { weekStart to loadFallbackTimetable(weekStart, session) }
                }.awaitAll()
            }
            outcomes.forEach { (weekStart, timetable) ->
                completedWeeks += 1
                if (timetable == null) {
                    failedWeeks += 1
                } else {
                    loaded[weekStart] = timetable
                }
                onProgress(AbsenceSubjectResolutionProgress(loaded.size, completedWeeks, weekStarts.size))
            }
        }

        return TermTimetableLoadResult(
            responses = loaded.toSortedMap().values.toList(),
            failedWeeks = failedWeeks,
        )
    }

    private suspend fun loadFallbackTimetable(
        weekStart: LocalDate,
        session: StoredSession,
    ): TimetableResponse? = try {
        withTimeoutOrNull(timetableFallbackTimeoutMillis) {
            val key = TimetableDates.apiDateString(weekStart)
            fetchTimetable(session, key).also {
                publishForActiveSession(session) {
                    cache.saveRawTimetable(session.cacheScope, key, it)
                }
            }
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        null
    }

    private fun UserResponse.resolvedFor(session: StoredSession): UserResponse =
        displaySchoolName?.let { resolved ->
            if (resolved == schoolName) this else copy(schoolName = resolved)
        } ?: copy(schoolName = session.linkedAccountSchoolName)
}

private data class TermTimetableLoadResult(
    val responses: List<TimetableResponse>,
    val failedWeeks: Int,
)

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
