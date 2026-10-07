package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.Json
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

    @Test
    fun `same username on path based schools has isolated local scopes`() {
        val first = session(username = "student.one")
            .copy(baseURL = "https://school.example/school-a")
            .stabilizedLocalCacheIdentity()
        val second = session(username = "student.one")
            .copy(baseURL = "https://school.example/school-b")
            .stabilizedLocalCacheIdentity()

        assertThat(first.cacheScope).isNotEqualTo(second.cacheScope)
        assertThat(first.cacheScope).startsWith("bakalari-school.example-")
        assertThat(second.cacheScope).startsWith("bakalari-school.example-")
    }

    @Test
    fun `pre upgrade path session retains legacy host alias until identity is stabilized`() {
        val legacy = session(username = "student.one")
            .copy(baseURL = "https://school.example/school-a")
        val legacyOtherPath = legacy.copy(baseURL = "https://school.example/school-b")
        val stabilized = legacy.stabilizedLocalCacheIdentity()
        val legacyJson = Json.encodeToString(StoredSession.serializer(), legacy)
        val restoredLegacy = Json.decodeFromString(StoredSession.serializer(), legacyJson)

        assertThat(legacy.cacheScope).isEqualTo(legacyOtherPath.cacheScope)
        assertThat(legacyJson).doesNotContain("localCacheIdentity")
        assertThat(restoredLegacy.localCacheIdentity).isNull()
        assertThat(restoredLegacy.cacheScope).isEqualTo(legacy.cacheScope)
        assertThat(stabilized.cacheScope).isNotEqualTo(legacy.cacheScope)
    }

    @Test
    fun `credentialless linked students on one server detach to isolated stable scopes`() {
        val first = session(username = "unused").copy(
            bakalari = null,
            linkedAccountID = "account-a",
        ).stabilizedLocalCacheIdentity(providerUserID = "provider-user-a")
        val second = session(username = "unused").copy(
            bakalari = null,
            linkedAccountID = "account-b",
        ).stabilizedLocalCacheIdentity(providerUserID = "provider-user-b")

        val firstLocal = first.copy(linkedAccountID = null)
        val secondLocal = second.copy(linkedAccountID = null)

        assertThat(firstLocal.cacheScope).isNotEqualTo(secondLocal.cacheScope)
        assertThat(firstLocal.cacheScope).doesNotContain("default")
        assertThat(secondLocal.cacheScope).doesNotContain("default")
    }

    @Test
    fun `stable local cache identity survives stored session serialization`() {
        val linked = session(username = "unused").copy(
            bakalari = null,
            linkedAccountID = "account-a",
        ).stabilizedLocalCacheIdentity(linkedAccountID = "account-a")
        val encoded = Json.encodeToString(StoredSession.serializer(), linked)

        val restored = Json.decodeFromString(StoredSession.serializer(), encoded)

        assertThat(restored.localCacheIdentity).isEqualTo(linked.localCacheIdentity)
        assertThat(restored.copy(linkedAccountID = null).cacheScope)
            .isEqualTo(linked.copy(linkedAccountID = null).cacheScope)
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
