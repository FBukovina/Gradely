package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Subject

data class SubjectDetailNotes(
    val subjectNote: String?,
    val temporaryMark: String?,
    val temporaryMarkNote: String?,
) {
    val hasContent: Boolean
        get() = subjectNote != null || temporaryMark != null || temporaryMarkNote != null

    val hasTemporaryContent: Boolean
        get() = temporaryMark != null || temporaryMarkNote != null
}

object SubjectDetailNotesPolicy {
    fun resolve(subject: Subject): SubjectDetailNotes = SubjectDetailNotes(
        subjectNote = subject.subjectNote.trimmedOrNull(),
        temporaryMark = subject.temporaryMark.trimmedOrNull(),
        temporaryMarkNote = subject.temporaryMarkNote.trimmedOrNull(),
    )

    private fun String?.trimmedOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)
}
