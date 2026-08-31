package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StoredSchoolSessionEnvelope
import com.google.common.truth.Truth.assertThat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
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
        assertThat(values.replaceTransactions).isEqualTo(1)
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
        assertThat(values.legacy).isNull()
        assertThat(values.clearAllTransactions).isEqualTo(1)
        assertThat(SchoolSessionStore(values).load()).isNull()
    }

    @Test
    fun malformedCurrentRecordRejectsLegacyOnFirstAndRecreatedLoad() {
        val values = FakeSchoolSessionValueStore(
            currentRejected = true,
            legacy = session(accessToken = "stale-legacy"),
        )

        val firstLoad = SchoolSessionStore(values).load()
        val recreatedLoad = SchoolSessionStore(values).load()

        assertThat(firstLoad).isNull()
        assertThat(recreatedLoad).isNull()
        assertThat(values.currentRejected).isFalse()
        assertThat(values.legacy).isNull()
        assertThat(values.clearAllTransactions).isEqualTo(1)
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
        assertThat(values.clearAllTransactions).isEqualTo(1)
    }

    @Test
    fun saveReplacesCurrentAndLegacyInOneValueStoreTransaction() {
        val values = FakeSchoolSessionValueStore(
            current = StoredSchoolSessionEnvelope(2, session(accessToken = "old-current")),
            legacy = session(accessToken = "old-legacy"),
        )
        val replacement = session(accessToken = "replacement")

        SchoolSessionStore(values).save(replacement)

        assertThat(values.current?.session).isEqualTo(replacement)
        assertThat(values.legacy).isNull()
        assertThat(values.replaceTransactions).isEqualTo(1)
    }

    @Test
    fun clearWaitsForLegacyMigrationAndRemovesTheMigratedEnvelope() {
        val values = BlockingLegacySchoolSessionValueStore(session())
        val store = SchoolSessionStore(values)
        val migrationFailure = AtomicReference<Throwable?>()
        val clearFailure = AtomicReference<Throwable?>()
        val clearStarted = CountDownLatch(1)
        val clearFinished = CountDownLatch(1)
        val migration = thread(name = "school-session-migration") {
            runCatching { store.load() }.exceptionOrNull()?.let(migrationFailure::set)
        }
        assertThat(values.legacyRead.await(5, TimeUnit.SECONDS)).isTrue()
        val clearing = thread(name = "school-session-clear") {
            clearStarted.countDown()
            runCatching { store.clear() }.exceptionOrNull()?.let(clearFailure::set)
            clearFinished.countDown()
        }
        assertThat(clearStarted.await(5, TimeUnit.SECONDS)).isTrue()

        val clearCompletedDuringMigration = clearFinished.await(100, TimeUnit.MILLISECONDS)
        values.releaseLegacyRead.countDown()
        migration.join(5_000)
        clearing.join(5_000)

        assertThat(clearCompletedDuringMigration).isFalse()
        assertThat(migration.isAlive).isFalse()
        assertThat(clearing.isAlive).isFalse()
        assertThat(migrationFailure.get()).isNull()
        assertThat(clearFailure.get()).isNull()
        assertThat(values.current).isNull()
        assertThat(values.legacy).isNull()
        assertThat(store.load()).isNull()
    }

    @Test
    fun detachedSaveWaitsForLegacyMigrationAndCannotBeOverwrittenByIt() {
        val linked = session().copy(
            linkedAccountID = "account-a",
            linkedAccountDisplayName = "Student A",
            linkedAccountSchoolName = "School A",
        )
        val values = BlockingLegacySchoolSessionValueStore(linked)
        val store = SchoolSessionStore(values)
        val migrationFailure = AtomicReference<Throwable?>()
        val detachFailure = AtomicReference<Throwable?>()
        val detachStarted = CountDownLatch(1)
        val detachFinished = CountDownLatch(1)
        val migration = thread(name = "school-session-migration") {
            runCatching { store.load() }.exceptionOrNull()?.let(migrationFailure::set)
        }
        assertThat(values.legacyRead.await(5, TimeUnit.SECONDS)).isTrue()
        val detaching = thread(name = "school-session-detach") {
            detachStarted.countDown()
            runCatching {
                val current = store.load() ?: return@runCatching
                store.save(
                    current.copy(
                        linkedAccountID = null,
                        linkedAccountDisplayName = null,
                        linkedAccountSchoolName = null,
                    ),
                )
            }.exceptionOrNull()?.let(detachFailure::set)
            detachFinished.countDown()
        }
        assertThat(detachStarted.await(5, TimeUnit.SECONDS)).isTrue()

        val detachCompletedDuringMigration = detachFinished.await(100, TimeUnit.MILLISECONDS)
        values.releaseLegacyRead.countDown()
        migration.join(5_000)
        detaching.join(5_000)

        val retained = store.load()
        assertThat(detachCompletedDuringMigration).isFalse()
        assertThat(migration.isAlive).isFalse()
        assertThat(detaching.isAlive).isFalse()
        assertThat(migrationFailure.get()).isNull()
        assertThat(detachFailure.get()).isNull()
        assertThat(retained?.accessToken).isEqualTo(linked.accessToken)
        assertThat(retained?.bakalari).isEqualTo(linked.bakalari)
        assertThat(retained?.linkedAccountID).isNull()
        assertThat(retained?.linkedAccountDisplayName).isNull()
        assertThat(retained?.linkedAccountSchoolName).isNull()
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
    var currentRejected: Boolean = false,
) : SchoolSessionValueStore {
    var replaceTransactions = 0
        private set
    var clearAllTransactions = 0
        private set

    override fun loadCurrent(): SecureJsonReadResult<StoredSchoolSessionEnvelope> = when {
        currentRejected -> SecureJsonReadResult.Rejected
        current == null -> SecureJsonReadResult.Absent
        else -> SecureJsonReadResult.Valid(checkNotNull(current))
    }
    override fun loadLegacy(): StoredSession? = legacy
    override fun replaceCurrentAndClearLegacy(envelope: StoredSchoolSessionEnvelope) {
        replaceTransactions += 1
        currentRejected = false
        current = envelope
        legacy = null
    }
    override fun clearCurrentAndLegacy() {
        clearAllTransactions += 1
        currentRejected = false
        current = null
        legacy = null
    }
}

private class BlockingLegacySchoolSessionValueStore(
    legacySession: StoredSession,
) : SchoolSessionValueStore {
    @Volatile
    var current: StoredSchoolSessionEnvelope? = null
        private set

    @Volatile
    var legacy: StoredSession? = legacySession
        private set

    val legacyRead = CountDownLatch(1)
    val releaseLegacyRead = CountDownLatch(1)

    override fun loadCurrent(): SecureJsonReadResult<StoredSchoolSessionEnvelope> =
        current?.let { SecureJsonReadResult.Valid(it) } ?: SecureJsonReadResult.Absent

    override fun loadLegacy(): StoredSession? {
        val captured = legacy
        legacyRead.countDown()
        check(releaseLegacyRead.await(5, TimeUnit.SECONDS)) { "Timed out waiting to release legacy read." }
        return captured
    }

    override fun replaceCurrentAndClearLegacy(envelope: StoredSchoolSessionEnvelope) {
        current = envelope
        legacy = null
    }

    override fun clearCurrentAndLegacy() {
        current = null
        legacy = null
    }
}
