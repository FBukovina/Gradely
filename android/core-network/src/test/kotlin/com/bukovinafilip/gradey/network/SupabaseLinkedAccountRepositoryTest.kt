package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class SupabaseLinkedAccountRepositoryTest {
    private lateinit var server: MockWebServer
    private var storedAccounts = emptyList<LinkedSchoolAccount>()
    private var accountStoreWrites = 0

    @Before
    fun setUp() {
        storedAccounts = emptyList()
        accountStoreWrites = 0
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
    fun `clear remains final writer when a legacy cache migration is already loading`() = runTest {
        storedAccounts = listOf(account("legacy-account-a"))
        val loaderStarted = CompletableDeferred<Unit>()
        val releaseLoader = CompletableDeferred<Unit>()
        val repository = repository(
            accountLoader = {
                val legacyAccounts = storedAccounts
                loaderStarted.complete(Unit)
                releaseLoader.await()
                storedAccounts = legacyAccounts
                legacyAccounts
            },
        )

        val heldLoad = async(start = CoroutineStart.UNDISPATCHED) { repository.localAccounts() }
        loaderStarted.await()
        val clear = async(start = CoroutineStart.UNDISPATCHED) { repository.clearLocalAccounts() }
        releaseLoader.complete(Unit)

        assertThat(heldLoad.await().map { it.id }).containsExactly("legacy-account-a")
        clear.await()
        assertThat(storedAccounts).isEmpty()
        assertThat(accountStoreWrites).isEqualTo(1)
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
        assertThat(accountStoreWrites).isEqualTo(1)
    }

    @Test
    fun `held account refresh cannot overwrite replacement identity cache`() = runTest {
        val dispatcher = HeldResponseDispatcher(
            jsonResponse(settingsResponse(accountID = "account-a", activeID = "account-a")),
        )
        server.dispatcher = dispatcher
        val authRepository = FakeAuthRepository()
        val repository = repository(authRepository)

        val heldRefresh = async { repository.refreshAccounts() }
        dispatcher.requestStarted.await()
        authRepository.signOut()
        authRepository.replaceSession(fakeAuthSession(accountID = "gradey-b", accessToken = "auth-b"))
        storedAccounts = listOf(account("account-b"))
        dispatcher.release()

        val failure = runCatching { heldRefresh.await() }.exceptionOrNull()
        val request = server.takeRequest()

        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer auth-access")
        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts.map { it.id }).containsExactly("account-b")
        assertThat(accountStoreWrites).isEqualTo(0)
    }

    @Test
    fun `held account refresh cannot repopulate cache cleared before identity adoption`() = runTest {
        storedAccounts = listOf(account("account-a"))
        val dispatcher = HeldResponseDispatcher(
            jsonResponse(settingsResponse(accountID = "account-a", activeID = "account-a")),
        )
        server.dispatcher = dispatcher
        val repository = repository()

        val heldRefresh = async { repository.refreshAccounts() }
        dispatcher.requestStarted.await()
        repository.clearLocalAccounts()
        dispatcher.release()

        val failure = runCatching { heldRefresh.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts).isEmpty()
        assertThat(accountStoreWrites).isEqualTo(1)
    }

    @Test
    fun `held link cannot upsert into replacement identity cache`() = runTest {
        val dispatcher = HeldResponseDispatcher(jsonResponse(accountResponse("account-a")))
        server.dispatcher = dispatcher
        val authRepository = FakeAuthRepository()
        val repository = repository(authRepository)

        val heldLink = async { repository.linkSchoolAccount(schoolSession(), user = null) }
        dispatcher.requestStarted.await()
        authRepository.signOut()
        authRepository.replaceSession(fakeAuthSession(accountID = "gradey-b", accessToken = "auth-b"))
        storedAccounts = listOf(account("account-b"))
        dispatcher.release()

        val failure = runCatching { heldLink.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts.map { it.id }).containsExactly("account-b")
        assertThat(accountStoreWrites).isEqualTo(0)
    }

    @Test
    fun `held link cannot upsert after cache is cleared with same auth session`() = runTest {
        storedAccounts = listOf(account("account-a"))
        val dispatcher = HeldResponseDispatcher(jsonResponse(accountResponse("stale-link")))
        server.dispatcher = dispatcher
        val repository = repository()

        val heldLink = async { repository.linkSchoolAccount(schoolSession(), user = null) }
        dispatcher.requestStarted.await()
        repository.clearLocalAccounts()
        dispatcher.release()

        val failure = runCatching { heldLink.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts).isEmpty()
        assertThat(accountStoreWrites).isEqualTo(1)
    }

    @Test
    fun `held unlink cannot delete from replacement identity cache`() = runTest {
        val dispatcher = HeldResponseDispatcher(jsonResponse("{}"))
        server.dispatcher = dispatcher
        val authRepository = FakeAuthRepository()
        val repository = repository(authRepository)

        val heldUnlink = async { repository.unlinkAccount("shared-account") }
        dispatcher.requestStarted.await()
        authRepository.signOut()
        authRepository.replaceSession(fakeAuthSession(accountID = "gradey-b", accessToken = "auth-b"))
        storedAccounts = listOf(account("shared-account"))
        dispatcher.release()

        val failure = runCatching { heldUnlink.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts.map { it.id }).containsExactly("shared-account")
        assertThat(accountStoreWrites).isEqualTo(0)
    }

    @Test
    fun `held unlink cannot delete cache adopted after clear with same auth session`() = runTest {
        storedAccounts = listOf(account("shared-account"))
        val dispatcher = HeldResponseDispatcher(jsonResponse("{}"))
        server.dispatcher = dispatcher
        val repository = repository()

        val heldUnlink = async { repository.unlinkAccount("shared-account") }
        dispatcher.requestStarted.await()
        repository.clearLocalAccounts()
        storedAccounts = listOf(account("adopted-account"))
        dispatcher.release()

        val failure = runCatching { heldUnlink.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(storedAccounts.map { it.id }).containsExactly("adopted-account")
        assertThat(accountStoreWrites).isEqualTo(1)
    }

    @Test
    fun `signed out session unlink uses captured identity without touching replacement cache`() = runTest {
        val authRepository = FakeAuthRepository()
        val accountASession = authRepository.validSession()
        authRepository.replaceSession(fakeAuthSession(accountID = "gradey-b", accessToken = "auth-b"))
        storedAccounts = listOf(account("account-b"))
        server.enqueue(jsonResponse("{}"))

        repository(authRepository).unlinkAccountForSignedOutSession(
            accountID = "account-a-meals",
            session = accountASession,
        )
        val request = server.takeRequest()

        assertThat(request.path).isEqualTo("/functions/v1/unlink-account")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer auth-access")
        assertThat(request.body.readUtf8()).isEqualTo("""{"id":"account-a-meals"}""")
        assertThat(storedAccounts.map { it.id }).containsExactly("account-b")
        assertThat(accountStoreWrites).isEqualTo(0)
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
    fun `school link and reconnect never send placeholder school metadata`() = runTest {
        val session = schoolSession().copy(linkedAccountSchoolName = " NÁzev   školy ")
        val user = UserResponse(
            fullName = "Student Name",
            schoolName = "název školy",
            userUID = "provider-user",
        )
        server.enqueue(jsonResponse(accountResponse("linked")))
        server.enqueue(jsonResponse(accountResponse("linked")))

        repository().linkSchoolAccount(session, user)
        val linkRequest = server.takeRequest()
        repository().reconnectSchoolAccount("linked", session, user)
        val reconnectRequest = server.takeRequest()

        val linkBody = GradeyJson.parseToJsonElement(linkRequest.body.readUtf8()).jsonObject
        val reconnectBody = GradeyJson.parseToJsonElement(reconnectRequest.body.readUtf8()).jsonObject
        assertThat(linkBody).doesNotContainKey("school_name")
        assertThat(reconnectBody).doesNotContainKey("school_name")
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
    fun `reconnect rejects missing blank and mismatched provider identity before network or cache write`() = runTest {
        val original = account("school", status = LinkedAccountStatus.ACTION_REQUIRED)
        storedAccounts = listOf(original)
        val candidates = listOf(
            null,
            UserResponse("Student", userUID = null),
            UserResponse("Student", userUID = ""),
            UserResponse("Student", userUID = "   "),
            UserResponse("Another student", userUID = "another-provider-user"),
        )

        candidates.forEach { candidate ->
            val failure = runCatching {
                repository().reconnectSchoolAccount(
                    accountID = original.id,
                    session = schoolSession(),
                    user = candidate,
                )
            }.exceptionOrNull()

            assertThat(failure).isInstanceOf(GradeyFunctionException::class.java)
            failure as GradeyFunctionException
            assertThat(failure.function).isEqualTo("relink-school-account")
            assertThat(failure.statusCode).isEqualTo(422)
            assertThat(failure.code).isEqualTo("SCHOOL_IDENTITY_MISMATCH")
        }

        assertThat(server.requestCount).isEqualTo(0)
        assertThat(accountStoreWrites).isEqualTo(0)
        assertThat(storedAccounts).containsExactly(original)
    }

    @Test
    fun `reconnect rejects an existing account without a provider identity`() = runTest {
        val original = account("school", status = LinkedAccountStatus.ACTION_REQUIRED)
            .copy(providerUserID = " ")
        storedAccounts = listOf(original)

        val failure = runCatching {
            repository().reconnectSchoolAccount(
                accountID = original.id,
                session = schoolSession(),
                user = UserResponse("Student", userUID = "provider-user"),
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyFunctionException::class.java)
        assertThat(server.requestCount).isEqualTo(0)
        assertThat(accountStoreWrites).isEqualTo(0)
        assertThat(storedAccounts).containsExactly(original)
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

    private fun repository(
        authRepository: GradeyAuthRepository = FakeAuthRepository(),
        accountLoader: suspend () -> List<LinkedSchoolAccount> = { storedAccounts },
    ) = SupabaseLinkedAccountRepository(
        configuration = SupabaseConfiguration(server.url("/").toString(), "anon-key"),
        authRepository = authRepository,
        accountStore = {
            storedAccounts = it.orEmpty()
            accountStoreWrites += 1
        },
        accountLoader = accountLoader,
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

private class HeldResponseDispatcher(
    private val response: MockResponse,
) : Dispatcher() {
    val requestStarted = CompletableDeferred<Unit>()
    private val responseRelease = CountDownLatch(1)

    override fun dispatch(request: RecordedRequest): MockResponse {
        requestStarted.complete(Unit)
        check(responseRelease.await(5, TimeUnit.SECONDS)) {
            "Timed out waiting to release a held linked-account response."
        }
        return response
    }

    fun release() {
        responseRelease.countDown()
    }
}

private class FakeAuthRepository(
    initialSession: GradeyAuthSession = fakeAuthSession(),
) : GradeyAuthRepository {
    @Volatile
    private var session: GradeyAuthSession? = initialSession

    fun replaceSession(replacement: GradeyAuthSession) {
        session = replacement
    }

    override suspend fun bootstrapSession() = session
    override suspend fun validSession() = session ?: throw GradeySessionExpiredException()
    override suspend fun refreshAccount() = validSession().account
    override suspend fun updateFullName(fullName: String) = validSession().account.copy(fullName = fullName)
    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?) = validSession()
    override suspend fun signOut() {
        session = null
    }
}

private fun fakeAuthSession(
    accountID: String = "gradey-user",
    accessToken: String = "auth-access",
) = GradeyAuthSession(
    accessToken = accessToken,
    refreshToken = "auth-refresh",
    account = GradeyAccount(accountID),
)

private fun JsonObject.stringValue(key: String): String = getValue(key).jsonPrimitive.content
private fun JsonObject.objectValue(key: String): JsonObject = getValue(key).jsonObject
