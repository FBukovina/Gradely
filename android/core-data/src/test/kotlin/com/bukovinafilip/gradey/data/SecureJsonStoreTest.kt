package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SecureJsonStoreTest {
    @Test
    fun `legacy EduPage session is rejected and cleared`() {
        var cleared = false
        val legacySession = """
            {
              "accessToken":"old-access",
              "refreshToken":"old-refresh",
              "tokenType":"Bearer",
              "expiresAtEpochMillis":4102444800000,
              "baseURL":"https://school.edupage.org",
              "provider":"edupage"
            }
        """.trimIndent()

        val session = decodeStoredValueOrClear(
            encoded = legacySession,
            serializer = StoredSession.serializer(),
            json = GradeyJson,
            clear = { cleared = true },
        )

        assertThat(session).isNull()
        assertThat(cleared).isTrue()
    }

    @Test
    fun `valid Bakalari session is retained`() {
        var cleared = false
        val encoded = """
            {
              "accessToken":"access",
              "refreshToken":"refresh",
              "tokenType":"Bearer",
              "expiresAtEpochMillis":4102444800000,
              "baseURL":"https://school.example",
              "provider":"bakalari"
            }
        """.trimIndent()

        val session = decodeStoredValueOrClear(
            encoded = encoded,
            serializer = StoredSession.serializer(),
            json = GradeyJson,
            clear = { cleared = true },
        )

        assertThat(session?.baseURL).isEqualTo("https://school.example")
        assertThat(cleared).isFalse()
    }
}
