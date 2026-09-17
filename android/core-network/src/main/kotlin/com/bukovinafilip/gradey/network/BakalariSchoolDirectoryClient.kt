package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.SchoolDirectoryClient
import com.bukovinafilip.gradey.model.SchoolDirectoryMunicipality
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import okhttp3.Dispatcher
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class SchoolDirectoryNetworkException(
    val statusCode: Int? = null,
    message: String,
    cause: Throwable? = null,
) : RuntimeException(message, cause)

class BakalariSchoolDirectoryClient(
    private val serviceURL: String = DEFAULT_SERVICE_URL,
    private val okHttpClient: OkHttpClient = defaultHttpClient(),
) : SchoolDirectoryClient {
    override suspend fun fetchMunicipalities(): List<SchoolDirectoryMunicipality> =
        execute(serviceURL)

    override suspend fun fetchSchools(municipalityName: String): List<SchoolDirectorySchool> {
        val url = serviceURL
            .toHttpUrl()
            .newBuilder()
            .setQueryParameter("name", municipalityName)
            .build()
            .toString()
        val response: TownSchoolsResponse = execute(url)
        val town = response.name.trim()
        return response.schools.mapNotNull { school ->
            val name = school.name.trim()
            val schoolURL = school.schoolURL.trim()
            if (name.isEmpty() || schoolURL.isEmpty()) return@mapNotNull null
            SchoolDirectorySchool(
                id = school.id,
                name = name,
                town = town,
                schoolURL = schoolURL,
            )
        }
    }

    private suspend inline fun <reified T> execute(url: String): T {
        val request = Request.Builder()
            .url(url)
            .get()
            .header("Accept", "application/json")
            .build()
        val body = try {
            okHttpClient.executeString(request)
        } catch (error: GradeyApiException) {
            throw SchoolDirectoryNetworkException(
                statusCode = error.statusCode,
                message = "School directory request failed (HTTP ${error.statusCode}).",
                cause = error,
            )
        }
        return try {
            GradeyJson.decodeFromString(body)
        } catch (error: SerializationException) {
            throw SchoolDirectoryNetworkException(
                message = "The school directory returned data Gradey could not read.",
                cause = error,
            )
        } catch (error: IllegalArgumentException) {
            throw SchoolDirectoryNetworkException(
                message = "The school directory returned data Gradey could not read.",
                cause = error,
            )
        }
    }

    @Serializable
    private data class TownSchoolsResponse(
        val name: String,
        val schools: List<TownSchool> = emptyList(),
    )

    @Serializable
    private data class TownSchool(
        val id: String,
        val name: String,
        @SerialName("schoolUrl")
        val schoolURL: String,
    )

    private companion object {
        const val DEFAULT_SERVICE_URL = "https://sluzby.bakalari.cz/api/v1/municipality"

        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .dispatcher(
                Dispatcher().apply {
                    maxRequests = 8
                    maxRequestsPerHost = 8
                },
            )
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .callTimeout(12, TimeUnit.SECONDS)
            .build()
    }
}
