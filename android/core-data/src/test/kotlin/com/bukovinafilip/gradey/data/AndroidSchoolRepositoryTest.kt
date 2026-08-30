package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.LoginResponse
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableDayDTO
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.BakalariApiException
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AndroidSchoolRepositoryTest {
    @Test
    fun bootstrapRestoresStoredSessionWithoutCallingBakalari() = runTest {
        val client = FakeBakalariClient()
        val session = validSession()
        val repository = repository(client, InMemorySchoolSessionStorage(session))

        val restored = repository.bootstrapSession()

        assertThat(restored).isEqualTo(session)
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(client.refreshCalls).isEqualTo(0)
        assertThat(client.marksCalls).isEqualTo(0)
    }

    @Test
    fun `activation preserves the device token family for the same linked account`() = runTest {
        val current = validSession().copy(
            linkedAccountID = "account-1",
            linkedAccountDisplayName = "Old name",
        )
        val incoming = current.copy(
            accessToken = "cloud-poller-access",
            refreshToken = "cloud-poller-refresh",
            linkedAccountDisplayName = "Canonical name",
            linkedAccountSchoolName = "Canonical school",
        )
        val client = FakeBakalariClient()
        val sessions = InMemorySchoolSessionStorage(current)

        val activated = repository(client, sessions).activateLinkedSchoolAccount(incoming)

        assertThat(activated.accessToken).isEqualTo("old-access")
        assertThat(activated.refreshToken).isEqualTo("old-refresh")
        assertThat(activated.linkedAccountDisplayName).isEqualTo("Canonical name")
        assertThat(activated.linkedAccountSchoolName).isEqualTo("Canonical school")
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(sessions.load()).isEqualTo(activated)
    }

    @Test
    fun `activation of another linked account mints a device Bakalari token family`() = runTest {
        val incoming = validSession().copy(
            accessToken = "cloud-poller-access",
            refreshToken = "cloud-poller-refresh",
            linkedAccountID = "account-2",
            linkedAccountDisplayName = "Second student",
            linkedAccountSchoolName = "Second school",
            bakalari = BakalariCredentials("second-student", "second-secret"),
        )
        val client = FakeBakalariClient()
        val sessions = InMemorySchoolSessionStorage(validSession().copy(linkedAccountID = "account-1"))

        val activated = repository(client, sessions).activateLinkedSchoolAccount(incoming)

        assertThat(client.loginCalls).isEqualTo(1)
        assertThat(client.lastLoginUsername).isEqualTo("second-student")
        assertThat(client.lastLoginPassword).isEqualTo("second-secret")
        assertThat(activated.accessToken).isEqualTo("login-access")
        assertThat(activated.refreshToken).isEqualTo("login-refresh")
        assertThat(activated.linkedAccountID).isEqualTo("account-2")
        assertThat(sessions.load()).isEqualTo(activated)
    }

    @Test
    fun `associating a newly linked account keeps current school credentials and tokens`() = runTest {
        val current = validSession()
        val sessions = InMemorySchoolSessionStorage(current)
        val linked = LinkedSchoolAccount(
            id = "linked-account",
            provider = LinkedAccountProvider.BAKALARI,
            displayName = "Student",
            schoolName = "School",
        )

        val associated = repository(FakeBakalariClient(), sessions).associateCurrentSession(linked)

        assertThat(associated.accessToken).isEqualTo(current.accessToken)
        assertThat(associated.bakalari).isEqualTo(current.bakalari)
        assertThat(associated.linkedAccountID).isEqualTo("linked-account")
        assertThat(associated.linkedAccountDisplayName).isEqualTo("Student")
        assertThat(associated.linkedAccountSchoolName).isEqualTo("School")
    }

    @Test
    fun `unlinking the active cloud account detaches metadata but keeps local school access`() = runTest {
        val current = validSession().copy(
            linkedAccountID = "linked-account",
            linkedAccountDisplayName = "Student",
            linkedAccountSchoolName = "School",
        )
        val sessions = InMemorySchoolSessionStorage(current)

        val local = repository(FakeBakalariClient(), sessions)
            .disassociateCurrentSession("linked-account")

        assertThat(local?.accessToken).isEqualTo(current.accessToken)
        assertThat(local?.bakalari).isEqualTo(current.bakalari)
        assertThat(local?.linkedAccountID).isNull()
        assertThat(local?.linkedAccountDisplayName).isNull()
        assertThat(local?.linkedAccountSchoolName).isNull()
        assertThat(sessions.load()).isEqualTo(local)
    }

    @Test
    fun serverFailureDoesNotRefreshOrRelogin() = runTest {
        val client = FakeBakalariClient().apply {
            marks = { _, _ -> throw BakalariApiException(500, "server unavailable") }
        }
        val sessions = InMemorySchoolSessionStorage(validSession())
        val repository = repository(client, sessions)

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(BakalariApiException::class.java)
        assertThat(client.refreshCalls).isEqualTo(0)
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(sessions.load()?.accessToken).isEqualTo("old-access")
    }

    @Test
    fun primaryRefreshFailureDoesNotDeleteCachedDashboard() = runTest {
        val session = validSession()
        val cached = DashboardData(MarksResponse(), user = UserResponse("Cached Student"))
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        cache.saveDashboard(session.cacheScope, cached)
        val client = FakeBakalariClient().apply {
            marks = { _, _ -> throw java.io.IOException("offline") }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(session), cache)

        val failure = runCatching { repository.loadDashboard(forceRefresh = true) }.exceptionOrNull()

        assertThat(failure).isInstanceOf(java.io.IOException::class.java)
        assertThat(cache.loadDashboard(session.cacheScope)).isEqualTo(cached)
        assertThat(repository.loadCachedDashboard()).isEqualTo(cached)
    }

    @Test
    fun rejectedAccessTokenRefreshesAndRetriesOnce() = runTest {
        val client = FakeBakalariClient().apply {
            marks = { _, token ->
                if (token == "old-access") throw BakalariApiException(401, "expired")
                MarksResponse()
            }
        }
        val sessions = InMemorySchoolSessionStorage(validSession())
        val repository = repository(client, sessions)

        repository.loadDashboard()

        assertThat(client.marksCalls).isEqualTo(2)
        assertThat(client.refreshCalls).isEqualTo(1)
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(sessions.load()?.accessToken).isEqualTo("new-access")
    }

    @Test
    fun rejectedRefreshTokenFallsBackToStoredCredentials() = runTest {
        val client = FakeBakalariClient().apply {
            refresh = { _, _ -> throw BakalariApiException(400, "invalid_grant") }
        }
        val sessions = InMemorySchoolSessionStorage(expiredSession())
        val repository = repository(client, sessions)

        repository.loadDashboard()

        assertThat(client.refreshCalls).isEqualTo(1)
        assertThat(client.loginCalls).isEqualTo(1)
        assertThat(client.lastLoginUsername).isEqualTo("student")
        assertThat(sessions.load()?.accessToken).isEqualTo("login-access")
    }

    @Test
    fun refreshNetworkFailureDoesNotAttemptCredentialLogin() = runTest {
        val client = FakeBakalariClient().apply {
            refresh = { _, _ -> throw java.io.IOException("offline") }
        }
        val sessions = InMemorySchoolSessionStorage(expiredSession())
        val repository = repository(client, sessions)

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(java.io.IOException::class.java)
        assertThat(client.refreshCalls).isEqualTo(1)
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(sessions.load()?.accessToken).isEqualTo("old-access")
    }

    @Test
    fun concurrentExpiredRequestsShareOneRefresh() = runTest {
        val client = FakeBakalariClient().apply {
            refresh = { _, _ ->
                delay(50)
                refreshedResponse()
            }
        }
        val sessions = InMemorySchoolSessionStorage(expiredSession())
        val repository = repository(client, sessions)

        val first = async { repository.loadDashboard() }
        val second = async { repository.loadDashboard() }
        first.await()
        second.await()

        assertThat(client.refreshCalls).isEqualTo(1)
        assertThat(client.loginCalls).isEqualTo(0)
    }

    @Test
    fun optionalAbsenceAndUserFailuresDoNotFailDashboard() = runTest {
        val client = FakeBakalariClient().apply {
            absences = { _, _ -> throw BakalariApiException(404, "not supported") }
            user = { _, _ -> throw BakalariApiException(404, "not supported") }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(validSession()))

        val dashboard = repository.loadDashboard()

        assertThat(dashboard.marksResponse).isEqualTo(MarksResponse())
        assertThat(dashboard.absencesPerSubject).isEmpty()
        assertThat(dashboard.user).isNull()
    }

    @Test
    fun `what-if prediction uses the authenticated endpoint and parses its returned average`() = runTest {
        val subject = Subject(
            subjectInfo = SubjectInfo(id = "math", name = "Mathematics"),
            averageText = "2.10",
            markPredictionEnabled = true,
        )
        val client = FakeBakalariClient().apply {
            prediction = { _, token, predictedSubject, markText, weight ->
                assertThat(token).isEqualTo("old-access")
                assertThat(predictedSubject).isEqualTo(subject)
                assertThat(markText).isEqualTo("1-")
                assertThat(weight).isEqualTo(4)
                predictedSubject.copy(averageText = "1,85")
            }
        }

        val average = repository(client, InMemorySchoolSessionStorage(validSession()))
            .predictSubjectAverage(subject, "1-", 4)

        assertThat(average).isEqualTo(1.85)
        assertThat(client.predictionCalls).isEqualTo(1)
    }

    @Test
    fun `what-if prediction refreshes a rejected access token and retries once`() = runTest {
        val subject = Subject(subjectInfo = SubjectInfo(id = "math", name = "Mathematics"))
        val client = FakeBakalariClient().apply {
            prediction = { _, token, predictedSubject, _, _ ->
                if (token == "old-access") throw BakalariApiException(401, "expired")
                predictedSubject.copy(averageText = "2.00")
            }
        }
        val sessions = InMemorySchoolSessionStorage(validSession())

        val average = repository(client, sessions).predictSubjectAverage(subject, "2", 1)

        assertThat(average).isEqualTo(2.0)
        assertThat(client.predictionCalls).isEqualTo(2)
        assertThat(client.refreshCalls).isEqualTo(1)
        assertThat(sessions.load()?.accessToken).isEqualTo("new-access")
    }

    @Test
    fun optionalFailuresPreservePreviouslyCachedDashboardContent() = runTest {
        val session = validSession()
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        val cachedAbsence = AbsenceResponse(
            absencesPerSubject = listOf(AbsencePerSubject("Mathematics", 100, 7)),
        )
        val cachedUser = UserResponse("Cached Student", "Cached School")
        cache.saveAbsence(session.cacheScope, cachedAbsence)
        cache.saveDashboard(
            session.cacheScope,
            DashboardData(MarksResponse(), cachedAbsence.absencesPerSubject, cachedUser),
        )
        val client = FakeBakalariClient().apply {
            absences = { _, _ -> throw java.io.IOException("offline") }
            user = { _, _ -> throw BakalariApiException(404, "not supported") }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(session), cache)

        val dashboard = repository.loadDashboard()

        assertThat(dashboard.absencesPerSubject).isEqualTo(cachedAbsence.absencesPerSubject)
        assertThat(dashboard.user).isEqualTo(cachedUser)
        assertThat(cache.loadDashboard(session.cacheScope)?.user).isEqualTo(cachedUser)
    }

    @Test
    fun optionalEndpointCancellationIsNotSwallowed() = runTest {
        val client = FakeBakalariClient().apply {
            absences = { _, _ -> throw CancellationException("cancelled") }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(validSession()))

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(CancellationException::class.java)
    }

    @Test
    fun unrecoverableExpiredSessionIsClearedButScopedCacheIsRetained() = runTest {
        val session = expiredSession()
        val sessions = InMemorySchoolSessionStorage(session)
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        val cached = DashboardData(MarksResponse(), user = UserResponse("Cached Student"))
        cache.saveDashboard(session.cacheScope, cached)
        val client = FakeBakalariClient().apply {
            refresh = { _, _ -> throw BakalariApiException(400, "invalid_grant") }
            loginResult = { _, _, _ -> throw BakalariApiException(400, "invalid credentials") }
        }
        val repository = repository(client, sessions, cache)

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(SchoolSessionExpiredException::class.java)
        assertThat(sessions.load()).isNull()
        assertThat(cache.loadDashboard(session.cacheScope)).isEqualTo(cached)
    }

    @Test
    fun rejectedRefreshWithoutStoredCredentialsClearsExpiredSession() = runTest {
        val client = FakeBakalariClient().apply {
            refresh = { _, _ -> throw BakalariApiException(401, "invalid refresh token") }
        }
        val sessions = InMemorySchoolSessionStorage(expiredSession().copy(bakalari = null))
        val repository = repository(client, sessions)

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(SchoolSessionExpiredException::class.java)
        assertThat(client.loginCalls).isEqualTo(0)
        assertThat(sessions.load()).isNull()
    }

    @Test
    fun transientCredentialLoginFailureRetainsExpiredSessionForRetry() = runTest {
        val client = FakeBakalariClient().apply {
            refresh = { _, _ -> throw BakalariApiException(400, "invalid_grant") }
            loginResult = { _, _, _ -> throw java.io.IOException("offline") }
        }
        val sessions = InMemorySchoolSessionStorage(expiredSession())
        val repository = repository(client, sessions)

        val failure = runCatching { repository.loadDashboard() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(java.io.IOException::class.java)
        assertThat(sessions.load()?.accessToken).isEqualTo("old-access")
    }

    @Test
    fun successfulTimetableLoadPublishesRealWidgetSnapshot() = runTest {
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        val client = FakeBakalariClient().apply {
            timetable = { _, _, _ ->
                TimetableResponse(
                    hours = listOf(TimetableHour("1", "1", "08:00", "08:45")),
                    days = listOf(
                        TimetableDayDTO(
                            atoms = listOf(TimetableAtom(hourID = "1", subjectID = "math")),
                            dayOfWeek = 1,
                            date = "2026-08-31",
                        ),
                    ),
                    subjects = listOf(TimetableEntity("math", "M", "Mathematics")),
                )
            }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(validSession()), cache)

        repository.loadTimetable("2026-08-31")

        val snapshot = cache.loadNextLessonSnapshot()
        assertThat(snapshot).isNotNull()
        assertThat(snapshot!!.lessons).hasSize(1)
        assertThat(snapshot.lessons.single().subjectName).isEqualTo("Mathematics")
        assertThat(snapshot.lessons.single().subjectAbbrev).isEqualTo("M")
        assertThat(snapshot.lessons.single().timeRange).isEqualTo("08:00-08:45")
    }

    @Test
    fun failedTimetableRefreshRetainsTheCachedWeek() = runTest {
        val session = validSession()
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        val cachedWeek = com.bukovinafilip.gradey.model.TimetableWeek("2026-08-31", emptyList(), emptyList())
        cache.saveTimetable(session.cacheScope, cachedWeek.weekStart, cachedWeek)
        val client = FakeBakalariClient().apply {
            timetable = { _, _, _ -> throw java.io.IOException("offline") }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(session), cache)

        val failure = runCatching { repository.loadTimetable("2026-09-01") }.exceptionOrNull()

        assertThat(failure).isInstanceOf(java.io.IOException::class.java)
        assertThat(repository.loadCachedTimetable("2026-09-01")).isEqualTo(cachedWeek)
    }

    @Test
    fun separateTimetableWeeksRemainIndependentlyCached() = runTest {
        val session = validSession()
        val dao = InMemoryCacheEntryDao()
        val cache = RoomGradeyCache(dao, GradeyJson)
        val client = FakeBakalariClient().apply {
            timetable = { _, _, date ->
                TimetableResponse(days = listOf(TimetableDayDTO(dayOfWeek = 1, date = date)))
            }
        }
        val repository = repository(client, InMemorySchoolSessionStorage(session), cache)

        repository.loadTimetable("2026-08-31")
        repository.loadTimetable("2026-09-07")

        assertThat(repository.loadCachedTimetable("2026-08-31")?.weekStart).isEqualTo("2026-08-31")
        assertThat(repository.loadCachedTimetable("2026-09-07")?.weekStart).isEqualTo("2026-09-07")
        assertThat(dao.load("timetable-week:${session.cacheScope}-2026-08-31")?.cachedAtEpochMillis).isGreaterThan(0)
        assertThat(dao.load("timetable-week:${session.cacheScope}-2026-09-07")?.cachedAtEpochMillis).isGreaterThan(0)
    }

    @Test
    fun logoutClearsSessionScopedCacheAndWidgetSnapshot() = runTest {
        val session = validSession()
        val sessions = InMemorySchoolSessionStorage(session)
        val cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson)
        val unrelatedScope = "bakalari-other.example.cz-unrelated"
        val unrelated = DashboardData(MarksResponse(), user = UserResponse("Other Student"))
        cache.saveDashboard(session.cacheScope, DashboardData(MarksResponse()))
        cache.saveDashboard(unrelatedScope, unrelated)
        cache.saveNextLessonSnapshot(
            NextLessonWidgetSnapshot(
                cachedAtEpochMillis = 1,
                lessons = listOf(NextLessonWidgetLesson("lesson", 1)),
            ),
        )
        val repository = repository(FakeBakalariClient(), sessions, cache)

        repository.logout()

        assertThat(sessions.load()).isNull()
        assertThat(cache.loadDashboard(session.cacheScope)).isNull()
        assertThat(cache.loadNextLessonSnapshot()).isNull()
        assertThat(cache.loadDashboard(unrelatedScope)).isEqualTo(unrelated)
    }

    private fun repository(
        client: BakalariClient,
        sessions: SchoolSessionStorage,
        cache: RoomGradeyCache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson),
    ): AndroidSchoolRepository = AndroidSchoolRepository(
        bakalariClient = client,
        sessionStore = sessions,
        cache = cache,
    )

    private fun validSession() = session(expiresAt = System.currentTimeMillis() + 3_600_000)
    private fun expiredSession() = session(expiresAt = System.currentTimeMillis() - 1_000)

    private fun session(expiresAt: Long) = StoredSession(
        accessToken = "old-access",
        refreshToken = "old-refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = expiresAt,
        baseURL = "https://school.example.cz",
        provider = SchoolProvider.BAKALARI,
        bakalari = BakalariCredentials("student", "secret"),
    )
}

