package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.model.LoginResponse
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.UserResponse
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.InterruptedIOException
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

enum class BakalariErrorKind {
    INVALID_RESPONSE,
    HTTP,
    AUTHENTICATION,
    DECODING,
    TIMEOUT,
    OFFLINE,
    TRANSPORT,
}

open class BakalariApiException(
    val statusCode: Int?,
    message: String,
    cause: Throwable? = null,
    val kind: BakalariErrorKind = if (statusCode == null) BakalariErrorKind.INVALID_RESPONSE else BakalariErrorKind.HTTP,
) : RuntimeException(message, cause)

class BakalariHttpException(statusCode: Int, message: String) :
    BakalariApiException(statusCode, message, kind = BakalariErrorKind.HTTP)

class BakalariAuthenticationException(statusCode: Int, message: String) :
    BakalariApiException(statusCode, message, kind = BakalariErrorKind.AUTHENTICATION)

class BakalariInvalidResponseException : BakalariApiException(
    statusCode = null,
    message = "The school returned an empty or invalid response.",
    kind = BakalariErrorKind.INVALID_RESPONSE,
)

class BakalariDecodingException(cause: Throwable) : BakalariApiException(
    statusCode = null,
    message = "The school returned data Gradey could not read.",
    cause = cause,
    kind = BakalariErrorKind.DECODING,
)

class BakalariTimeoutException(cause: Throwable) : BakalariApiException(
    statusCode = null,
    message = "The Bakaláři request timed out. Please try again.",
    cause = cause,
    kind = BakalariErrorKind.TIMEOUT,
)

class BakalariOfflineException(cause: Throwable) : BakalariApiException(
    statusCode = null,
    message = "Bakaláři could not be reached. Check your internet connection and try again.",
    cause = cause,
    kind = BakalariErrorKind.OFFLINE,
)

class BakalariTransportException(cause: Throwable) : BakalariApiException(
    statusCode = null,
    message = "The Bakaláři connection failed. Please try again.",
    cause = cause,
    kind = BakalariErrorKind.TRANSPORT,
)

class BakalariNetworkClient(
    private val okHttpClient: OkHttpClient = defaultHttpClient(),
) : BakalariClient {
    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse =
        postForm(
            baseURL = baseURL,
            path = "api/login",
            fields = mapOf(
                "client_id" to "ANDR",
                "grant_type" to "password",
                "username" to username,
                "password" to password,
            ),
        )

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse =
        postForm(
            baseURL = baseURL,
            path = "api/login",
            fields = mapOf(
                "client_id" to "ANDR",
                "grant_type" to "refresh_token",
                "refresh_token" to refreshToken,
            ),
        )

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse =
        get(baseURL, "api/3/marks", accessToken = accessToken)

    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse =
        get(baseURL, "api/3/absence/student", accessToken = accessToken)

    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse =
        get(baseURL, "api/3/user", accessToken = accessToken)

    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse =
        get(baseURL, "api/3/timetable/actual", query = mapOf("date" to date), accessToken = accessToken)

    override suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject =
        postJson(
            baseURL = baseURL,
            path = "api/3/marks/what-if",
            accessToken = accessToken,
            body = GradeyJson.encodeToString(WhatIfMarkRequest.payload(subject, markText, weight)),
        )

    private suspend inline fun <reified T> postForm(
        baseURL: String,
        path: String,
        fields: Map<String, String>,
    ): T {
        val request = Request.Builder()
            .url(baseURL.appendPath(path))
            .post(formBody(fields))
            .header("Accept", "application/json")
            .build()
        return execute(request)
    }

    private suspend inline fun <reified T> get(
        baseURL: String,
        path: String,
        query: Map<String, String> = emptyMap(),
        accessToken: String,
    ): T {
        val url = buildString {
            append(baseURL.appendPath(path))
            if (query.isNotEmpty()) {
                append("?")
                append(
                    query.entries.joinToString("&") { (key, value) ->
                        "${key.urlEncoded()}=${value.urlEncoded()}"
                    },
                )
            }
        }
        val request = Request.Builder()
            .url(url)
            .get()
            .header("Accept", "application/json")
            .header("Authorization", "Bearer $accessToken")
            .build()
        return execute(request)
    }

    private suspend inline fun <reified T> postJson(
        baseURL: String,
        path: String,
        accessToken: String,
        body: String,
    ): T {
        val request = Request.Builder()
            .url(baseURL.appendPath(path))
            .post(jsonBody(body))
            .header("Accept", "application/json")
            .header("Authorization", "Bearer $accessToken")
            .build()
        return execute(request)
    }

    private suspend inline fun <reified T> execute(request: Request): T {
        val body = try {
            okHttpClient.executeString(request)
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeyApiException) {
            val message = readableHTTPError(error.statusCode, error.responseBody)
            if (error.statusCode == 401 || error.statusCode == 403) {
                throw BakalariAuthenticationException(error.statusCode, message)
            }
            // Do not retain the raw response body as an outward exception cause.
            throw BakalariHttpException(error.statusCode, message)
        } catch (error: SocketTimeoutException) {
            throw BakalariTimeoutException(error)
        } catch (error: InterruptedIOException) {
            throw BakalariTimeoutException(error)
        } catch (error: UnknownHostException) {
            throw BakalariOfflineException(error)
        } catch (error: ConnectException) {
            throw BakalariOfflineException(error)
        } catch (error: NoRouteToHostException) {
            throw BakalariOfflineException(error)
        } catch (error: IOException) {
            throw BakalariTransportException(error)
        }

        if (body.isBlank()) throw BakalariInvalidResponseException()

        return try {
            GradeyJson.decodeFromString(body)
        } catch (error: SerializationException) {
            throw BakalariDecodingException(error)
        } catch (error: IllegalArgumentException) {
            throw BakalariDecodingException(error)
        }
    }

    private fun readableHTTPError(statusCode: Int, responseBody: String?): String {
        val jsonMessage = responseBody
            ?.let { runCatching { GradeyJson.parseToJsonElement(it).jsonObject }.getOrNull() }
            ?.let { body ->
                listOf("error_description", "message", "error")
                    .firstNotNullOfOrNull { key ->
                        body[key]
                            ?.let { value -> runCatching { value.jsonPrimitive.content }.getOrNull() }
                            ?.trim()
                            ?.takeIf(String::isNotEmpty)
                    }
            }
        if (jsonMessage != null && jsonMessage.length <= 300 && '<' !in jsonMessage && '>' !in jsonMessage) {
            return jsonMessage
        }
        return when (statusCode) {
            400 -> "Bakaláři rejected the request. Check the entered details and try again."
            401 -> "Your Bakaláři session is no longer valid. Please reconnect your school account."
            403 -> "Bakaláři refused access to this information."
            404 -> "This Bakaláři server does not provide the requested information."
            in 500..599 -> "The Bakaláři server is temporarily unavailable (HTTP $statusCode)."
            else -> "The Bakaláři request failed (HTTP $statusCode)."
        }
    }

    private fun String.urlEncoded(): String = URLEncoder.encode(this, StandardCharsets.UTF_8.name())

    private companion object {
        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .callTimeout(45, TimeUnit.SECONDS)
            .build()
    }
}

