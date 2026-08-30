package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class BakalariLoginTest {
    @Test
    fun `validates each credential without changing the password`() {
        val missing = SchoolLoginValidator.validate("", "  ", "")

        assertThat(missing.isValid).isFalse()
        assertThat(missing.schoolURLMessage).isEqualTo("School URL is required.")
        assertThat(missing.usernameMessage).isEqualTo("Username is required.")
        assertThat(missing.passwordMessage).isEqualTo("Password is required.")

        val valid = SchoolLoginValidator.validate("school.example.cz", " student ", " password ")

        assertThat(valid).isEqualTo(SchoolLoginValidation())
        assertThat(valid.isValid).isTrue()
    }

    @Test
    fun `surfaces the URL normalizer validation message`() {
        val validation = SchoolLoginValidator.validate(
            schoolURL = "http://school.example.cz",
            username = "student",
            password = "secret",
        )

        assertThat(validation.schoolURLMessage).isEqualTo("School URL must use HTTPS.")
        assertThat(validation.isValid).isFalse()
    }

    @Test
    fun `demo account requires the exact host username and password`() {
        assertThat(
            BakalariDemoAccount.matches(
                "https://demo.gradely.app/",
                " APPLE-REVIEW ",
                "GradelyDemo2026!",
            ),
        ).isTrue()
        assertThat(BakalariDemoAccount.matches("demo.gradely.app", "apple-review", "wrong"))
            .isFalse()
        assertThat(BakalariDemoAccount.matches("demo.gradely.app.evil", "apple-review", "GradelyDemo2026!"))
            .isFalse()
        assertThat(BakalariDemoAccount.matches("school.example.cz", "apple-review", "GradelyDemo2026!"))
            .isFalse()
    }

    @Test
    fun `demo tokens remain identifiable for the saved demo session`() {
        assertThat(BakalariDemoAccount.isDemoToken("demo-access")).isTrue()
        assertThat(BakalariDemoAccount.isDemoToken("demo-refresh")).isTrue()
        assertThat(BakalariDemoAccount.isDemoToken("real-token")).isFalse()
    }
}
