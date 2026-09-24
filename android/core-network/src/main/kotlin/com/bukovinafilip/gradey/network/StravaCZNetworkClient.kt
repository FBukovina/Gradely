package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.StravaCZClient
import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class StravaCZNetworkClient(
    private val okHttpClient: OkHttpClient = defaultClient(),
    private val baseURL: String = "https://app.strava.cz",
) : StravaCZClient {
    override suspend fun login(
        canteenNumber: String,
        username: String,
        password: String,
    ): StravaCZStoredSession {
        runCatching { okHttpClient.executeString(baseRequest("en/prihlasit-se?jidelna").get().build()) }
        val body = post(
            endpoint = "login",
            payload = buildJsonObject {
                put("cislo", canteenNumber)
                put("jmeno", username)
                put("heslo", password)
                put("zustatPrihlasen", true)
                put("environment", "W")
                put("lang", "EN")
            },
        )
        return StravaCZResponseMapper.login(body)
    }

    override suspend fun fetchMenu(session: StravaCZStoredSession): StravaCZMenu =
        StravaCZResponseMapper.menu(
            post(
                endpoint = "objednavky",
                payload = buildJsonObject {
                    put("cislo", session.canteenNumber)
                    put("sid", session.sessionID)
                    put("s5url", session.serviceURL)
                    put("lang", "EN")
                    put("konto", session.balance)
                    put("podminka", "")
                    put("ignoreCert", false)
                },
            ),
        )

    override suspend fun changeMealOrder(
        session: StravaCZStoredSession,
        mealID: Int,
        ordered: Boolean,
    ): Double? = StravaCZResponseMapper.balance(
        post(
            endpoint = "pridejJidloS5",
            payload = sessionPayload(session) {
                put("veta", mealID.toString())
                put("pocet", if (ordered) "1" else "0")
            },
        ),
    )

    override suspend fun saveOrders(session: StravaCZStoredSession): Double? =
        StravaCZResponseMapper.balance(
            post(
                endpoint = "saveOrders",
                payload = sessionPayload(session) { put("xml", JsonNull) },
            ),
        )

    override suspend fun cancelOrderChanges(session: StravaCZStoredSession): Double? =
        StravaCZResponseMapper.balance(
            post(
                endpoint = "nactiVlastnostiPA",
                payload = sessionPayload(session) {
                    put("getText", true)
                    put("checkVersion", true)
                    put("resetTables", true)
                    put("frontendFunction", "refreshInformations")
                },
            ),
        )

    override suspend fun logout(session: StravaCZStoredSession) {
        post(
            endpoint = "logOut",
            payload = sessionPayload(session),
            allowEmpty = true,
        )
    }

    private fun sessionPayload(
        session: StravaCZStoredSession,
        extra: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {},
    ): JsonObject = buildJsonObject {
        put("sid", session.sessionID)
        put("cislo", session.canteenNumber)
        put("url", session.serviceURL)
        put("lang", "EN")
        put("ignoreCert", "false")
        extra()
    }

    private suspend fun post(
        endpoint: String,
        payload: JsonObject,
        allowEmpty: Boolean = false,
    ): String {
        val request = baseRequest("api/$endpoint")
            .post(
                GradeyJson.encodeToString(JsonObject.serializer(), payload)
                    .toRequestBody("text/plain;charset=UTF-8".toMediaType()),
            )
            .build()
        val body = try {
            okHttpClient.executeString(request)
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeyApiException) {
            throw apiError(error.statusCode, error.responseBody)
        } catch (error: IOException) {
            throw StravaCZException(
                StravaCZErrorKind.TRANSPORT,
                "Strava.cz could not be reached. Check your connection and try again.",
                cause = error,
            )
        }
        if (!allowEmpty && body.isBlank()) {
            throw StravaCZException(
                StravaCZErrorKind.INVALID_RESPONSE,
                "Strava.cz returned an empty response.",
            )
        }
        return body.ifBlank { "{}" }
    }

    private fun baseRequest(path: String): Request.Builder = Request.Builder()
        .url(baseURL.appendPath(path))
        .header("Accept", "*/*")
        .header("Accept-Language", "en-US,en;q=0.9,cs;q=0.8")
        .header("Origin", baseURL)
        .header("Referer", "$baseURL/en/prihlasit-se?jidelna")
        .header("User-Agent", UserAgent)

    private fun apiError(statusCode: Int, responseBody: String?): StravaCZException {
        val objectValue = responseBody
            ?.let { runCatching { GradeyJson.parseToJsonElement(it).jsonObject }.getOrNull() }
        val number = (objectValue?.get("number") as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toIntOrNull() }
        val message = (objectValue?.get("message") as? JsonPrimitive)
            ?.contentOrNull
            ?.trim()
            ?.takeIf { it.isNotEmpty() && '<' !in it && '>' !in it }
            ?.take(240)
            ?: responseBody
                ?.trim()
                ?.takeIf { it.isNotEmpty() && '<' !in it && '>' !in it }
                ?.take(240)
        return when {
            number == 35 -> StravaCZException(
                StravaCZErrorKind.INSUFFICIENT_BALANCE,
                message ?: "Your Strava.cz balance is too low for this order.",
                statusCode,
            )
            statusCode == 401 || statusCode == 403 -> StravaCZException(
                StravaCZErrorKind.AUTHENTICATION,
                message ?: "Your Strava.cz session is no longer valid. Please reconnect.",
                statusCode,
            )
            else -> StravaCZException(
                StravaCZErrorKind.HTTP,
                message ?: "The Strava.cz request failed (HTTP $statusCode).",
                statusCode,
            )
        }
    }

    private companion object {
        const val UserAgent =
            "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Mobile Safari/537.36"

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .cookieJar(MemoryCookieJar())
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .callTimeout(45, TimeUnit.SECONDS)
            .build()
    }
}

private class MemoryCookieJar : CookieJar {
    private val cookies = ConcurrentHashMap<String, List<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        this.cookies[url.host] = cookies
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> =
        cookies[url.host].orEmpty().filter { it.matches(url) }
}
