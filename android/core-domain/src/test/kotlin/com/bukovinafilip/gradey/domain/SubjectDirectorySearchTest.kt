package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SubjectDirectorySearchTest {
    private val subjects = listOf(
        subject("cz", "Čj", "Český jazyk"),
        subject("math", "M", "Matematika"),
        subject("eng", "Aj", "Anglický jazyk"),
    )

    @Test
    fun `blank query preserves repository order`() {
        assertThat(SubjectDirectorySearch.results("   ", subjects)).containsExactlyElementsIn(subjects).inOrder()
    }

    @Test
    fun `search is case and diacritic insensitive across subject names`() {
        val results = SubjectDirectorySearch.results("CESKY", subjects)

        assertThat(results.map(Subject::id)).containsExactly("cz")
    }

    @Test
    fun `search matches abbreviations and requires every token`() {
        assertThat(SubjectDirectorySearch.results("aj", subjects).map(Subject::id)).containsExactly("eng")
        assertThat(SubjectDirectorySearch.results("math", subjects).map(Subject::id)).containsExactly("math")
        assertThat(SubjectDirectorySearch.results("jazyk ang", subjects).map(Subject::id)).containsExactly("eng")
        assertThat(SubjectDirectorySearch.results("jazyk matematika", subjects)).isEmpty()
    }

    @Test
    fun `unknown query returns a real empty result`() {
        assertThat(SubjectDirectorySearch.results("chemie", subjects)).isEmpty()
    }

    private fun subject(id: String, abbrev: String, name: String) = Subject(
        subjectInfo = SubjectInfo(id = id, abbrev = abbrev, name = name),
    )
}
