package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.NotificationPreferences
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.time.Instant

data class SupabaseConfiguration(
    val url: String,
    val anonKey: String,
) {
    val isConfigured: Boolean get() = url.isNotBlank() && anonKey.isNotBlank()
}

class SupabaseGradeyAuthRepository(
    private val configuration: SupabaseConfiguration,
    private val sessionStore: suspend (GradeyAuthSession?) -> Unit,
    private val sessionLoader: suspend () -> GradeyAuthSession?,
    private val okHttpClient: OkHttpClient = OkHttpClient(),
    private val nowProvider: () -> Long = System::currentTimeMillis,
) : GradeyAuthRepository {
    private val refreshMutex = Mutex()

    override suspend fun bootstrapSession(): GradeyAuthSession? = sessionLoader()

    override suspend fun validSession(): GradeyAuthSession {
        val restored = sessionLoader() ?: throw GradeySessionExpiredException()
        if (!needsRefresh(restored)) return restored

        return refreshMutex.withLock {
            val current = sessionLoader() ?: throw GradeySessionExpiredException()
            if (!needsRefresh(current)) return@withLock current

            val refreshToken = current.refreshToken?.trim()?.takeIf(String::isNotEmpty)
                ?: expireSession()
            try {
                val response: SupabaseTokenResponse = send(
                    path = "auth/v1/token?grant_type=refresh_token",
                    method = "POST",
                    body = GradeyJson.encodeToString(RefreshTokenRequest(refreshToken)),
                )
                val refreshed = response.makeSession(
                    previous = current,
                    nowEpochMillis = nowProvider(),
                )
                sessionStore(refreshed)
                refreshed
            } catch (error: CancellationException) {
                throw error
            } catch (error: GradeyApiException) {
                if (error.statusCode == 400 || error.statusCode == 401) {
                    expireSession(error)
                }
                throw error
            }
        }
    }

    override suspend fun refreshAccount(): GradeyAccount {
        val session = validSession()
        val response: SupabaseUserResponse = send(
            path = "auth/v1/user",
            method = "GET",
            authorization = session.authorizationHeader,
        )
        return persistAccount(response, session)
    }

    override suspend fun updateFullName(fullName: String): GradeyAccount {
        val normalizedName = fullName.trim()
        require(normalizedName.length in 1..80) {
            "Your name must be between 1 and 80 characters."
        }
        val session = validSession()
        val response: SupabaseUserResponse = send(
            path = "auth/v1/user",
            method = "PUT",
            authorization = session.authorizationHeader,
            body = GradeyJson.encodeToString(
                UpdateUserRequest(UpdateUserMetadata(normalizedName)),
            ),
        )
        return persistAccount(response, session)
    }

    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?): GradeyAuthSession {
        require(idToken.isNotBlank()) { "Missing Google identity token." }
        ensureConfigured()
        return refreshMutex.withLock {
            val response: SupabaseTokenResponse = send(
                path = "auth/v1/token?grant_type=id_token",
                method = "POST",
                body = GradeyJson.encodeToString(SignInWithIDTokenRequest("google", idToken, accessToken)),
            )
            val session = response.makeSession(
                suppliedFullName = fullName,
                nowEpochMillis = nowProvider(),
            )
            sessionStore(session)
            session
        }
    }

    override suspend fun signOut() {
        refreshMutex.withLock {
            val session = sessionLoader()
            var cancellation: CancellationException? = null
            if (session != null && configuration.isConfigured) {
                try {
                    val request = Request.Builder()
                        .url(configuration.url.appendPath("auth/v1/logout"))
                        .post(jsonBody("{}"))
                        .header("apikey", configuration.anonKey)
                        .header("Authorization", session.authorizationHeader)
                        .build()
                    okHttpClient.executeString(request)
                } catch (error: CancellationException) {
                    cancellation = error
                } catch (_: Throwable) {
                    // Remote logout is best effort. Local sign-out must still finish.
                }
            }
            withContext(NonCancellable) { sessionStore(null) }
            cancellation?.let { throw it }
        }
    }

    private suspend inline fun <reified T> send(
        path: String,
        method: String,
        body: String? = null,
        authorization: String? = null,
    ): T {
        ensureConfigured()
        val builder = Request.Builder()
            .url(configuration.url.appendPath(path))
            .header("Accept", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", authorization ?: "Bearer ${configuration.anonKey}")
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(jsonBody(body ?: "{}"))
            "PUT" -> builder.put(jsonBody(body ?: "{}"))
            else -> error("Unsupported Gradey ID request method: $method")
        }
        if (body != null) builder.header("Content-Type", "application/json")
        val request = builder.build()
        return GradeyJson.decodeFromString(okHttpClient.executeString(request))
    }

    private fun needsRefresh(session: GradeyAuthSession): Boolean =
        session.expiresAtEpochMillis?.let { it <= nowProvider() + REFRESH_LEEWAY_MILLIS } ?: false

    private suspend fun expireSession(cause: Throwable? = null): Nothing {
        sessionStore(null)
        throw GradeySessionExpiredException(cause)
    }

    private suspend fun persistAccount(
        response: SupabaseUserResponse,
        sessionUsedForRequest: GradeyAuthSession,
    ): GradeyAccount = refreshMutex.withLock {
        val current = sessionLoader()
        if (
            current == null ||
            current.account.id != sessionUsedForRequest.account.id ||
            current.accessToken != sessionUsedForRequest.accessToken
        ) {
            throw GradeySessionExpiredException()
        }
        val account = response.mergeInto(current.account, nowProvider())
        sessionStore(current.copy(account = account))
        account
    }

    private fun ensureConfigured() {
        if (!configuration.isConfigured) throw IllegalStateException("Supabase is not configured.")
    }

    private companion object {
        const val REFRESH_LEEWAY_MILLIS = 60_000L
    }
}

