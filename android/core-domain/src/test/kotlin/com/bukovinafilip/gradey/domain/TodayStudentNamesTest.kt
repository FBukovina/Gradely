package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class TodayStudentNamesTest {
    @Test
    fun `school profile name wins`() {
        assertThat(TodayStudentNames.resolve("  Student Name  ", "Linked Name"))
            .isEqualTo("Student Name")
    }

    @Test
    fun `linked account name is the fallback`() {
        assertThat(TodayStudentNames.resolve("  ", "  Linked Name  "))
            .isEqualTo("Linked Name")
    }

    @Test
    fun `missing identities allow the UI to use Gradey`() {
        assertThat(TodayStudentNames.resolve(null, ""))
            .isNull()
    }
}
