package com.bukovinafilip.gradey.domain

import java.net.URI

data class SchoolLoginValidation(
    val schoolURLMessage: String? = null,
    val usernameMessage: String? = null,
    val passwordMessage: String? = null,
) {
    val isValid: Boolean
        get() = schoolURLMessage == null && usernameMessage == null && passwordMessage == null
}

object SchoolLoginValidator {
    fun validate(schoolURL: String, username: String, password: String): SchoolLoginValidation {
        val schoolURLMessage = runCatching { SchoolURLNormalizer.normalizedBaseURL(schoolURL) }
            .exceptionOrNull()
            ?.message
            ?: if (schoolURL.isBlank()) "School URL is required." else null

        return SchoolLoginValidation(
            schoolURLMessage = schoolURLMessage,
            usernameMessage = if (username.isBlank()) "Username is required." else null,
            passwordMessage = if (password.isEmpty()) "Password is required." else null,
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
