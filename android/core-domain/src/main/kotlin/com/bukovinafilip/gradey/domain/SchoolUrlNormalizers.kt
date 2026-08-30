package com.bukovinafilip.gradey.domain

import java.net.URI

class InvalidSchoolUrl(message: String) : IllegalArgumentException(message)

object SchoolURLNormalizer {
    fun normalizedBaseURL(rawValue: String): String {
        var value = rawValue.trim()
        if (value.isBlank()) throw InvalidSchoolUrl("School URL is required.")
        if (!value.contains("://")) value = "https://$value"

        val uri = runCatching { URI(value) }.getOrElse { throw InvalidSchoolUrl("Invalid school URL.") }
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase() ?: throw InvalidSchoolUrl("Invalid school URL.")
        if (scheme != "https") throw InvalidSchoolUrl("School URL must use HTTPS.")

        val cleanPath = uri.path
            ?.trim('/')
            ?.takeUnless { it.equals("login", ignoreCase = true) || it.equals("next/login", ignoreCase = true) }
            ?.takeIf { it.isNotBlank() }

        return buildString {
            append("https://")
            append(host)
            if (uri.port > 0) append(":").append(uri.port)
            if (cleanPath != null) append("/").append(cleanPath)
        }
    }

    fun displayString(baseURL: String): String =
        normalizedBaseURL(baseURL).removeSuffix("/")
}

object EduPageURLNormalizer {
    fun normalizedBaseURL(rawValue: String): String {
        var value = rawValue.trim()
        if (value.isBlank()) throw InvalidSchoolUrl("EduPage school is required.")
        if (!value.contains("://")) {
            value = if (value.contains(".")) "https://$value" else "https://$value.edupage.org"
        }

        val uri = runCatching { URI(value) }.getOrElse { throw InvalidSchoolUrl("Invalid EduPage URL.") }
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase() ?: throw InvalidSchoolUrl("Invalid EduPage URL.")
        if (scheme != "https" || (host != "edupage.org" && !host.endsWith(".edupage.org"))) {
            throw InvalidSchoolUrl("EduPage URL must be a secure edupage.org host.")
        }
        return "https://$host"
    }
}

