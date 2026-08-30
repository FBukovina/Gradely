package com.bukovinafilip.gradey.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

val GradeyJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    isLenient = true
}

class GradeyApiException(
    val statusCode: Int,
    message: String,
) : RuntimeException(message)

suspend fun OkHttpClient.executeString(request: Request): String = withContext(Dispatchers.IO) {
    newCall(request).execute().use { response ->
        val body = response.body?.string().orEmpty()
        if (!response.isSuccessful) throw GradeyApiException(response.code, body.ifBlank { "HTTP ${response.code}" })
        body
    }
}

fun formBody(fields: Map<String, String>): FormBody =
    FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()

fun jsonBody(json: String) = json.toRequestBody("application/json; charset=utf-8".toMediaType())

fun String.appendPath(path: String): String =
    trimEnd('/') + "/" + path.trimStart('/')

