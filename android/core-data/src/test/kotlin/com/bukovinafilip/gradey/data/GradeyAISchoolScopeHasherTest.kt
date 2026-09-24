package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.StoredSession
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyAISchoolScopeHasherTest {
    private val hasher = GradeyAISchoolScopeHasher(ByteArray(32) { 7 })

    @Test
    fun `same school identity and salt produce a stable opaque scope`() {
        val session = session("https://SCHOOL.example.cz/path", " Parent ", "linked-account")

        val scope = hasher.schoolScope(session)

        assertThat(scope).isEqualTo("school_fb32967160cb5b5e0a3e78d263e11d341efb41b0e4313df8356b08b6868be185")
        assertThat(scope).doesNotContain("school.example.cz")
        assertThat(scope).doesNotContain("parent")
        assertThat(scope).doesNotContain("linked-account")
    }

    @Test
    fun `account school user and device salt changes cannot reuse another context`() {
        val baseline = session("https://school.example.cz", "student-a", "account-a")
        val scopes = setOf(
            hasher.schoolScope(baseline),
            hasher.schoolScope(baseline.copy(baseURL = "https://other.example.cz")),
            hasher.schoolScope(baseline.copy(bakalari = BakalariCredentials("student-b", "secret"))),
            hasher.schoolScope(baseline.copy(linkedAccountID = "account-b")),
            GradeyAISchoolScopeHasher(ByteArray(32) { 8 }).schoolScope(baseline),
        )

        assertThat(scopes).hasSize(5)
    }

    private fun session(baseURL: String, username: String, linkedAccountID: String) = StoredSession(
        accessToken = "must-not-leak",
        refreshToken = "must-not-leak",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = baseURL,
        bakalari = BakalariCredentials(username, "secret"),
        linkedAccountID = linkedAccountID,
    )
}
