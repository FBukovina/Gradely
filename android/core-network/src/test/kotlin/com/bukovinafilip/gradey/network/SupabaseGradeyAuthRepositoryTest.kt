package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.google.common.truth.Truth.assertThat
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Before
import org.junit.Test

class SupabaseGradeyAuthRepositoryTest {
    private lateinit var server: MockWebServer
    private var storedSession: GradeyAuthSession? = null

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `valid unexpired session is restored without a request`() = runTest {
        storedSession = session(expiresAt = NOW + 61_000)

        val result = repository().validSession()

        assertThat(result).isEqualTo(storedSession)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun `expiring session refreshes and preserves omitted account fields`() = runTest {
        storedSession = session(expiresAt = NOW + 60_000)
        server.enqueue(
            jsonResponse(
                tokenResponse(
                    accessToken = "fresh-access",
                    refreshToken = null,
                    metadata = """{"provider_data":{"nested":true}}""",
                ),
            ),
        )

        val result = repository().validSession()
        val request = server.takeRequest()

        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/auth/v1/token?grant_type=refresh_token")
        assertThat(request.body.readUtf8()).isEqualTo("""{"refresh_token":"old-refresh"}""")
        assertThat(request.getHeader("apikey")).isEqualTo("anon-key")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer anon-key")
        assertThat(result.accessToken).isEqualTo("fresh-access")
        assertThat(result.refreshToken).isEqualTo("old-refresh")
        assertThat(result.account.fullName).isEqualTo("Stored Name")
        assertThat(result.account.email).isEqualTo("new@example.com")
        assertThat(result.account.avatarURL).isEqualTo("https://old.example/avatar.png")
        assertThat(result.expiresAtEpochMillis).isEqualTo(NOW + 3_600_000)
        assertThat(storedSession).isEqualTo(result)
    }

    @Test
    fun `simultaneous callers share one refresh`() = runTest {
        storedSession = session(expiresAt = NOW)
        server.enqueue(jsonResponse(tokenResponse(accessToken = "shared-access")))
        val auth = repository()

        val results = coroutineScope {
            List(8) { async { auth.validSession() } }.awaitAll()
        }

        assertThat(results.map(GradeyAuthSession::accessToken).distinct())
            .containsExactly("shared-access")
        assertThat(server.requestCount).isEqualTo(1)
    }

    @Test
    fun `rejected refresh explicitly expires and clears the local session`() = runTest {
        for (status in listOf(400, 401)) {
            storedSession = session(expiresAt = NOW)
            server.enqueue(MockResponse().setResponseCode(status).setBody("""{"message":"invalid token"}"""))

            val failure = runCatching { repository().validSession() }.exceptionOrNull()

            assertThat(failure).isInstanceOf(GradeySessionExpiredException::class.java)
            assertThat(storedSession).isNull()
        }
    }

    @Test
    fun `missing refresh token explicitly expires and clears the local session`() = runTest {
        storedSession = session(expiresAt = NOW, refreshToken = "  ")

        val failure = runCatching { repository().validSession() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeySessionExpiredException::class.java)
        assertThat(storedSession).isNull()
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun `server and transport failures retain the restored session`() = runTest {
        val original = session(expiresAt = NOW)
        storedSession = original
        server.enqueue(MockResponse().setResponseCode(503).setBody("temporarily unavailable"))

        val serverFailure = runCatching { repository().validSession() }.exceptionOrNull()

        assertThat(serverFailure).isInstanceOf(GradeyApiException::class.java)
        assertThat(storedSession).isEqualTo(original)

        val offlineClient = OkHttpClient.Builder()
            .addInterceptor { throw IOException("offline") }
            .build()
        val transportFailure = runCatching {
            repository(okHttpClient = offlineClient).validSession()
        }.exceptionOrNull()

        assertThat(transportFailure).isInstanceOf(IOException::class.java)
        assertThat(storedSession).isEqualTo(original)
    }

    @Test
    fun `profile refresh merges optional fields and persists the account`() = runTest {
        storedSession = session(expiresAt = NOW + 3_600_000)
        server.enqueue(
            jsonResponse(
                userResponse(
                    email = " refreshed@example.com ",
                    metadata = """{"full_name":"Canonical Name","avatar_url":"https://new.example/avatar.png"}""",
                ),
            ),
        )

        val account = repository().refreshAccount()
        val request = server.takeRequest()

        assertThat(request.method).isEqualTo("GET")
        assertThat(request.path).isEqualTo("/auth/v1/user")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer old-access")
        assertThat(account.email).isEqualTo("refreshed@example.com")
        assertThat(account.fullName).isEqualTo("Canonical Name")
        assertThat(account.avatarURL).isEqualTo("https://new.example/avatar.png")
        assertThat(storedSession?.account).isEqualTo(account)
    }

    @Test
    fun `full name update trims validates sends and persists`() = runTest {
        storedSession = session(expiresAt = NOW + 3_600_000)
        server.enqueue(
            jsonResponse(
                userResponse(metadata = """{"full_name":"Updated Name"}"""),
            ),
        )

        val account = repository().updateFullName("  Updated Name  ")
        val request = server.takeRequest()

        assertThat(request.method).isEqualTo("PUT")
        assertThat(request.path).isEqualTo("/auth/v1/user")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer old-access")
        assertThat(request.body.readUtf8()).isEqualTo(
            """{"data":{"full_name":"Updated Name"}}""",
        )
        assertThat(account.fullName).isEqualTo("Updated Name")
        assertThat(storedSession?.account?.fullName).isEqualTo("Updated Name")

        for (invalid in listOf("   ", "x".repeat(81))) {
            val failure = runCatching { repository().updateFullName(invalid) }.exceptionOrNull()
            assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        }
        assertThat(server.requestCount).isEqualTo(1)
    }

    @Test
    fun `Google credential exchange stores a real Supabase session`() = runTest {
        server.enqueue(
            jsonResponse(
                tokenResponse(
                    accessToken = "google-access",
                    refreshToken = "google-refresh",
                    metadata = """{"name":"Server Name"}""",
                ),
            ),
        )

        val result = repository().signInWithGoogle(
            idToken = "google-id-token",
            accessToken = "google-access-token",
            fullName = " Credential Name ",
        )
        val request = server.takeRequest()

        assertThat(request.path).isEqualTo("/auth/v1/token?grant_type=id_token")
        assertThat(request.body.readUtf8()).isEqualTo(
            """{"provider":"google","id_token":"google-id-token","access_token":"google-access-token"}""",
        )
        assertThat(result.account.fullName).isEqualTo("Credential Name")
        assertThat(result.refreshToken).isEqualTo("google-refresh")
        assertThat(storedSession).isEqualTo(result)
    }

    @Test
    fun `provider-specific optional profile shapes do not invalidate authentication`() = runTest {
        server.enqueue(
            jsonResponse(
                """
                {
                  "access_token":"access",
                  "expires_in":3600,
                  "user":{
                    "id":"account-1",
                    "email":{"unexpected":true},
                    "user_metadata":["provider-specific"],
                    "created_at":123
                  }
                }
                """.trimIndent(),
            ),
        )

        val result = repository().signInWithGoogle(
            idToken = "google-id-token",
            fullName = "Credential Name",
        )

        assertThat(result.account.email).isNull()
        assertThat(result.account.fullName).isEqualTo("Credential Name")
        assertThat(result.account.createdAtEpochMillis).isEqualTo(NOW)
        assertThat(storedSession).isEqualTo(result)
    }

    @Test
    fun `sign out waits for refresh and cannot be undone by its late response`() = runTest {
        storedSession = session(expiresAt = NOW)
        val auth = repository()
        server.enqueue(
            jsonResponse(tokenResponse(accessToken = "late-access"))
                .setBodyDelay(150, TimeUnit.MILLISECONDS),
        )
        server.enqueue(jsonResponse("{}"))

        val refresh = async { auth.validSession() }
        yield()
        val signOut = async { auth.signOut() }
        refresh.await()
        signOut.await()

        assertThat(server.takeRequest().path).contains("grant_type=refresh_token")
        val logout = server.takeRequest()
        assertThat(logout.path).isEqualTo("/auth/v1/logout")
        assertThat(logout.getHeader("Authorization")).isEqualTo("Bearer late-access")
        assertThat(storedSession).isNull()
    }

    @Test
    fun `cancelled remote logout still clears the local session`() = runTest {
        storedSession = session(expiresAt = NOW + 3_600_000)
        val auth = repository()
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))

        val signOut = async { auth.signOut() }
        yield()
        assertThat(server.takeRequest(1, TimeUnit.SECONDS)).isNotNull()
        signOut.cancelAndJoin()

        assertThat(storedSession).isNull()
    }

