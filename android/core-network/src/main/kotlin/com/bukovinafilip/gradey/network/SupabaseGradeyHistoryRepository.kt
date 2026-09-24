package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.Request

class SupabaseGradeyHistoryRepository(
    private val configuration: SupabaseConfiguration,
    private val authRepository: GradeyAuthRepository,
    private val okHttpClient: OkHttpClient = OkHttpClient(),
) : GradeyHistoryRepository {
    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        check(configuration.isConfigured) { "Gradey ID is not configured in this build." }
        val session = authRepository.validSession()
        val body = GradeyJson.encodeToString(
            GradeHistoryRequest(
                linkedAccountID = accountID?.trim()?.takeIf(String::isNotEmpty),
                days = days,
            ),
        )
        val request = Request.Builder()
            .url(configuration.url.appendPath("functions/v1/grade-history"))
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("apikey", configuration.anonKey)
            .header("Authorization", session.authorizationHeader)
            .post(jsonBody(body))
            .build()
        return try {
            GradeyJson.decodeFromString(okHttpClient.executeString(request))
        } catch (error: CancellationException) {
            throw error
        } catch (error: GradeyApiException) {
            throw GradeyFunctionException(
                function = "grade-history",
                statusCode = error.statusCode,
                code = null,
                message = "Gradey could not load grade history. Please try again.",
            )
        }
    }
}

@Serializable
private data class GradeHistoryRequest(
    @SerialName("linked_account_id")
    val linkedAccountID: String?,
    val days: Int?,
)
