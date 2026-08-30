package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.LoginResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.BakalariApiException
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AndroidSchoolRepositoryTest {
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

    private fun repository(
        client: BakalariClient,
        sessions: SchoolSessionStorage,
    ): AndroidSchoolRepository = AndroidSchoolRepository(
        bakalariClient = client,
        sessionStore = sessions,
        cache = RoomGradeyCache(InMemoryCacheEntryDao(), GradeyJson),
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
    var lastLoginUsername: String? = null

    var refresh: suspend (String, String) -> LoginResponse = { _, _ -> refreshedResponse() }
    var marks: suspend (String, String) -> MarksResponse = { _, _ -> MarksResponse() }

    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse {
        loginCalls += 1
        lastLoginUsername = username
        return LoginResponse("login-access", "login-refresh", "Bearer", 3_600)
    }

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse {
        refreshCalls += 1
        return refresh(baseURL, refreshToken)
    }

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse {
        marksCalls += 1
        return marks(baseURL, accessToken)
    }

    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse = AbsenceResponse()
    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse = UserResponse("Student")
    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse = TimetableResponse()
    override suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject = subject
}

private fun refreshedResponse() = LoginResponse("new-access", "new-refresh", "Bearer", 3_600)
