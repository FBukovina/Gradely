package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SecureJsonStoreTest {
    @Test
    fun `tri-state read distinguishes absent valid and rejected without mutating storage`() {
        val preferences = RecordingSecureJsonPreferences(
            initialValues = mapOf(
                "valid" to GradeyJson.encodeToString(StoredSession.serializer(), session()),
                "rejected" to "{not-json",
            ),
        )
        val store = SecureJsonStore(preferences, GradeyJson)

        val absent = store.read("absent", StoredSession.serializer())
        val valid = store.read("valid", StoredSession.serializer())
        val rejected = store.read("rejected", StoredSession.serializer())

        assertThat(absent).isEqualTo(SecureJsonReadResult.Absent)
        assertThat(valid).isInstanceOf(SecureJsonReadResult.Valid::class.java)
        assertThat((valid as SecureJsonReadResult.Valid<*>).value).isEqualTo(session())
        assertThat(rejected).isEqualTo(SecureJsonReadResult.Rejected)
        assertThat(preferences.commits).isEmpty()
        assertThat(preferences.values).containsKey("rejected")
    }

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

    @Test
    fun `secure save propagates synchronous commit failure`() {
        val preferences = RecordingSecureJsonPreferences(commitSucceeds = false)
        val store = SecureJsonStore(preferences, GradeyJson)

        val failure = runCatching {
            store.save("session", session(), StoredSession.serializer())
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("Failed to persist secure JSON values")
        assertThat(preferences.commits).hasSize(1)
        assertThat(preferences.values).doesNotContainKey("session")
    }

    @Test
    fun `secure replacement writes current and removes legacy in one commit`() {
        val preferences = RecordingSecureJsonPreferences(
            initialValues = mapOf("legacy" to "legacy-payload"),
        )
        val store = SecureJsonStore(preferences, GradeyJson)

        store.saveReplacing(
            key = "current",
            value = session(),
            serializer = StoredSession.serializer(),
            removeKeys = setOf("legacy"),
        )

        assertThat(preferences.commits).hasSize(1)
        assertThat(preferences.commits.single().keys).containsExactly("legacy", "current")
        assertThat(preferences.commits.single()["legacy"]).isNull()
        assertThat(preferences.commits.single()["current"]).isNotNull()
        assertThat(preferences.values).containsKey("current")
        assertThat(preferences.values).doesNotContainKey("legacy")
    }

    @Test
    fun `secure multi-key clear uses one commit`() {
        val preferences = RecordingSecureJsonPreferences(
            initialValues = mapOf("current" to "current-payload", "legacy" to "legacy-payload"),
        )
        val store = SecureJsonStore(preferences, GradeyJson)

        store.clear(setOf("current", "legacy"))

        assertThat(preferences.commits).hasSize(1)
        assertThat(preferences.commits.single().keys).containsExactly("current", "legacy")
        assertThat(preferences.values).isEmpty()
    }

    @Test
    fun `rejected current identity atomically clears legacy and never falls back`() {
        val preferences = RecordingSecureJsonPreferences(
            initialValues = mapOf(
                "current" to "{not-json",
                "legacy" to GradeyJson.encodeToString(StoredSession.serializer(), session()),
            ),
        )
        val store = SecureJsonStore(preferences, GradeyJson)

        val first = store.loadCurrentOrMigrateLegacy(
            currentKey = "current",
            legacyKey = "legacy",
            serializer = StoredSession.serializer(),
        )
        val second = store.loadCurrentOrMigrateLegacy(
            currentKey = "current",
            legacyKey = "legacy",
            serializer = StoredSession.serializer(),
        )

        assertThat(first).isNull()
        assertThat(second).isNull()
        assertThat(preferences.commits).hasSize(1)
        assertThat(preferences.commits.single().keys).containsExactly("current", "legacy")
        assertThat(preferences.values).isEmpty()
    }

    @Test
    fun `valid legacy identity migrates with one durable replacement`() {
        val preferences = RecordingSecureJsonPreferences(
            initialValues = mapOf(
                "legacy" to GradeyJson.encodeToString(StoredSession.serializer(), session()),
            ),
        )
        val store = SecureJsonStore(preferences, GradeyJson)

        val migrated = store.loadCurrentOrMigrateLegacy(
            currentKey = "current",
            legacyKey = "legacy",
            serializer = StoredSession.serializer(),
        )

        assertThat(migrated).isEqualTo(session())
        assertThat(preferences.commits).hasSize(1)
        assertThat(preferences.commits.single().keys).containsExactly("legacy", "current")
        assertThat(preferences.values).containsKey("current")
        assertThat(preferences.values).doesNotContainKey("legacy")
    }

    private fun session() = StoredSession(
        accessToken = "access",
        refreshToken = "refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = 4_102_444_800_000,
        baseURL = "https://school.example.cz",
        provider = SchoolProvider.BAKALARI,
        bakalari = BakalariCredentials("student", "secret"),
    )
}

private class RecordingSecureJsonPreferences(
    initialValues: Map<String, String> = emptyMap(),
    private val commitSucceeds: Boolean = true,
) : SecureJsonPreferences {
    val values = initialValues.toMutableMap()
    val commits = mutableListOf<Map<String, String?>>()

    override fun getString(key: String, defaultValue: String?): String? = values[key] ?: defaultValue

    override fun commit(changes: Map<String, String?>): Boolean {
        commits += changes.toMap()
        if (!commitSucceeds) return false
        changes.forEach { (key, value) ->
            if (value == null) values.remove(key) else values[key] = value
        }
        return true
    }
}
