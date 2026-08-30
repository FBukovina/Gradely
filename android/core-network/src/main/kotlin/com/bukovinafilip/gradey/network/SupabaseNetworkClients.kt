package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.NotificationPreferences
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.Request

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
) : GradeyAuthRepository {
    override suspend fun bootstrapSession(): GradeyAuthSession? = sessionLoader()

    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?): GradeyAuthSession {
        require(idToken.isNotBlank()) { "Missing Google identity token." }
        ensureConfigured()
        val response: SupabaseTokenResponse = send(
            path = "auth/v1/token?grant_type=id_token",
            body = GradeyJson.encodeToString(SignInWithIDTokenRequest("google", idToken, accessToken)),
        )
        val session = response.makeSession(fullName)
        sessionStore(session)
        return session
    }

    override suspend fun signOut() {
        val session = sessionLoader()
        if (session != null && configuration.isConfigured) {
            runCatching {
                val request = Request.Builder()
                    .url(configuration.url.appendPath("auth/v1/logout"))
                    .post(jsonBody("{}"))
                    .header("apikey", configuration.anonKey)
                    .header("Authorization", session.authorizationHeader)
                    .build()
                okHttpClient.executeString(request)
            }
        }
        sessionStore(null)
    }

    private suspend inline fun <reified T> send(path: String, body: String): T {
        val request = Request.Builder()
            .url(configuration.url.appendPath(path))
            .post(jsonBody(body))
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", "Bearer ${configuration.anonKey}")
            .build()
        return GradeyJson.decodeFromString(okHttpClient.executeString(request))
    }

    private fun ensureConfigured() {
        if (!configuration.isConfigured) throw IllegalStateException("Supabase is not configured.")
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

    private suspend inline fun <reified T> send(function: String, session: GradeyAuthSession, body: T) {
        if (!configuration.isConfigured) throw IllegalStateException("Supabase is not configured.")
        val request = Request.Builder()
            .url(configuration.url.appendPath("functions/v1/$function"))
            .post(jsonBody(GradeyJson.encodeToString(body)))
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", session.authorizationHeader)
            .build()
        okHttpClient.executeString(request)
    }
}

@Serializable
private data class SignInWithIDTokenRequest(
    val provider: String,
    @SerialName("id_token")
    val idToken: String,
    @SerialName("access_token")
    val accessToken: String? = null,
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
    fun makeSession(fullName: String?): GradeyAuthSession =
        GradeyAuthSession(
            accessToken = accessToken,
            refreshToken = refreshToken,
            tokenType = tokenType ?: "Bearer",
            expiresAtEpochMillis = expiresIn?.let { System.currentTimeMillis() + it * 1000L },
            account = user.makeAccount(fullName),
        )
}

@Serializable
private data class SupabaseUserResponse(
    val id: String,
    val email: String? = null,
    @SerialName("user_metadata")
    val userMetadata: Map<String, String> = emptyMap(),
    @SerialName("created_at")
    val createdAt: String? = null,
) {
    fun makeAccount(fullName: String?): GradeyAccount =
        GradeyAccount(
            id = id,
            email = email,
            fullName = fullName?.takeIf { it.isNotBlank() } ?: userMetadata["full_name"] ?: userMetadata["name"],
            avatarURL = userMetadata["avatar_url"],
        )
}

@Serializable
private data class RegisterDeviceRequest(
    val token: String,
    val platform: String,
    val environment: String,
)

