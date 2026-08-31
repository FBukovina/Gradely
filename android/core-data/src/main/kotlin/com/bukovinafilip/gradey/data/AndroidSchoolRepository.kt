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
import com.bukovinafilip.gradey.domain.AuthenticatedSchoolSessionCandidate
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.domain.SchoolCloudInvalidationResult
import com.bukovinafilip.gradey.domain.SchoolDirectoryNameResolver
import com.bukovinafilip.gradey.domain.SchoolCloudMutationToken
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
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
    private val sessionRefreshMutex = Mutex()
    private val inFlightSchoolRefreshes =
        mutableMapOf<SchoolSessionRefreshPlan.Refresh, CompletableDeferred<ActiveSchoolSession>>()
    private var schoolCloudMutationEpoch = 0L
    private var sessionGeneration = 0L

    override suspend fun bootstrapSession(): StoredSession? = sessionStore.load()

    override suspend fun currentStoredSession(): StoredSession? = sessionStore.load()

    override suspend fun login(schoolURL: String, username: String, password: String): StoredSession =
        login(schoolURL, username, password, captureSchoolCloudMutationToken())

    override suspend fun login(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession {
        val candidate = authenticateBakalariSession(schoolURL, username, password, cloudMutationToken)
        return sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            requireCurrentSessionGeneration(candidate.sessionGeneration)
            advanceSessionGeneration()
            saveReplacingSchoolScope(candidate.session)
            candidate.session
        }
    }

    override suspend fun authenticateSchoolSessionCandidate(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): AuthenticatedSchoolSessionCandidate = coroutineScope {
        val candidate = authenticateBakalariSession(schoolURL, username, password, cloudMutationToken)
        val session = candidate.session
        val marks = bakalariClient.fetchMarks(session.baseURL, session.accessToken)
        val absence = async {
            optionalCandidateRequest { bakalariClient.fetchAbsences(session.baseURL, session.accessToken) }
        }
        val user = async {
            optionalCandidateRequest { bakalariClient.fetchUser(session.baseURL, session.accessToken) }
        }
        val absenceResult = absence.await()
        val dashboard = DashboardData(
            marksResponse = marks,
            absencesPerSubject = absenceResult?.absencesPerSubject.orEmpty(),
            user = user.await()?.resolvedFor(session),
        )
        sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            requireCurrentSessionGeneration(candidate.sessionGeneration)
        }
        AuthenticatedSchoolSessionCandidate(
            session = session,
            dashboard = dashboard,
            sessionGeneration = candidate.sessionGeneration,
        )
    }

    override suspend fun promoteAuthenticatedSchoolSessionCandidate(
        candidate: AuthenticatedSchoolSessionCandidate,
        account: LinkedSchoolAccount,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession = sessionMutationMutex.withLock {
        requireCurrentSchoolCloudMutation(cloudMutationToken)
        requireCurrentSessionGeneration(candidate.sessionGeneration)
        require(account.provider == LinkedAccountProvider.from(candidate.session.provider)) {
            "The linked account provider does not match the authenticated school session."
        }
        val promoted = candidate.session.copy(
            linkedAccountID = account.id,
            linkedAccountDisplayName = account.displayName,
            linkedAccountSchoolName = account.schoolName,
        )
        advanceSessionGeneration()
        saveReplacingSchoolScope(promoted)
        promoted
    }

    private suspend fun authenticateBakalariSession(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): AuthenticatedBakalariSession {
        val expectedSessionGeneration = sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            sessionGeneration
        }
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
        sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            requireCurrentSessionGeneration(expectedSessionGeneration)
        }
        return AuthenticatedBakalariSession(session, expectedSessionGeneration)
    }

    override suspend fun restoreSession(session: StoredSession): StoredSession =
        sessionMutationMutex.withLock {
            advanceSessionGeneration()
            saveReplacingSchoolScope(session)
            session
        }

    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession =
        activateLinkedSchoolAccount(session, captureSchoolCloudMutationToken())

    override suspend fun activateLinkedSchoolAccount(
        session: StoredSession,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession {
        var expectedSessionGeneration: Long? = null
        val preserved = sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
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
                advanceSessionGeneration()
                saveReplacingSchoolScope(preserved)
                preserved
            } else {
                expectedSessionGeneration = sessionGeneration
                null
            }
        }
        if (preserved != null) return preserved

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
        return sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            requireCurrentSessionGeneration(checkNotNull(expectedSessionGeneration))
            advanceSessionGeneration()
            saveReplacingSchoolScope(activated)
            activated
        }
    }

    override suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession =
        associateCurrentSession(account, captureSchoolCloudMutationToken())

    override suspend fun associateCurrentSession(
        account: LinkedSchoolAccount,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession =
        sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
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
            advanceSessionGeneration()
            sessionStore.save(associated)
            associated
        }

    override suspend fun disassociateCurrentSession(accountID: String): StoredSession? =
        disassociateCurrentSession(accountID, captureSchoolCloudMutationToken())

    override suspend fun disassociateCurrentSession(
        accountID: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession? =
        sessionMutationMutex.withLock {
            requireCurrentSchoolCloudMutation(cloudMutationToken)
            val current = sessionStore.load() ?: return@withLock null
            if (current.linkedAccountID != accountID) return@withLock current
            val local = current.copy(
                linkedAccountID = null,
                linkedAccountDisplayName = null,
                linkedAccountSchoolName = null,
            )
            // Detaching cloud metadata does not change the underlying local student.
            advanceSessionGeneration()
            sessionStore.save(local)
            local
        }

    override suspend fun captureSchoolCloudMutationToken(): SchoolCloudMutationToken =
        sessionMutationMutex.withLock {
            SchoolCloudMutationToken(schoolCloudMutationEpoch)
        }

    override suspend fun invalidateSchoolCloudMutationsAndDisassociate(): SchoolCloudInvalidationResult =
        sessionMutationMutex.withLock {
            // Fail closed: once teardown enters this boundary, no previously issued token may
            // commit even if secure-storage detachment itself fails.
            schoolCloudMutationEpoch = nextSchoolCloudMutationEpoch(schoolCloudMutationEpoch)
            advanceSessionGeneration()
            val current = sessionStore.load()
            val result = if (current == null) {
                SchoolCloudInvalidationResult(
                    previousLinkedAccountID = null,
                    retainedSession = null,
                )
            } else if (
                current.linkedAccountID == null &&
                current.linkedAccountDisplayName == null &&
                current.linkedAccountSchoolName == null
            ) {
                SchoolCloudInvalidationResult(
                    previousLinkedAccountID = current.linkedAccountID,
                    retainedSession = current,
                )
            } else {
                val detached = current.copy(
                    linkedAccountID = null,
                    linkedAccountDisplayName = null,
                    linkedAccountSchoolName = null,
                )
                // Identity teardown must not discard the retained Bakaláři login or any of its
                // school-scoped caches and platform projections.
                try {
                    sessionStore.save(detached)
                    SchoolCloudInvalidationResult(
                        previousLinkedAccountID = current.linkedAccountID,
                        retainedSession = detached,
                    )
                } catch (saveError: Throwable) {
                    try {
                        // A failed encrypted-store rewrite must not leave cloud identity metadata
                        // durable. Clear only the session; school caches and projections remain.
                        sessionStore.clear()
                    } catch (clearError: Throwable) {
                        saveError.addSuppressed(clearError)
                        throw saveError
                    }
                    SchoolCloudInvalidationResult(
                        previousLinkedAccountID = current.linkedAccountID,
                        retainedSession = null,
                    )
                }
            }
            result
        }

    override suspend fun restoreSessionIfCurrentCandidate(
        candidate: StoredSession,
        previous: StoredSession?,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession? = sessionMutationMutex.withLock {
        requireCurrentSchoolCloudMutation(cloudMutationToken)
        val current = sessionStore.load()
        if (current != candidate) return@withLock current
        if (previous == null) {
            advanceSessionGeneration()
            sessionStore.clear()
            return@withLock null
        }
        advanceSessionGeneration()
        saveReplacingSchoolScope(previous)
        previous
    }

    override suspend fun logout() = sessionMutationMutex.withLock {
        // Fail closed before storage work: a held login or activation must not be able to
        // repopulate the session even if clearing secure storage or caches fails.
        schoolCloudMutationEpoch = nextSchoolCloudMutationEpoch(schoolCloudMutationEpoch)
        advanceSessionGeneration()
        sessionStore.clear()
        clearLocalCaches()
    }

    override suspend fun clearLocalCaches() = cache.clearAllSchoolData()

    override suspend fun loadCachedDashboard(): DashboardData? =
        sessionStore.load()?.let { cache.loadDashboard(it.cacheScope) }

    override suspend fun loadCachedAbsence(): AbsenceResponse? =
        sessionStore.load()?.let { cache.loadAbsence(it.cacheScope) }

    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData = coroutineScope {
        val activeSession = validSession()
        val session = activeSession.session
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
        publishForActiveSession(activeSession) {
            cache.saveMarks(session.cacheScope, marks)
            if (absenceResult != null) cache.saveAbsence(session.cacheScope, absenceResult)
            cache.saveDashboard(session.cacheScope, data)
        }
        data
    }

    override suspend fun loadAbsence(forceRefresh: Boolean): AbsenceResponse {
        val activeSession = validSession()
        val session = activeSession.session
        val response = fetchAbsence(session)
        publishForActiveSession(activeSession) {
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

        val activeSession = validSession()
        val session = activeSession.session
        val term = AbsenceTerms.resolve(response, dateProvider())
        val markSubjects = try {
            cache.loadMarks(session.cacheScope)?.subjects ?: fetchMarks(session).also {
                publishForActiveSession(activeSession) {
                    cache.saveMarks(session.cacheScope, it)
                }
            }.subjects
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
            throw error
        } catch (_: Throwable) {
            emptyList()
        }
        val timetableLoad = loadTermTimetables(term.weekStarts, activeSession, onProgress)
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
        val activeSession = validSession()
        val session = activeSession.session
        publishForActiveSession(activeSession) {
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
        val activeSession = validSession()
        val session = activeSession.session
        val weekStart = TimetableDates.apiDateString(TimetableDates.monday(date))
        val timetable = cache.loadRawTimetable(session.cacheScope, weekStart) ?: fetchTimetable(session, weekStart).also {
            publishForActiveSession(activeSession) {
                cache.saveRawTimetable(session.cacheScope, weekStart, it)
            }
        }
        val markSubjects = try {
            cache.loadMarks(session.cacheScope)?.subjects ?: fetchMarks(session).also {
                publishForActiveSession(activeSession) {
                    cache.saveMarks(session.cacheScope, it)
                }
            }.subjects
        } catch (error: CancellationException) {
            throw error
        } catch (error: SchoolSessionExpiredException) {
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

    override suspend fun clearNextLessonSnapshotIfSignedOut(): Boolean =
        sessionMutationMutex.withLock {
            if (sessionStore.load() != null) return@withLock false
            try {
                cache.clearNextLessonSnapshot()
            } catch (_: Throwable) {
                // Session absence remains authoritative if the disposable projection is damaged.
            }
            true
        }

    override suspend fun loadTimetable(weekContaining: String): TimetableWeek {
        val activeSession = validSession()
        val session = activeSession.session
        val monday = TimetableDates.apiDateString(TimetableDates.monday(LocalDate.parse(weekContaining)))
        val response = fetchTimetable(session, monday)
        val week = TimetableMapper.makeWeek(response, monday, TimetableDates.apiDateString(dateProvider()))
        publishForActiveSession(activeSession) {
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
        val session = validSession().session
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

    private fun requireCurrentSchoolCloudMutation(token: SchoolCloudMutationToken) {
        if (token.epoch != schoolCloudMutationEpoch) throw GradeyIdentityChangedException()
    }

    private fun requireCurrentSessionGeneration(expected: Long) {
        if (expected != sessionGeneration) {
            throw CancellationException("The active school session changed before this operation completed.")
        }
    }

    private fun advanceSessionGeneration() {
        sessionGeneration = nextMutationSequence(sessionGeneration)
    }

    private fun nextSchoolCloudMutationEpoch(current: Long): Long =
        nextMutationSequence(current)

    private fun nextMutationSequence(current: Long): Long =
        if (current == Long.MAX_VALUE) Long.MIN_VALUE else current + 1L

    private suspend fun <T> publishForActiveSession(
        activeSession: ActiveSchoolSession,
        publication: suspend () -> T,
    ): T = sessionMutationMutex.withLock {
        val session = activeSession.session
        val active = sessionStore.load()
        if (
            activeSession.sessionGeneration != sessionGeneration ||
            active == null ||
            active.cacheScope != session.cacheScope
        ) {
            throw CancellationException("The active school account changed before data publication.")
        }
        publication()
    }

    private suspend fun validSession(): ActiveSchoolSession {
        val activeSession = sessionMutationMutex.withLock {
            ActiveSchoolSession(
                session = sessionStore.load() ?: throw SchoolSessionExpiredException(),
                sessionGeneration = sessionGeneration,
            )
        }
        if (!activeSession.session.isExpired()) return activeSession
        val session = activeSession.session
        return refreshBakalariIfCurrent(session, refreshRejectedAccessToken = false)
    }

    private suspend fun refreshBakalariIfCurrent(
        observedSession: StoredSession,
        refreshRejectedAccessToken: Boolean,
    ): ActiveSchoolSession {
        val plan = sessionMutationMutex.withLock {
            val latest = sessionStore.load() ?: throw SchoolSessionExpiredException()
            if (latest.cacheScope != observedSession.cacheScope) {
                throw CancellationException("The active school account changed before token refresh.")
            }
            val anotherRefreshAlreadySucceeded =
                refreshRejectedAccessToken &&
                    latest.accessToken != observedSession.accessToken &&
                    !latest.isExpired()
            if ((!refreshRejectedAccessToken && !latest.isExpired()) || anotherRefreshAlreadySucceeded) {
                SchoolSessionRefreshPlan.UseCurrent(latest, sessionGeneration)
            } else {
                SchoolSessionRefreshPlan.Refresh(
                    session = latest,
                    schoolCloudMutationEpoch = schoolCloudMutationEpoch,
                    sessionGeneration = sessionGeneration,
                )
            }
        }
        if (plan is SchoolSessionRefreshPlan.UseCurrent) {
            return ActiveSchoolSession(plan.session, plan.sessionGeneration)
        }
        check(plan is SchoolSessionRefreshPlan.Refresh)

        var leadsRefresh = false
        val sharedResult = sessionRefreshMutex.withLock {
            inFlightSchoolRefreshes[plan] ?: run {
                leadsRefresh = true
                CompletableDeferred<ActiveSchoolSession>().also { result ->
                    inFlightSchoolRefreshes[plan] = result
                }
            }
        }
        if (!leadsRefresh) return sharedResult.await()

        try {
            val refreshed = executeBakalariRefresh(plan)
            sharedResult.complete(refreshed)
            return refreshed
        } catch (error: Throwable) {
            sharedResult.completeExceptionally(error)
            throw error
        } finally {
            withContext(NonCancellable) {
                sessionRefreshMutex.withLock {
                    if (inFlightSchoolRefreshes[plan] === sharedResult) {
                        inFlightSchoolRefreshes.remove(plan)
                    }
                }
            }
        }
    }

    private suspend fun executeBakalariRefresh(
        plan: SchoolSessionRefreshPlan.Refresh,
    ): ActiveSchoolSession {
        sessionMutationMutex.withLock {
            requireCurrentRefreshCandidate(plan)
        }
        val session = plan.session
        val response = try {
            bakalariClient.refreshToken(session.baseURL, session.refreshToken)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isRefreshTokenRejected(error)) throw error
            sessionMutationMutex.withLock {
                requireCurrentRefreshCandidate(plan)
            }
            val credentials = session.bakalari ?: expireRefreshCandidate(plan, error)
            try {
                bakalariClient.login(session.baseURL, credentials.username, credentials.password)
            } catch (loginError: CancellationException) {
                throw loginError
            } catch (loginError: Throwable) {
                if (isRefreshTokenRejected(loginError)) expireRefreshCandidate(plan, loginError)
                throw loginError
            }
        }
        val updated = session.copy(
            accessToken = response.accessToken,
            refreshToken = response.refreshToken,
            tokenType = response.tokenType,
            expiresAtEpochMillis = System.currentTimeMillis() + response.expiresIn * 1000L,
        )
        sessionMutationMutex.withLock {
            requireCurrentRefreshCandidate(plan)
            sessionStore.save(updated)
        }
        return ActiveSchoolSession(updated, plan.sessionGeneration)
    }

    private suspend fun <T> withBakalariRetry(session: StoredSession, block: suspend (StoredSession) -> T): T =
        try {
            block(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isAccessTokenRejected(error)) throw error
            val refreshed = refreshBakalariIfCurrent(session, refreshRejectedAccessToken = true)
            block(refreshed.session)
        }

    private fun requireCurrentRefreshCandidate(plan: SchoolSessionRefreshPlan.Refresh) {
        if (plan.schoolCloudMutationEpoch != schoolCloudMutationEpoch) {
            throw GradeyIdentityChangedException()
        }
        requireCurrentSessionGeneration(plan.sessionGeneration)
        if (sessionStore.load() != plan.session) {
            throw CancellationException("The active school account changed during token refresh.")
        }
    }

    private suspend fun expireRefreshCandidate(
        plan: SchoolSessionRefreshPlan.Refresh,
        cause: Throwable,
    ): Nothing {
        sessionMutationMutex.withLock {
            requireCurrentRefreshCandidate(plan)
            advanceSessionGeneration()
            sessionStore.clear()
            // A rejected refresh/login makes the global launcher projection unsafe even though the
            // account-scoped caches remain useful for reconnect/offline recovery.
            try {
                withContext(NonCancellable) { cache.clearNextLessonSnapshot() }
            } catch (_: Throwable) {
                // The rejected session remains authoritative if the disposable widget cache is damaged.
            }
        }
        throw SchoolSessionExpiredException(cause)
    }

    private suspend fun <T> optionalCandidateRequest(block: suspend () -> T): T? =
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
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
        activeSession: ActiveSchoolSession,
        onProgress: suspend (AbsenceSubjectResolutionProgress) -> Unit,
    ): TermTimetableLoadResult {
        val session = activeSession.session
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
                    async { weekStart to loadFallbackTimetable(weekStart, activeSession) }
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
        activeSession: ActiveSchoolSession,
    ): TimetableResponse? = try {
        val session = activeSession.session
        withTimeoutOrNull(timetableFallbackTimeoutMillis) {
            val key = TimetableDates.apiDateString(weekStart)
            fetchTimetable(session, key).also {
                publishForActiveSession(activeSession) {
                    cache.saveRawTimetable(session.cacheScope, key, it)
                }
            }
        }
    } catch (error: CancellationException) {
        throw error
    } catch (error: SchoolSessionExpiredException) {
        throw error
    } catch (_: Throwable) {
        null
    }

    private suspend fun UserResponse.resolvedFor(session: StoredSession): UserResponse {
        displaySchoolName?.let { resolved ->
            return if (resolved == schoolName) this else copy(schoolName = resolved)
        }

        val directoryName = try {
            cache.loadSchoolDirectory()?.schools?.let { schools ->
                SchoolDirectoryNameResolver.resolve(session.baseURL, schools)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        return copy(
            schoolName = directoryName
                ?: SchoolDirectoryNameResolver.displayableName(session.linkedAccountSchoolName),
        )
    }
}

private data class TermTimetableLoadResult(
    val responses: List<TimetableResponse>,
    val failedWeeks: Int,
)

private data class ActiveSchoolSession(
    val session: StoredSession,
    val sessionGeneration: Long,
)

private data class AuthenticatedBakalariSession(
    val session: StoredSession,
    val sessionGeneration: Long,
)

private sealed interface SchoolSessionRefreshPlan {
    data class UseCurrent(
        val session: StoredSession,
        val sessionGeneration: Long,
    ) : SchoolSessionRefreshPlan

    data class Refresh(
        val session: StoredSession,
        val schoolCloudMutationEpoch: Long,
        val sessionGeneration: Long,
    ) : SchoolSessionRefreshPlan
}

interface SchoolSessionStorage {
    fun load(): StoredSession?
    fun save(session: StoredSession)
    fun clear()
}

internal interface SchoolSessionValueStore {
    fun loadCurrent(): SecureJsonReadResult<StoredSchoolSessionEnvelope>
    fun loadLegacy(): StoredSession?
    fun replaceCurrentAndClearLegacy(envelope: StoredSchoolSessionEnvelope)
    fun clearCurrentAndLegacy()
}

private class EncryptedSchoolSessionValueStore(
    private val secureJsonStore: SecureJsonStore,
) : SchoolSessionValueStore {
    override fun loadCurrent(): SecureJsonReadResult<StoredSchoolSessionEnvelope> =
        secureJsonStore.read(CURRENT_KEY, StoredSchoolSessionEnvelope.serializer())

    override fun loadLegacy(): StoredSession? =
        secureJsonStore.loadOrClearInvalid(LEGACY_KEY, StoredSession.serializer())

    override fun replaceCurrentAndClearLegacy(envelope: StoredSchoolSessionEnvelope) =
        secureJsonStore.saveReplacing(
            key = CURRENT_KEY,
            value = envelope,
            serializer = StoredSchoolSessionEnvelope.serializer(),
            removeKeys = setOf(LEGACY_KEY),
        )

    override fun clearCurrentAndLegacy() = secureJsonStore.clear(setOf(CURRENT_KEY, LEGACY_KEY))

    private companion object {
        const val CURRENT_KEY = "school.session.v2"
        const val LEGACY_KEY = "school.session.v1"
    }
}

class SchoolSessionStore internal constructor(
    private val valueStore: SchoolSessionValueStore,
) : SchoolSessionStorage {
    private val storageLock = Any()

    constructor(secureJsonStore: SecureJsonStore) : this(EncryptedSchoolSessionValueStore(secureJsonStore))

    override fun load(): StoredSession? = synchronized(storageLock) {
        when (val current = valueStore.loadCurrent()) {
            SecureJsonReadResult.Absent -> Unit
            SecureJsonReadResult.Rejected -> {
                valueStore.clearCurrentAndLegacy()
                return@synchronized null
            }
            is SecureJsonReadResult.Valid -> {
                if (current.value.formatVersion == CURRENT_FORMAT_VERSION) {
                    return@synchronized current.value.session
                }
                valueStore.clearCurrentAndLegacy()
                return@synchronized null
            }
        }

        val legacy = valueStore.loadLegacy() ?: return@synchronized null
        save(legacy)
        legacy
    }

    override fun save(session: StoredSession) = synchronized(storageLock) {
        valueStore.replaceCurrentAndClearLegacy(StoredSchoolSessionEnvelope(CURRENT_FORMAT_VERSION, session))
    }

    override fun clear() = synchronized(storageLock) {
        valueStore.clearCurrentAndLegacy()
    }

    private companion object {
        const val CURRENT_FORMAT_VERSION = 2
    }
}
