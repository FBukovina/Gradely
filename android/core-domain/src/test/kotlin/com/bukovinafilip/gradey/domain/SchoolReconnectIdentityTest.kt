package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolReconnectIdentityTest {
    @Test
    fun `only matching nonblank canonical provider identities permit reconnect`() {
        val cases = listOf(
            IdentityCase(existing = "student-1", candidate = "student-1", expected = true),
            IdentityCase(existing = " student-1 ", candidate = "student-1", expected = true),
            IdentityCase(existing = "student-1", candidate = " student-1 ", expected = true),
            IdentityCase(existing = "student-1", candidate = "student-2", expected = false),
            IdentityCase(existing = null, candidate = "student-1", expected = false),
            IdentityCase(existing = "", candidate = "student-1", expected = false),
            IdentityCase(existing = "   ", candidate = "student-1", expected = false),
            IdentityCase(existing = "student-1", candidate = null, expected = false),
            IdentityCase(existing = "student-1", candidate = "", expected = false),
            IdentityCase(existing = "student-1", candidate = "   ", expected = false),
        )

        cases.forEach { testCase ->
            assertThat(
                SchoolReconnectIdentities.match(
                    existingProviderUserID = testCase.existing,
                    candidateProviderUserID = testCase.candidate,
                ),
            ).isEqualTo(testCase.expected)
        }
    }

    private data class IdentityCase(
        val existing: String?,
        val candidate: String?,
        val expected: Boolean,
    )
}