    private fun repository(
        okHttpClient: OkHttpClient = OkHttpClient(),
    ) = SupabaseGradeyAuthRepository(
        configuration = SupabaseConfiguration(
            url = server.url("/").toString().removeSuffix("/"),
            anonKey = "anon-key",
        ),
        sessionStore = { storedSession = it },
        sessionLoader = { storedSession },
        okHttpClient = okHttpClient,
        nowProvider = { NOW },
    )

    private fun session(
        expiresAt: Long,
        refreshToken: String? = "old-refresh",
    ) = GradeyAuthSession(
        accessToken = "old-access",
        refreshToken = refreshToken,
        expiresAtEpochMillis = expiresAt,
        account = GradeyAccount(
            id = "account-1",
            email = "old@example.com",
            fullName = "Stored Name",
            avatarURL = "https://old.example/avatar.png",
            createdAtEpochMillis = 123L,
        ),
    )

    private fun tokenResponse(
        accessToken: String,
        refreshToken: String? = "rotated-refresh",
        metadata: String = "{}",
    ): String =
        """
        {
          "access_token":"$accessToken",
          ${refreshToken?.let { "\"refresh_token\":\"$it\"," }.orEmpty()}
          "token_type":"Bearer",
          "expires_in":3600,
          "user":${userResponse(metadata = metadata)}
        }
        """.trimIndent()

    private fun userResponse(
        email: String = "new@example.com",
        metadata: String = "{}",
    ): String =
        """
        {
          "id":"account-1",
          "email":"$email",
          "user_metadata":$metadata,
          "created_at":"2024-01-02T03:04:05Z"
        }
        """.trimIndent()

    private fun jsonResponse(body: String): MockResponse =
        MockResponse()
            .setResponseCode(200)
            .setHeader("Content-Type", "application/json")
            .setBody(body)

    private companion object {
        const val NOW = 1_800_000_000_000L
    }
}
