package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.domain.LinkedAccountRepository
import com.bukovinafilip.gradey.domain.SchoolDirectoryNameResolver
import com.bukovinafilip.gradey.domain.SchoolReconnectIdentities
import com.bukovinafilip.gradey.model.GradeyAccountSettingsSnapshot
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccountActivation
import com.bukovinafilip.gradey.model.LinkedSchoolTokenPayload
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.UserResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

class GradeyFunctionException(
    val function: String,
    val statusCode: Int,
    val code: String?,
    message: String,
) : IllegalStateException(message)

class SupabaseLinkedAccountRepository(
    private val configuration: SupabaseConfiguration,
    private val authRepository: GradeyAuthRepository,
    private val accountStore: suspend (List<LinkedSchoolAccount>?) -> Unit,
    private val accountLoader: suspend () -> List<LinkedSchoolAccount>,
    private val okHttpClient: OkHttpClient = OkHttpClient(),
) : LinkedAccountRepository {
    private val cacheMutex = Mutex()
    private var cacheEpoch = 0L

    override suspend fun localAccounts(): List<LinkedSchoolAccount> =
        cacheMutex.withLock { accountLoader() }

    override suspend fun refreshAccounts(): GradeyAccountSettingsSnapshot =
        requestAndUpdateCache(
            request = { session -> get("account-settings", session) },
            updateCache = { snapshot -> accountStore(snapshot.linkedAccounts) },
        )

    override suspend fun linkSchoolAccount(
        session: StoredSession,
        user: UserResponse?,
    ): LinkedSchoolAccount = requestAndUpdateCache(
        request = { ownerSession ->
            post(
                function = "link-school-account",
                body = LinkSchoolAccountRequest(
                    provider = session.provider,
                    baseURL = session.baseURL,
                    displayName = user?.fullName?.trim()?.takeIf(String::isNotEmpty)
                        ?: session.linkedAccountDisplayName
                        ?: session.provider.displayName,
                    schoolName = user?.displaySchoolName
                        ?: SchoolDirectoryNameResolver.displayableName(session.linkedAccountSchoolName),
                    providerUserID = user?.userUID,
                    tokenPayload = LinkedSchoolTokenPayload.from(session),
                ),
                session = ownerSession,
            )
        },
        updateCache = ::upsertInCache,
    )

    override suspend fun linkStravaCZAccount(session: StravaCZStoredSession): LinkedSchoolAccount =
        requestAndUpdateCache(
            request = { ownerSession ->
                post(
                    function = "link-stravacz-account",
                    body = LinkStravaCZAccountRequest(
                        displayName = session.displayName,
                        canteenNumber = session.canteenNumber,
                        canteenName = session.canteenName,
                        username = session.username,
                        serviceURL = session.serviceURL,
                        sessionID = session.sessionID,
                    ),
                    session = ownerSession,
                )
            },
            updateCache = ::upsertInCache,
        )

    override suspend fun activateSchoolAccount(accountID: String): LinkedSchoolAccountActivation {
        require(accountID.isNotBlank()) { "Missing linked school account." }
        return requestAndUpdateCache(
            request = { session ->
                post(
                    function = "activate-school-account",
                    body = AccountIDRequest(accountID),
                    session = session,
                )
            },
            updateCache = { activation -> upsertInCache(activation.account) },
        )
    }

    override suspend fun reconnectSchoolAccount(
        accountID: String,
        session: StoredSession,
        user: UserResponse?,
    ): LinkedSchoolAccount {
        require(accountID.isNotBlank()) { "Missing linked school account." }
        val existing = cacheMutex.withLock {
            accountLoader().firstOrNull {
                it.id == accountID && it.provider.isSupportedSchoolProvider
            }
        }
        if (
            !SchoolReconnectIdentities.match(
                existingProviderUserID = existing?.providerUserID,
                candidateProviderUserID = user?.userUID,
            )
        ) {
            throw GradeyFunctionException(
                function = "relink-school-account",
                statusCode = 422,
                code = "SCHOOL_IDENTITY_MISMATCH",
                message = "The refreshed credentials could not be proven to belong to the linked account.",
            )
        }
        return requestAndUpdateCache(
            request = { ownerSession ->
                post(
                    function = "relink-school-account",
                    body = RelinkSchoolAccountRequest(
                        id = accountID,
                        provider = session.provider,
                        baseURL = session.baseURL,
                        displayName = user?.fullName?.trim()?.takeIf(String::isNotEmpty)
                            ?: session.linkedAccountDisplayName
                            ?: session.provider.displayName,
                        schoolName = user?.displaySchoolName
                            ?: SchoolDirectoryNameResolver.displayableName(session.linkedAccountSchoolName),
                        providerUserID = user?.userUID,
                        tokenPayload = LinkedSchoolTokenPayload.from(session),
                    ),
                    session = ownerSession,
                )
            },
            updateCache = ::upsertInCache,
        )
    }

    override suspend fun updateNotificationsEnabled(
        accountID: String,
        enabled: Boolean,
    ): LinkedSchoolAccount {
        require(accountID.isNotBlank()) { "Missing linked school account." }
        return requestAndUpdateCache(
            request = { session ->
                post(
                    function = "update-linked-account-preferences",
                    body = UpdateLinkedAccountPreferencesRequest(accountID, enabled),
                    session = session,
                )
            },
            updateCache = ::upsertInCache,
        )
    }

    override suspend fun unlinkAccount(accountID: String) {
        require(accountID.isNotBlank()) { "Missing linked school account." }
        requestAndUpdateCache(
            request = { session ->
                postIgnoringResponse(
                    function = "unlink-account",
                    body = AccountIDRequest(accountID),
                    session = session,
                )
            },
            updateCache = {
                accountStore(accountLoader().filterNot { it.id == accountID })
            },
        )
    }

    override suspend fun unlinkAccountForSignedOutSession(
        accountID: String,
        session: GradeyAuthSession,
    ) {
        require(accountID.isNotBlank()) { "Missing linked school account." }
        postIgnoringResponse(
            function = "unlink-account",
            body = AccountIDRequest(accountID),
            session = session,
        )
    }

    override suspend fun clearLocalAccounts() {
        cacheMutex.withLock {
            cacheEpoch += 1
            accountStore(null)
        }
    }

    private suspend fun upsertInCache(account: LinkedSchoolAccount) {
        val updated = accountLoader()
            .filterNot { it.id == account.id }
            .plus(account)
            .sortedBy { it.displayName.lowercase() }
        accountStore(updated)
    }

    private suspend fun <Response> requestAndUpdateCache(
        request: suspend (GradeyAuthSession) -> Response,
        updateCache: suspend (Response) -> Unit,
    ): Response {
        val ownerCacheEpoch = cacheMutex.withLock { cacheEpoch }
        val ownerSession = authRepository.validSession()
        val response = request(ownerSession)
        cacheMutex.withLock {
            val currentSession = authRepository.bootstrapSession()
            if (ownerCacheEpoch != cacheEpoch || !ownerSession.isSameSessionAs(currentSession)) {
                throw GradeyIdentityChangedException()
            }
            updateCache(response)
        }
        return response
    }

    private suspend inline fun <reified Response> get(
        function: String,
        session: GradeyAuthSession? = null,
    ): Response = GradeyJson.decodeFromString(sendData(function, "GET", null, session))

    private suspend inline fun <reified Response, reified Body> post(
        function: String,
        body: Body,
        session: GradeyAuthSession? = null,
    ): Response = GradeyJson.decodeFromString(
        sendData(function, "POST", GradeyJson.encodeToString(body), session),
    )

    private suspend inline fun <reified Body> postIgnoringResponse(
        function: String,
        body: Body,
        session: GradeyAuthSession? = null,
    ) {
        sendData(function, "POST", GradeyJson.encodeToString(body), session)
    }

    private suspend fun sendData(
        function: String,
        method: String,
        body: String?,
        sessionOverride: GradeyAuthSession? = null,
    ): String {
        check(configuration.isConfigured) { "Gradey ID is not configured in this build." }
        val session = sessionOverride ?: authRepository.validSession()
        val builder = Request.Builder()
            .url(configuration.url.appendPath("functions/v1/$function"))
            .header("Accept", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", session.authorizationHeader)
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(jsonBody(body ?: "{}"))
            else -> error("Unsupported Gradey function method: $method")
        }
        if (body != null) builder.header("Content-Type", "application/json")
        return try {
            okHttpClient.executeString(builder.build())
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeyApiException) {
            throw error.asFunctionException(function)
        }
    }
}

