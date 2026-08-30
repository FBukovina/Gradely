package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import java.text.Collator
import java.text.Normalizer
import java.util.Locale

object SchoolDirectorySearch {
    fun results(
        query: String,
        schools: List<SchoolDirectorySchool>,
        limit: Int = 8,
    ): List<SchoolDirectorySchool> {
        val normalizedQuery = normalize(query.trim())
        if (normalizedQuery.isEmpty() || limit <= 0) return emptyList()
        val tokens = normalizedQuery.split(Regex("\\s+")).filter(String::isNotEmpty)
        val collator = Collator.getInstance(CZECH_LOCALE)

        return schools
            .mapNotNull { school -> score(school, normalizedQuery, tokens)?.let { school to it } }
            .sortedWith { left, right ->
                when {
                    left.second != right.second -> left.second.compareTo(right.second)
                    collator.compare(left.first.trimmedTown, right.first.trimmedTown) != 0 ->
                        collator.compare(left.first.trimmedTown, right.first.trimmedTown)
                    else -> collator.compare(left.first.trimmedName, right.first.trimmedName)
                }
            }
            .take(limit)
            .map { it.first }
    }

    fun normalize(value: String): String = Normalizer
        .normalize(value.lowercase(CZECH_LOCALE), Normalizer.Form.NFD)
        .replace(COMBINING_MARKS, "")

    private fun acronym(value: String): String = normalize(value)
        .split(NON_ALPHANUMERIC)
        .filter(String::isNotEmpty)
        .mapNotNull(String::firstOrNull)
        .joinToString(separator = "")

    private fun score(
        school: SchoolDirectorySchool,
        query: String,
        tokens: List<String>,
    ): Int? {
        val name = normalize(school.name)
        val town = normalize(school.town)
        val url = normalize(school.schoolURL)
        val nameAcronym = acronym(name)
        val searchable = "$name $town $url $nameAcronym"
        if (!tokens.all(searchable::contains)) return null

        return when {
            name == query -> 0
            nameAcronym == query || nameAcronym.startsWith(query) -> 5
            name.startsWith(query) -> 10
            town.startsWith(query) -> 20
            name.contains(query) -> 30
            town.contains(query) -> 40
            url.contains(query) -> 50
            else -> 60
        }
    }

    private val CZECH_LOCALE = Locale.forLanguageTag("cs-CZ")
    private val COMBINING_MARKS = Regex("\\p{M}+")
    private val NON_ALPHANUMERIC = Regex("[^\\p{L}\\p{N}]+")
}
