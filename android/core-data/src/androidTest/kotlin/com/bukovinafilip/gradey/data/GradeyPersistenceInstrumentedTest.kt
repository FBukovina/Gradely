package com.bukovinafilip.gradey.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSchoolSessionEnvelope
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import java.io.FileOutputStream
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.serializer
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyPersistenceInstrumentedTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val databaseNames = mutableSetOf<String>()

    @After
    fun cleanUp() {
        databaseNames.forEach(context::deleteDatabase)
        context.getSharedPreferences("gradey-test-session-index", Context.MODE_PRIVATE)
            .edit().clear().commit()
    }

    @Test
    fun versionOneCacheMigratesWithoutLosingEntries() {
        runBlocking {
            val name = databaseName("migration")
            val path = context.getDatabasePath(name)
            path.parentFile?.mkdirs()
            SQLiteDatabase.openOrCreateDatabase(path, null).use { legacy ->
                legacy.execSQL(
                    "CREATE TABLE IF NOT EXISTS `cache_entries` " +
                        "(`key` TEXT NOT NULL, `payload` TEXT NOT NULL, " +
                        "`cachedAtEpochMillis` INTEGER NOT NULL, PRIMARY KEY(`key`))",
                )
                legacy.execSQL(
                    "INSERT INTO `cache_entries` (`key`, `payload`, `cachedAtEpochMillis`) VALUES (?, ?, ?)",
                    arrayOf<Any>("dashboard-school", "{\"value\":1}", 1234L),
                )
                legacy.version = 1
            }

            val migrated = buildGradeyDatabase(context, name)
            val entry = migrated.cacheEntries().load("dashboard-school")
            val indexes = migrated.openHelper.readableDatabase.query(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
                arrayOf("index_cache_entries_cachedAtEpochMillis"),
            ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
            migrated.close()

            assertThat(entry?.payload).isEqualTo("{\"value\":1}")
            assertThat(entry?.cachedAtEpochMillis).isEqualTo(1234L)
            assertThat(indexes).containsExactly("index_cache_entries_cachedAtEpochMillis")
        }
    }

    @Test
    fun corruptDisposableCacheIsRecreatedAndRemainsWritable() {
        runBlocking {
            val name = databaseName("corrupt")
            val first = buildGradeyDatabase(context, name)
            first.cacheEntries().save(CacheEntryEntity("old", "payload", 1))
            first.close()
            FileOutputStream(context.getDatabasePath(name), false).use { stream ->
                stream.write("not-a-sqlite-database".encodeToByteArray())
            }

            val recovered = buildGradeyDatabase(context, name)
            recovered.cacheEntries().save(CacheEntryEntity("new", "safe", 2))

            assertThat(recovered.cacheEntries().load("old")).isNull()
            assertThat(recovered.cacheEntries().load("new")?.payload).isEqualTo("safe")
            recovered.close()
        }
    }

    @Test
    fun encryptedLegacySessionMigratesAtomicallyToCurrentEnvelope() {
        val fileName = "gradey-test-session-${System.nanoTime()}"
        val secureStore = SecureJsonStore(context, fileName, GradeyJson)
        val session = session()
        secureStore.save("school.session.v1", session, StoredSession.serializer())

        val restored = SchoolSessionStore(secureStore).load()

        assertThat(restored).isEqualTo(session)
        assertThat(
            secureStore.load("school.session.v2", StoredSchoolSessionEnvelope.serializer()),
        ).isEqualTo(StoredSchoolSessionEnvelope(2, session))
        assertThat(secureStore.load("school.session.v1", StoredSession.serializer())).isNull()
    }

    @Test
    fun malformedEncryptedCurrentSessionIsClearedInsteadOfCrashing() {
        val fileName = "gradey-test-session-${System.nanoTime()}"
        val secureStore = SecureJsonStore(context, fileName, GradeyJson)
        secureStore.save("school.session.v2", "malformed-envelope", String.serializer())

        val restored = SchoolSessionStore(secureStore).load()

        assertThat(restored).isNull()
        assertThat(secureStore.load("school.session.v2", String.serializer())).isNull()
    }

    private fun databaseName(kind: String): String = "gradey-$kind-${System.nanoTime()}.db"
        .also(databaseNames::add)

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
