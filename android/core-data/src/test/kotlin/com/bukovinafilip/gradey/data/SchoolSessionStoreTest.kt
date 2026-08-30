package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StoredSchoolSessionEnvelope
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolSessionStoreTest {
    @Test
    fun legacySessionMigratesToCurrentEnvelopeWithoutSigningOut() {
        val legacy = session()
        val values = FakeSchoolSessionValueStore(legacy = legacy)
        val store = SchoolSessionStore(values)

        val restored = store.load()

        assertThat(restored).isEqualTo(legacy)
        assertThat(values.current?.formatVersion).isEqualTo(2)
        assertThat(values.current?.session).isEqualTo(legacy)
        assertThat(values.legacy).isNull()
    }

    @Test
    fun currentEnvelopeRestoresWithoutConsultingLegacyRecord() {
        val current = session(accessToken = "current-access")
        val legacy = session(accessToken = "legacy-access")
        val values = FakeSchoolSessionValueStore(
            current = StoredSchoolSessionEnvelope(2, current),
            legacy = legacy,
        )

        val restored = SchoolSessionStore(values).load()

        assertThat(restored).isEqualTo(current)
        assertThat(values.legacy).isEqualTo(legacy)
    }

    @Test
    fun unknownFutureEnvelopeIsRejectedInsteadOfMisread() {
        val values = FakeSchoolSessionValueStore(
            current = StoredSchoolSessionEnvelope(99, session()),
            legacy = session(accessToken = "stale-legacy"),
        )

        val restored = SchoolSessionStore(values).load()

        assertThat(restored).isNull()
        assertThat(values.current).isNull()
        assertThat(values.legacy).isNotNull()
    }

    @Test
    fun clearRemovesCurrentAndLegacyRecords() {
        val values = FakeSchoolSessionValueStore(
            current = StoredSchoolSessionEnvelope(2, session()),
            legacy = session(),
        )

        SchoolSessionStore(values).clear()

        assertThat(values.current).isNull()
        assertThat(values.legacy).isNull()
    }

    private fun session(accessToken: String = "access") = StoredSession(
        accessToken = accessToken,
        refreshToken = "refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = 4_102_444_800_000,
        baseURL = "https://school.example.cz",
        provider = SchoolProvider.BAKALARI,
        bakalari = BakalariCredentials("student", "secret"),
    )
}

private class FakeSchoolSessionValueStore(
    var current: StoredSchoolSessionEnvelope? = null,
    var legacy: StoredSession? = null,
) : SchoolSessionValueStore {
    override fun loadCurrent(): StoredSchoolSessionEnvelope? = current
    override fun loadLegacy(): StoredSession? = legacy
    override fun saveCurrent(envelope: StoredSchoolSessionEnvelope) {
        current = envelope
    }
    override fun clearCurrent() {
        current = null
    }
    override fun clearLegacy() {
        legacy = null
    }
}
