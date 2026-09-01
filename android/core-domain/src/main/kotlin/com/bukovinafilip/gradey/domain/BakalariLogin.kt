package com.bukovinafilip.gradey.domain

import java.net.URI

data class SchoolLoginValidation(
    val schoolURLError: SchoolLoginValidationError? = null,
    val usernameError: SchoolLoginValidationError? = null,
    val passwordError: SchoolLoginValidationError? = null,
) {
    val isValid: Boolean
        get() = schoolURLError == null && usernameError == null && passwordError == null
}

enum class SchoolLoginValidationError { REQUIRED, INVALID }

object SchoolLoginValidator {
    fun validate(schoolURL: String, username: String, password: String): SchoolLoginValidation {
        val schoolURLError = when {
            schoolURL.isBlank() -> SchoolLoginValidationError.REQUIRED
            runCatching { SchoolURLNormalizer.normalizedBaseURL(schoolURL) }.isFailure ->
                SchoolLoginValidationError.INVALID
            else -> null
        }

        return SchoolLoginValidation(
            schoolURLError = schoolURLError,
            usernameError = SchoolLoginValidationError.REQUIRED.takeIf { username.isBlank() },
            passwordError = SchoolLoginValidationError.REQUIRED.takeIf { password.isEmpty() },
        )
    }
}

object BakalariDemoAccount {
    const val schoolURL = "demo.gradely.app"
    const val username = "apple-review"
    const val password = "GradelyDemo2026!"
    const val accessToken = "demo-access"
    const val refreshToken = "demo-refresh"

    fun isDemoBaseURL(baseURL: String): Boolean {
        val normalized = runCatching { SchoolURLNormalizer.normalizedBaseURL(baseURL) }.getOrNull()
            ?: return false
        val host = runCatching { URI(normalized).host?.lowercase() }.getOrNull() ?: return false
        return host == schoolURL
    }

    fun matches(baseURL: String, username: String, password: String): Boolean =
        isDemoBaseURL(baseURL) &&
            username.trim().equals(this.username, ignoreCase = true) &&
            password == this.password

    fun isDemoToken(token: String): Boolean = token == accessToken || token == refreshToken
}

class InvalidDemoAccountCredentialsException : IllegalArgumentException(
    "Use demo.gradely.app, apple-review, and GradelyDemo2026! for the demo account.",
)