private fun GradeyAuthSession.isSameSessionAs(current: GradeyAuthSession?): Boolean =
    current != null &&
        account.id == current.account.id &&
        accessToken == current.accessToken

@Serializable
private data class LinkSchoolAccountRequest(
    val provider: SchoolProvider,
    @SerialName("base_url")
    val baseURL: String,
    @SerialName("display_name")
    val displayName: String,
    @SerialName("school_name")
    val schoolName: String?,
    @SerialName("provider_user_id")
    val providerUserID: String?,
    @SerialName("token_payload")
    val tokenPayload: LinkedSchoolTokenPayload,
)

@Serializable
private data class LinkStravaCZAccountRequest(
    @SerialName("display_name")
    val displayName: String,
    @SerialName("canteen_number")
    val canteenNumber: String,
    @SerialName("canteen_name")
    val canteenName: String?,
    val username: String,
    @SerialName("service_url")
    val serviceURL: String,
    @SerialName("session_id")
    val sessionID: String,
)

@Serializable
private data class RelinkSchoolAccountRequest(
    val id: String,
    val provider: SchoolProvider,
    @SerialName("base_url")
    val baseURL: String,
    @SerialName("display_name")
    val displayName: String,
    @SerialName("school_name")
    val schoolName: String?,
    @SerialName("provider_user_id")
    val providerUserID: String?,
    @SerialName("token_payload")
    val tokenPayload: LinkedSchoolTokenPayload,
)

@Serializable
private data class AccountIDRequest(val id: String)

@Serializable
private data class UpdateLinkedAccountPreferencesRequest(
    val id: String,
    val notificationsEnabled: Boolean,
)

private fun GradeyApiException.asFunctionException(function: String): GradeyFunctionException {
    val objectBody = responseBody?.let { runCatching { GradeyJson.parseToJsonElement(it) as? JsonObject }.getOrNull() }
    val code = objectBody.string("code")
    val serverMessage = objectBody.string("error") ?: objectBody.string("message")
    val safeMessage = serverMessage
        ?.trim()
        ?.takeIf { it.isNotEmpty() && !it.contains('<') && !it.contains('>') }
        ?.take(240)
        ?: "Gradey could not complete this account request. Please try again."
    return GradeyFunctionException(function, statusCode, code, safeMessage)
}

private fun JsonObject?.string(key: String): String? =
    (this?.get(key) as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.contentOrNull