@Serializable
private data class WhatIfMarkRequest(
    @kotlinx.serialization.SerialName("Id")
    val id: String?,
    @kotlinx.serialization.SerialName("MarkText")
    val markText: String,
    @kotlinx.serialization.SerialName("Weight")
    val weight: Int?,
    @kotlinx.serialization.SerialName("MaxPoints")
    val maxPoints: Int,
    @kotlinx.serialization.SerialName("SubjectId")
    val subjectID: String,
) {
    companion object {
        fun payload(subject: Subject, predictedMarkText: String, predictedWeight: Int): List<WhatIfMarkRequest> {
            val existing = subject.marks.map { mark ->
                WhatIfMarkRequest(
                    id = mark.id,
                    markText = mark.markText,
                    weight = mark.weight?.let { kotlin.math.round(it).toInt() },
                    maxPoints = mark.maxPoints ?: 0,
                    subjectID = mark.subjectID,
                )
            }
            return existing + WhatIfMarkRequest(
                id = null,
                markText = predictedMarkText,
                weight = kotlin.math.max(1, predictedWeight),
                maxPoints = 0,
                subjectID = subject.id,
            )
        }
    }
}

class DemoAwareBakalariClient(
    private val liveClient: BakalariClient = BakalariNetworkClient(),
    private val demoClient: BakalariClient = DemoBakalariClient(),
) : BakalariClient {
    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse =
        if (DemoAccount.matches(baseURL, username, password)) demoClient.login(baseURL, username, password)
        else liveClient.login(baseURL, username, password)

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(refreshToken)) demoClient.refreshToken(baseURL, refreshToken)
        else liveClient.refreshToken(baseURL, refreshToken)

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken)) demoClient.fetchMarks(baseURL, accessToken)
        else liveClient.fetchMarks(baseURL, accessToken)

    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken)) demoClient.fetchAbsences(baseURL, accessToken)
        else liveClient.fetchAbsences(baseURL, accessToken)

    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken)) demoClient.fetchUser(baseURL, accessToken)
        else liveClient.fetchUser(baseURL, accessToken)

    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken)) demoClient.fetchTimetable(baseURL, accessToken, date)
        else liveClient.fetchTimetable(baseURL, accessToken, date)

    override suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject =
        if (DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken)) demoClient.predictSubject(baseURL, accessToken, subject, markText, weight)
        else liveClient.predictSubject(baseURL, accessToken, subject, markText, weight)
}

object DemoAccount {
    const val schoolURL = "demo.gradey.app"
    const val username = "apple-review"
    const val password = "GradelyDemo2026!"
    const val accessToken = "demo-access"
    const val refreshToken = "demo-refresh"

    fun isDemoBaseURL(baseURL: String): Boolean {
        val host = baseURL.removePrefix("https://").removePrefix("http://").substringBefore("/").lowercase()
        return host == "demo" || host == schoolURL
    }

    fun matches(baseURL: String, username: String, password: String): Boolean =
        isDemoBaseURL(baseURL) && username.trim().equals(this.username, ignoreCase = true) && password == this.password

    fun isDemoToken(token: String): Boolean = token == accessToken || token == refreshToken
}

class DemoBakalariClient : BakalariClient {
    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse =
        LoginResponse(DemoAccount.accessToken, DemoAccount.refreshToken, "Bearer", 86_400, userID = "demo-user")

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse =
        login(baseURL, DemoAccount.username, DemoAccount.password)

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse = com.bukovinafilip.gradey.domain.DemoData.marksResponse
    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse = com.bukovinafilip.gradey.domain.DemoData.absenceResponse
    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse = com.bukovinafilip.gradey.domain.DemoData.user

    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse =
        com.bukovinafilip.gradey.domain.DemoData.timetableResponse(date)

    override suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject {
        val value = GradeMath.parseMarkValue(markText) ?: return subject
        val average = GradeMath.theoreticalAverage(subject.marks, subject.averageText, value, weight)
        return subject.copy(averageText = String.format(java.util.Locale.US, "%.2f", average))
    }
}
