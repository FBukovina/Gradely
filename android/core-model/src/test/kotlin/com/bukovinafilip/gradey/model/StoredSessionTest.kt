package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class StoredSessionTest {
    @Test
    fun `local sessions on the same server are scoped by username`() {
        val first = session(username = "student.one")
        val second = session(username = "student.two")

        assertThat(first.cacheScope).isNotEqualTo(second.cacheScope)
        assertThat(first.cacheScope).startsWith("bakalari-school.example-")
        assertThat(first.cacheScope).doesNotContain("student.one")
    }

    @Test
    fun `username cache scope is stable across harmless formatting differences`() {
        val first = session(username = " Student.One ")
        val second = session(username = "student.one")

        assertThat(first.cacheScope).isEqualTo(second.cacheScope)
    }

    @Test
    fun `linked account identifier takes precedence over local identity`() {
        val session = session(username = "student.one").copy(linkedAccountID = "account-123")

        assertThat(session.cacheScope).isEqualTo("linked-account-123")
    }

    private fun session(username: String) = StoredSession(
        accessToken = "access",
        refreshToken = "refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = "https://SCHOOL.EXAMPLE/path",
        bakalari = BakalariCredentials(username = username, password = "secret"),
    )
}
