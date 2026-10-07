package com.bukovinafilip.gradey.network

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Callback
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

val GradeyJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    isLenient = true
}

class GradeyApiException(
    val statusCode: Int,
    val responseBody: String?,
) : RuntimeException("HTTP $statusCode")

suspend fun OkHttpClient.executeString(request: Request): String = suspendCancellableCoroutine { continuation ->
    val call = newCall(request)
    continuation.invokeOnCancellation { call.cancel() }
    call.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (continuation.isActive) continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            try {
                response.use {
                    val body = it.body?.string().orEmpty()
                    if (!continuation.isActive) return
                    if (it.isSuccessful) {
                        continuation.resume(body)
                    } else {
                        continuation.resumeWithException(
                            GradeyApiException(it.code, body.takeIf(String::isNotBlank)),
                        )
                    }
                }
            } catch (error: Throwable) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }
        }
    })
}

fun formBody(fields: Map<String, String>): FormBody =
    FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()

fun jsonBody(json: String) = json.toRequestBody("application/json; charset=utf-8".toMediaType())

fun String.appendPath(path: String): String =
    trimEnd('/') + "/" + path.trimStart('/')
