package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import java.net.URI
import java.text.Normalizer
import java.util.Locale

object SchoolDirectoryNameResolver {
    fun resolve(
        baseURL: String,
        schools: List<SchoolDirectorySchool>,
    ): String? {
        val normalizedBaseURL = normalizedURL(baseURL) ?: return null

        val exactMatch = schools.firstOrNull { school ->
            normalizedURL(school.trimmedSchoolURL) == normalizedBaseURL
        }
        if (exactMatch != null) return displayableName(exactMatch.trimmedName)

        val baseHost = host(normalizedBaseURL) ?: return null
        val hostMatchNames = schools.mapNotNull { school ->
            val schoolURL = normalizedURL(school.trimmedSchoolURL) ?: return@mapNotNull null
            if (host(schoolURL) != baseHost) return@mapNotNull null
            displayableName(school.trimmedName)
        }.distinct()

        return hostMatchNames.singleOrNull()
    }

    fun displayableName(rawValue: String?): String? {
        val trimmed = rawValue
            ?.replace(UNICODE_WHITESPACE_EDGES, "")
            ?.takeIf(String::isNotEmpty)
            ?: return null
        val normalized = Normalizer.normalize(trimmed, Normalizer.Form.NFD)
            .replace(COMBINING_MARKS, "")
            .lowercase(CZECH_LOCALE)
            .replace(UNICODE_WHITESPACE, " ")
        return trimmed.takeUnless { normalized in PLACEHOLDER_NAMES }
    }

    private fun normalizedURL(rawValue: String): String? = runCatching {
        SchoolURLNormalizer.normalizedBaseURL(rawValue).lowercase(Locale.ROOT)
    }.getOrNull()

    private fun host(normalizedURL: String): String? = runCatching {
        URI(normalizedURL).host?.lowercase(Locale.ROOT)
    }.getOrNull()

    private val CZECH_LOCALE = Locale.forLanguageTag("cs-CZ")
    private val COMBINING_MARKS = Regex("\\p{M}+")
    private val UNICODE_WHITESPACE = Regex("(?U)\\s+")
    private val UNICODE_WHITESPACE_EDGES = Regex("(?U)^\\s+|\\s+$")
    private val PLACEHOLDER_NAMES = setOf("nazev skoly")
}
