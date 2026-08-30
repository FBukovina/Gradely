package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Subject
import java.text.Normalizer
import java.util.Locale

object SubjectDirectorySearch {
    fun results(query: String, subjects: List<Subject>): List<Subject> {
        val tokens = normalized(query).split(' ').filter(String::isNotBlank)
        if (tokens.isEmpty()) return subjects

        return subjects.filter { subject ->
            val searchable = normalized(
                listOf(subject.displayName, subject.subjectInfo.abbrev, subject.id).joinToString(" "),
            )
            tokens.all(searchable::contains)
        }
    }

    private fun normalized(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()
}