private class InMemorySchoolSessionStorage(
    private var session: StoredSession?,
) : SchoolSessionStorage {
    override fun load(): StoredSession? = session
    override fun save(session: StoredSession) {
        this.session = session
    }
    override fun clear() {
        session = null
    }
}

private class InMemoryCacheEntryDao : CacheEntryDao {
    private val entries = mutableMapOf<String, CacheEntryEntity>()

    override suspend fun load(key: String): CacheEntryEntity? = entries[key]
    override suspend fun save(entity: CacheEntryEntity) {
        entries[entity.key] = entity
    }
    override suspend fun clear(key: String) {
        entries.remove(key)
    }
    override suspend fun clearPrefix(prefix: String) {
        entries.keys.filter { it.startsWith(prefix) }.forEach(entries::remove)
    }
    override suspend fun clearAll() {
        entries.clear()
    }
}

private class FakeBakalariClient : BakalariClient {
    var refreshCalls = 0
    var loginCalls = 0
    var marksCalls = 0
    var predictionCalls = 0
    var lastLoginUsername: String? = null
    var lastLoginPassword: String? = null

    var loginResult: suspend (String, String, String) -> LoginResponse = { _, _, _ ->
        LoginResponse("login-access", "login-refresh", "Bearer", 3_600)
    }
    var refresh: suspend (String, String) -> LoginResponse = { _, _ -> refreshedResponse() }
    var marks: suspend (String, String) -> MarksResponse = { _, _ -> MarksResponse() }
    var absences: suspend (String, String) -> AbsenceResponse = { _, _ -> AbsenceResponse() }
    var user: suspend (String, String) -> UserResponse = { _, _ -> UserResponse("Student") }
    var timetable: suspend (String, String, String) -> TimetableResponse = { _, _, _ -> TimetableResponse() }
    var prediction: suspend (String, String, Subject, String, Int) -> Subject = { _, _, subject, _, _ -> subject }

    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse {
        loginCalls += 1
        lastLoginUsername = username
        lastLoginPassword = password
        return loginResult(baseURL, username, password)
    }

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse {
        refreshCalls += 1
        return refresh(baseURL, refreshToken)
    }

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse {
        marksCalls += 1
        return marks(baseURL, accessToken)
    }

    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse =
        absences(baseURL, accessToken)
    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse =
        user(baseURL, accessToken)
    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse =
        timetable(baseURL, accessToken, date)
    override suspend fun predictSubject(
        baseURL: String,
        accessToken: String,
        subject: Subject,
        markText: String,
        weight: Int,
    ): Subject {
        predictionCalls += 1
        return prediction(baseURL, accessToken, subject, markText, weight)
    }
}

private fun refreshedResponse() = LoginResponse("new-access", "new-refresh", "Bearer", 3_600)