class SupabaseDevicePushTokenClient(
    private val configuration: SupabaseConfiguration,
    private val okHttpClient: OkHttpClient = OkHttpClient(),
) : DevicePushTokenClient {
    override suspend fun registerDeviceToken(token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) {
        send(
            function = "register-device",
            session = gradeySession,
            body = RegisterDeviceRequest(token, platform, environment),
        )
    }

    override suspend fun updateNotificationPreferences(preferences: NotificationPreferences, gradeySession: GradeyAuthSession) {
        send(
            function = "update-notification-preferences",
            session = gradeySession,
            body = preferences,
        )
    }

    override suspend fun requestDataExport(gradeySession: GradeyAuthSession): String = send(
        function = "request-data-export",
        session = gradeySession,
        body = EmptyFunctionRequest,
    )

    override suspend fun deleteAccount(gradeySession: GradeyAuthSession) {
        send(
            function = "delete-account",
            session = gradeySession,
            body = EmptyFunctionRequest,
        )
    }

    private suspend inline fun <reified T> send(function: String, session: GradeyAuthSession, body: T): String {
        if (!configuration.isConfigured) throw IllegalStateException("Supabase is not configured.")
        val request = Request.Builder()
            .url(configuration.url.appendPath("functions/v1/$function"))
            .post(jsonBody(GradeyJson.encodeToString(body)))
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", session.authorizationHeader)
            .build()
        return okHttpClient.executeString(request)
    }
}

@Serializable
private data object EmptyFunctionRequest

@Serializable
private data class SignInWithIDTokenRequest(
    val provider: String,
    @SerialName("id_token")
    val idToken: String,
    @SerialName("access_token")
    val accessToken: String? = null,
)

@Serializable
private data class RefreshTokenRequest(
    @SerialName("refresh_token")
    val refreshToken: String,
)

@Serializable
private data class UpdateUserRequest(
    val data: UpdateUserMetadata,
)

@Serializable
private data class UpdateUserMetadata(
    @SerialName("full_name")
    val fullName: String,
)

@Serializable
private data class SupabaseTokenResponse(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String? = null,
    @SerialName("token_type")
    val tokenType: String? = null,
    @SerialName("expires_in")
    val expiresIn: Long? = null,
    val user: SupabaseUserResponse,
) {
    fun makeSession(
        previous: GradeyAuthSession? = null,
        suppliedFullName: String? = null,
        nowEpochMillis: Long,
    ): GradeyAuthSession {
        require(user.id.isNotBlank() && (previous == null || previous.account.id == user.id)) {
            "Gradey ID returned an invalid account."
        }
        val freshAccount = user.makeAccount(nowEpochMillis)
        val account = freshAccount.copy(
            email = freshAccount.email.nonEmptyOrNull() ?: previous?.account?.email,
            fullName = suppliedFullName.nonEmptyOrNull()
                ?: freshAccount.fullName.nonEmptyOrNull()
                ?: previous?.account?.fullName,
            avatarURL = freshAccount.avatarURL.nonEmptyOrNull() ?: previous?.account?.avatarURL,
            createdAtEpochMillis = user.createdAtEpochMillis()
                ?: previous?.account?.createdAtEpochMillis
                ?: nowEpochMillis,
        )
        return GradeyAuthSession(
            accessToken = accessToken,
            refreshToken = refreshToken.nonEmptyOrNull() ?: previous?.refreshToken,
            tokenType = tokenType ?: "Bearer",
            expiresAtEpochMillis = expiresIn?.let { nowEpochMillis + it * 1000L },
            account = account,
        )
    }
}

@Serializable
private data class SupabaseUserResponse(
    val id: String,
    val email: JsonElement? = null,
    @SerialName("user_metadata")
    val userMetadata: JsonElement? = null,
    @SerialName("created_at")
    val createdAt: JsonElement? = null,
) {
    fun makeAccount(nowEpochMillis: Long): GradeyAccount =
        GradeyAccount(
            id = id,
            email = email.stringContent(),
            fullName = metadataString("full_name") ?: metadataString("name"),
            avatarURL = metadataString("avatar_url"),
            createdAtEpochMillis = createdAtEpochMillis() ?: nowEpochMillis,
        )

    fun mergeInto(account: GradeyAccount, nowEpochMillis: Long): GradeyAccount {
        require(id.isNotBlank() && id == account.id) {
            "Gradey ID returned an invalid account."
        }
        val responseAccount = makeAccount(nowEpochMillis)
        return account.copy(
            email = responseAccount.email ?: account.email,
            fullName = responseAccount.fullName ?: account.fullName,
            avatarURL = responseAccount.avatarURL ?: account.avatarURL,
            createdAtEpochMillis = createdAtEpochMillis() ?: account.createdAtEpochMillis,
        )
    }

    private fun metadataString(key: String): String? =
        (userMetadata as? JsonObject)?.get(key).stringContent()

    fun createdAtEpochMillis(): Long? = createdAt.stringContent()
        ?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
}

private fun String?.nonEmptyOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)

private fun JsonElement?.stringContent(): String? =
    (this as? JsonPrimitive)
        ?.takeIf(JsonPrimitive::isString)
        ?.contentOrNull
        .nonEmptyOrNull()

@Serializable
private data class RegisterDeviceRequest(
    val token: String,
    val platform: String,
    val environment: String,
)
