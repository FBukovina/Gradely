package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.UserResponse
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class LocalLinkedAccountSchoolNameTest {
    @Test
    fun `valid API school name wins over fallback`() {
        val user = UserResponse(
            fullName = "Student",
            schoolOrganizationName = " API School ",
            schoolName = "Fallback API School",
        )

        assertThat(resolvedLocalLinkedSchoolName(user, "Stored School")).isEqualTo("API School")
    }

    @Test
    fun `real fallback is trimmed and retained`() {
        assertThat(resolvedLocalLinkedSchoolName(null, "  Stored School  ")).isEqualTo("Stored School")
    }

    @Test
    fun `placeholder API and fallback names resolve to null`() {
        val user = UserResponse(fullName = "Student", schoolName = "název školy")

        assertThat(resolvedLocalLinkedSchoolName(user, " NÁZEV   ŠKOLY ")).isNull()
    }
}
