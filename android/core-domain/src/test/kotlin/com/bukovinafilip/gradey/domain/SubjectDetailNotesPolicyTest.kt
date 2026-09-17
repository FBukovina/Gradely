package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SubjectDetailNotesPolicyTest {
    @Test
    fun `trims and preserves every independent Bakalari note field`() {
        val notes = SubjectDetailNotesPolicy.resolve(
            subject(
                subjectNote = "  Bring a ruler.  ",
                temporaryMark = " 2- ",
                temporaryMarkNote = "  Waiting for confirmation. ",
            ),
        )

        assertThat(notes.subjectNote).isEqualTo("Bring a ruler.")
        assertThat(notes.temporaryMark).isEqualTo("2-")
        assertThat(notes.temporaryMarkNote).isEqualTo("Waiting for confirmation.")
        assertThat(notes.hasContent).isTrue()
        assertThat(notes.hasTemporaryContent).isTrue()
    }

    @Test
    fun `blank optional fields do not create an empty notes card`() {
        val notes = SubjectDetailNotesPolicy.resolve(
            subject(subjectNote = " ", temporaryMark = "\n", temporaryMarkNote = null),
        )

        assertThat(notes.hasContent).isFalse()
        assertThat(notes.hasTemporaryContent).isFalse()
    }

    @Test
    fun `temporary note remains visible without a temporary mark value`() {
        val notes = SubjectDetailNotesPolicy.resolve(
            subject(temporaryMarkNote = "Teacher is reviewing this mark"),
        )

        assertThat(notes.temporaryMark).isNull()
        assertThat(notes.temporaryMarkNote).isEqualTo("Teacher is reviewing this mark")
        assertThat(notes.hasTemporaryContent).isTrue()
    }

    private fun subject(
        subjectNote: String? = null,
        temporaryMark: String? = null,
        temporaryMarkNote: String? = null,
    ) = Subject(
        subjectInfo = SubjectInfo(id = "math", abbrev = "M", name = "Mathematics"),
        subjectNote = subjectNote,
        temporaryMark = temporaryMark,
        temporaryMarkNote = temporaryMarkNote,
    )
}
