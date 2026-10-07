package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolDirectoryNameResolverTest {
    @Test
    fun `exact normalized URL wins over another school on the same host`() {
        val schools = listOf(
            school("other", "Other School", "https://school.example.cz/other"),
            school("exact", "Exact School", "HTTPS://SCHOOL.EXAMPLE.CZ/bakalari/"),
        )

        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/bakalari",
            schools = schools,
        )

        assertThat(resolved).isEqualTo("Exact School")
    }

    @Test
    fun `next login path query trailing slash and case normalize for exact matching`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = " SCHOOL.EXAMPLE.CZ/next/login?source=browser#form ",
            schools = listOf(
                school("exact", "Exact School", "https://school.example.cz/"),
                school("other", "Other School", "https://school.example.cz/other"),
            ),
        )

        assertThat(resolved).isEqualTo("Exact School")
    }

    @Test
    fun `invalid exact name fails closed instead of using another same-host school`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/bakalari",
            schools = listOf(
                school("exact", "Název školy", "https://school.example.cz/bakalari"),
                school("other", "Other School", "https://school.example.cz/other"),
            ),
        )

        assertThat(resolved).isNull()
    }

    @Test
    fun `first duplicate exact URL remains authoritative`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/bakalari",
            schools = listOf(
                school("first", "First School", "https://school.example.cz/bakalari/"),
                school("second", "Second School", "HTTPS://SCHOOL.EXAMPLE.CZ/bakalari"),
            ),
        )

        assertThat(resolved).isEqualTo("First School")
    }

    @Test
    fun `unique same-host name is used when no exact URL exists`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/student",
            schools = listOf(school("directory", "Directory School", "https://school.example.cz/bakalari")),
        )

        assertThat(resolved).isEqualTo("Directory School")
    }

    @Test
    fun `multiple names on the same host are ambiguous`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/student",
            schools = listOf(
                school("first", "First School", "https://school.example.cz/first"),
                school("second", "Second School", "https://school.example.cz/second"),
            ),
        )

        assertThat(resolved).isNull()
    }

    @Test
    fun `case-only name differences remain ambiguous`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/student",
            schools = listOf(
                school("first", "Shared School", "https://school.example.cz/first"),
                school("second", "shared school", "https://school.example.cz/second"),
            ),
        )

        assertThat(resolved).isNull()
    }

    @Test
    fun `duplicate same-host names remain unambiguous`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/student",
            schools = listOf(
                school("first", "Shared School", "https://school.example.cz/first"),
                school("second", "Shared School", "https://school.example.cz/second"),
            ),
        )

        assertThat(resolved).isEqualTo("Shared School")
    }

    @Test
    fun `blank placeholder invalid and unrelated entries are ignored`() {
        val resolved = SchoolDirectoryNameResolver.resolve(
            baseURL = "https://school.example.cz/student",
            schools = listOf(
                school("blank", "   ", "https://school.example.cz/blank"),
                school("placeholder", "Název   školy", "https://school.example.cz/placeholder"),
                school("invalid", "Invalid URL School", "not a url"),
                school("other", "Other Host School", "https://other.example.cz"),
            ),
        )

        assertThat(resolved).isNull()
    }

    @Test
    fun `same-host fallback ignores path and port but invalid base fails closed`() {
        val schools = listOf(
            school("school", "Port School", "https://school.example.cz:8443/bakalari"),
        )

        assertThat(
            SchoolDirectoryNameResolver.resolve(
                baseURL = "https://school.example.cz:9443/student",
                schools = schools,
            ),
        ).isEqualTo("Port School")
        assertThat(SchoolDirectoryNameResolver.resolve("http://school.example.cz", schools)).isNull()
    }

    @Test
    fun `displayable name trims values and rejects blank and placeholder variants`() {
        assertThat(SchoolDirectoryNameResolver.displayableName("  Real   School  ")).isEqualTo("Real   School")
        assertThat(SchoolDirectoryNameResolver.displayableName("\u0085Real\t\u00A0School\u0085"))
            .isEqualTo("Real\t\u00A0School")
        assertThat(SchoolDirectoryNameResolver.displayableName("  ")).isNull()
        assertThat(SchoolDirectoryNameResolver.displayableName("NÁZEV   ŠKOLY")).isNull()
        assertThat(SchoolDirectoryNameResolver.displayableName("Název\u00A0školy")).isNull()
        assertThat(SchoolDirectoryNameResolver.displayableName("\u0085Název\u0085školy\u0085")).isNull()
    }

    private fun school(
        id: String,
        name: String,
        schoolURL: String,
    ) = SchoolDirectorySchool(
        id = id,
        name = name,
        town = "Town",
        schoolURL = schoolURL,
    )
}
