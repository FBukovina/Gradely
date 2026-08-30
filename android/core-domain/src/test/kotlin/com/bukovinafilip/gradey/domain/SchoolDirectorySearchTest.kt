package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolDirectorySearchTest {
    private val schools = listOf(
        SchoolDirectorySchool(
            id = "omska",
            name = "Gymnázium Praha 10, Omská",
            town = "Praha",
            schoolURL = "https://bakalari.omska.cz",
        ),
        SchoolDirectorySchool(
            id = "eden",
            name = "Základní škola Eden",
            town = "Praha",
            schoolURL = "https://zseden.bakalari.cz",
        ),
        SchoolDirectorySchool(
            id = "brno",
            name = "Střední škola Brno",
            town = "Brno",
            schoolURL = "https://gymnazium.example.cz",
        ),
    )

    @Test
    fun `search ignores case and diacritics and ranks names before urls`() {
        assertThat(SchoolDirectorySearch.results("gymnazium", schools).first().id).isEqualTo("omska")
    }

    @Test
    fun `search requires every query token`() {
        assertThat(SchoolDirectorySearch.results("praha eden", schools).map { it.id })
            .containsExactly("eden")
    }

    @Test
    fun `search matches Czech school acronyms`() {
        val acronymSchool = SchoolDirectorySchool(
            id = "sssvt",
            name = "Soukromá střední škola výpočetní techniky Praha",
            town = "Praha 9",
            schoolURL = "https://school.example.cz",
        )

        assertThat(SchoolDirectorySearch.results("SSŠVT", schools + acronymSchool).map { it.id })
            .containsExactly("sssvt")
    }

    @Test
    fun `blank query returns no results`() {
        assertThat(SchoolDirectorySearch.results("  ", schools)).isEmpty()
    }
}
