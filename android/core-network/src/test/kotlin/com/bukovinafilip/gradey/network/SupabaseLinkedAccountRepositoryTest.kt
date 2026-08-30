package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.UserResponse
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class SupabaseLinkedAccountRepositoryTest {
    private lateinit var server: MockWebServer
    private var storedAccounts = emptyList<LinkedSchoolAccount>()

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
    fun `local accounts are cache only and do not make a cloud request`() = runTest {
        storedAccounts = listOf(account("cached"))

        val result = repository().localAccounts()

        assertThat(result).isEqualTo(storedAccounts)
        assertThat(server.requestCount).isEqualTo(0)
    }

    @Test
    fun `account settings refresh uses Gradey auth and replaces the encrypted snapshot`() = runTest {
        storedAccounts = listOf(account("stale"))
        server.enqueue(jsonResponse(settingsResponse(accountID = "remote", activeID = "remote")))

        val snapshot = repository().refreshAccounts()
        val request = server.takeRequest()

        assertThat(request.method).isEqualTo("GET")
        assertThat(request.path).isEqualTo("/functions/v1/account-settings")
        assertThat(request.getHeader("apikey")).isEqualTo("anon-key")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer auth-access")
        assertThat(snapshot.activeSchoolAccountID).isEqualTo("remote")
        assertThat(snapshot.linkedAccounts.single().status).isEqualTo(LinkedAccountStatus.ACTIVE)
        assertThat(storedAccounts.map { it.id }).containsExactly("remote")
    }

    @Test
    fun `account settings preserve providers managed by iOS without activating them on Android`() = runTest {
        server.enqueue(
            jsonResponse(
                settingsResponse(accountID = "school", activeID = "school").replace(
                    "\"linked_accounts\":[${accountResponse("school")}],",
                    """
                    "linked_accounts":[
                      ${accountResponse("school")},
                      ${accountResponse("legacy-edupage").replace("\"bakalari\"", "\"eduPage\"")},
                      ${accountResponse("canteen").replace("\"bakalari\"", "\"stravaCZ\"")}
                    ],
                    """.trimIndent(),
                ),
            ),
        )

        val accounts = repository().refreshAccounts().linkedAccounts

        assertThat(accounts.map { it.provider }).containsExactly(
            LinkedAccountProvider.BAKALARI,
            LinkedAccountProvider.EDU_PAGE,
            LinkedAccountProvider.STRAVA_CZ,
        ).inOrder()
        assertThat(accounts.filter { it.provider.isSupportedSchoolProvider }.map { it.id })
            .containsExactly("school")
    }

    @Test
    fun `school link sends the same sanitized Bakalari payload as iOS and caches success`() = runTest {
        server.enqueue(jsonResponse(accountResponse("linked")))

        val result = repository().linkSchoolAccount(
            session = schoolSession(),
            user = UserResponse(
                fullName = "Student Name",
                schoolName = "Fallback school",
                userUID = "provider-user",
                schoolOrganizationName = "Canonical School",
            ),
        )
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject
        val payload = body.objectValue("token_payload")

        assertThat(request.path).isEqualTo("/functions/v1/link-school-account")
        assertThat(body.stringValue("provider")).isEqualTo("bakalari")
        assertThat(body.stringValue("base_url")).isEqualTo("https://school.example.cz")
        assertThat(body.stringValue("display_name")).isEqualTo("Student Name")
        assertThat(body.stringValue("school_name")).isEqualTo("Canonical School")
        assertThat(body.stringValue("provider_user_id")).isEqualTo("provider-user")
        assertThat(payload.stringValue("baseURL")).isEqualTo("https://school.example.cz")
        assertThat(payload.stringValue("accessToken")).isEqualTo("school-access")
        assertThat(payload.stringValue("refreshToken")).isEqualTo("school-refresh")
        assertThat(payload.objectValue("bakalari").stringValue("username")).isEqualTo("student")
        assertThat(payload.objectValue("bakalari").stringValue("password")).isEqualTo("secret")
        assertThat(result.id).isEqualTo("linked")
        assertThat(storedAccounts.single().id).isEqualTo("linked")
    }

    @Test
    fun `Strava link sends the iOS compatible canteen payload and caches success`() = runTest {
        server.enqueue(
            jsonResponse(
                accountResponse("canteen")
                    .replace("\"bakalari\"", "\"stravaCZ\"")
                    .replace("\"schoolName\":\"School\"", "\"schoolName\":null")
                    .replace("\"canteenName\":null", "\"canteenName\":\"School Canteen\""),
            ),
        )

        val result = repository().linkStravaCZAccount(
            StravaCZStoredSession(
                sessionID = "strava-session",
                serviceURL = "https://s5.strava.cz/FOOD",
                canteenNumber = "1234",
                username = "student",
                fullName = "Student Name",
                canteenName = "School Canteen",
            ),
        )
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject

        assertThat(request.path).isEqualTo("/functions/v1/link-stravacz-account")
        assertThat(body.stringValue("display_name")).isEqualTo("Student Name")
        assertThat(body.stringValue("canteen_number")).isEqualTo("1234")
        assertThat(body.stringValue("canteen_name")).isEqualTo("School Canteen")
        assertThat(body.stringValue("username")).isEqualTo("student")
        assertThat(body.stringValue("service_url")).isEqualTo("https://s5.strava.cz/FOOD")
        assertThat(body.stringValue("session_id")).isEqualTo("strava-session")
        assertThat(result.provider).isEqualTo(LinkedAccountProvider.STRAVA_CZ)
        assertThat(storedAccounts.single().id).isEqualTo("canteen")
    }

    @Test
    fun `activation decodes cloud credentials and updates cached status`() = runTest {
        storedAccounts = listOf(account("school", status = LinkedAccountStatus.ACTION_REQUIRED))
        server.enqueue(
            jsonResponse(
                """
                {
                  "account":${accountResponse("school")},
                  "token_payload":{
                    "provider":"bakalari",
                    "baseURL":"https://school.example.cz",
                    "accessToken":"cloud-access",
                    "refreshToken":"cloud-refresh",
                    "tokenType":"Bearer",
                    "expiresAt":"2026-08-30T12:00:00Z",
                    "bakalari":{"username":"student","password":"secret"}
                  }
                }
                """.trimIndent(),
            ),
        )

        val activation = repository().activateSchoolAccount("school")
        val request = server.takeRequest()
        val storedSession = activation.tokenPayload.makeStoredSession(activation.account)

        assertThat(request.body.readUtf8()).isEqualTo("""{"id":"school"}""")
        assertThat(storedSession.linkedAccountID).isEqualTo("school")
        assertThat(storedSession.bakalari?.password).isEqualTo("secret")
        assertThat(storedSession.expiresAtEpochMillis).isEqualTo(1788091200000L)
        assertThat(storedAccounts.single().status).isEqualTo(LinkedAccountStatus.ACTIVE)
    }

    @Test
    fun `reconnect scopes fresh credentials to the requested existing account`() = runTest {
        storedAccounts = listOf(account("school", status = LinkedAccountStatus.ACTION_REQUIRED))
        server.enqueue(jsonResponse(accountResponse("school")))

        val result = repository().reconnectSchoolAccount(
            accountID = "school",
            session = schoolSession(),
            user = UserResponse("Student Name", userUID = "provider-user"),
        )
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject

        assertThat(request.path).isEqualTo("/functions/v1/relink-school-account")
        assertThat(body.stringValue("id")).isEqualTo("school")
        assertThat(body.stringValue("provider_user_id")).isEqualTo("provider-user")
        assertThat(body.objectValue("token_payload").objectValue("bakalari").stringValue("username"))
            .isEqualTo("student")
        assertThat(result.status).isEqualTo(LinkedAccountStatus.ACTIVE)
        assertThat(storedAccounts.single().status).isEqualTo(LinkedAccountStatus.ACTIVE)
    }

    @Test
    fun `preference update and unlink only mutate cache after remote success`() = runTest {
        storedAccounts = listOf(account("school"))
        server.enqueue(jsonResponse(accountResponse("school", notificationsEnabled = false)))
        server.enqueue(jsonResponse("{}"))

        val updated = repository().updateNotificationsEnabled("school", false)
        val updateRequest = server.takeRequest()
        repository().unlinkAccount("school")
        val unlinkRequest = server.takeRequest()

        assertThat(updated.notificationsEnabled).isFalse()
        assertThat(updateRequest.body.readUtf8())
            .isEqualTo("""{"id":"school","notificationsEnabled":false}""")
        assertThat(unlinkRequest.path).isEqualTo("/functions/v1/unlink-account")
        assertThat(storedAccounts).isEmpty()
    }

    @Test
    fun `failed mutation retains cache and exposes only a bounded safe server message`() = runTest {
        storedAccounts = listOf(account("school"))
        server.enqueue(
            MockResponse().setResponseCode(503).setBody(
                """{"error":"Temporarily unavailable","code":"RETRY_LATER"}""",
            ),
        )

        val failure = runCatching { repository().unlinkAccount("school") }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyFunctionException::class.java)
        failure as GradeyFunctionException
        assertThat(failure.statusCode).isEqualTo(503)
        assertThat(failure.code).isEqualTo("RETRY_LATER")
        assertThat(failure.message).isEqualTo("Temporarily unavailable")
        assertThat(storedAccounts.map { it.id }).containsExactly("school")

        server.enqueue(MockResponse().setResponseCode(500).setBody("<html>secret diagnostic</html>"))
        val htmlFailure = runCatching { repository().unlinkAccount("school") }.exceptionOrNull()
        assertThat(htmlFailure?.message).doesNotContain("secret diagnostic")
    }

    private fun repository() = SupabaseLinkedAccountRepository(
        configuration = SupabaseConfiguration(server.url("/").toString(), "anon-key"),
        authRepository = FakeAuthRepository(),
        accountStore = { storedAccounts = it.orEmpty() },
        accountLoader = { storedAccounts },
    )

    private fun schoolSession() = StoredSession(
        accessToken = "school-access",
        refreshToken = "school-refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = 1_788_091_200_000L,
        baseURL = "https://school.example.cz",
        bakalari = BakalariCredentials("student", "secret"),
    )

    private fun account(
        id: String,
        status: LinkedAccountStatus = LinkedAccountStatus.ACTIVE,
    ) = LinkedSchoolAccount(
        id = id,
        provider = LinkedAccountProvider.BAKALARI,
        providerUserID = "provider-user",
        displayName = "Student",
        schoolName = "School",
        status = status,
    )

    private fun settingsResponse(accountID: String, activeID: String) =
        """
        {
          "active_school_account_id":"$activeID",
          "linked_accounts":[${accountResponse(accountID)}],
          "notification_preferences":{
            "new_marks_enabled":true,
            "lock_screen_detail":"mark_and_subject",
            "quiet_hours_enabled":false,
            "quiet_hours_start_minute":1320,
            "quiet_hours_end_minute":360,
            "quiet_hours_time_zone":"Europe/Prague"
          }
        }
        """.trimIndent()

    private fun accountResponse(id: String, notificationsEnabled: Boolean = true) =
        """
        {
          "id":"$id",
          "provider":"bakalari",
          "providerUserID":"provider-user",
          "displayName":"Student",
          "schoolName":"School",
          "canteenName":null,
          "status":"active",
          "notificationsEnabled":$notificationsEnabled,
          "lastPolledAt":null,
          "lastSyncedAt":"2026-08-30T10:00:00Z",
          "actionRequiredReason":null
        }
        """.trimIndent()

    private fun jsonResponse(body: String) = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)
}

private class FakeAuthRepository : GradeyAuthRepository {
    private val session = GradeyAuthSession(
        accessToken = "auth-access",
        refreshToken = "auth-refresh",
        account = GradeyAccount("gradey-user"),
    )

    override suspend fun bootstrapSession() = session
    override suspend fun validSession() = session
    override suspend fun refreshAccount() = session.account
    override suspend fun updateFullName(fullName: String) = session.account.copy(fullName = fullName)
    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?) = session
    override suspend fun signOut() = Unit
}

private fun JsonObject.stringValue(key: String): String = getValue(key).jsonPrimitive.content
private fun JsonObject.objectValue(key: String): JsonObject = getValue(key).jsonObject
