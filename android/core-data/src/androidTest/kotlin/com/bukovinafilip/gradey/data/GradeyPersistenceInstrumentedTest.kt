package com.bukovinafilip.gradey.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.domain.BakalariDemoAccount
import com.bukovinafilip.gradey.domain.SchoolDirectoryNameResolver
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSchoolSessionEnvelope
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.network.DemoAwareBakalariClient
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
    private val sharedPreferenceNames = mutableSetOf<String>()

    @After
    fun cleanUp() {
        databaseNames.forEach(context::deleteDatabase)
        sharedPreferenceNames.forEach(context::deleteSharedPreferences)
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

    @Test
    fun demoLoginPersistsAndLoadsDashboardOnAndroidRuntime() = runBlocking {
        val database = buildGradeyDatabase(context, databaseName("demo-login"))
        try {
            val sessionStore = SchoolSessionStore(
                SecureJsonStore(context, sharedPreferenceName("demo-login"), GradeyJson),
            )
            val repository = AndroidSchoolRepository(
                bakalariClient = DemoAwareBakalariClient(),
                sessionStore = sessionStore,
                cache = RoomGradeyCache(database.cacheEntries(), GradeyJson),
            )

            val session = repository.login(
                schoolURL = BakalariDemoAccount.schoolURL,
                username = BakalariDemoAccount.username,
                password = BakalariDemoAccount.password,
            )

            assertThat(session.cacheScope)
                .isEqualTo("bakalari-demo.gradely.app-702769b16df31c33250a36d9")
            assertThat(repository.bootstrapSession()).isEqualTo(session)

            val dashboard = repository.loadDashboard(forceRefresh = false)
            assertThat(dashboard.user?.fullName).isEqualTo("Alex Novak")
            assertThat(dashboard.user?.displaySchoolName).isEqualTo("Gradey Demo School")
            assertThat(
                SchoolDirectoryNameResolver.displayableName("\u0085Název\u00A0školy\u0085"),
            ).isNull()
        } finally {
            database.close()
        }
    }

    @Test
    fun schoolScopeCopyRollsBackEveryDestinationRowWhenOneRoomWriteFails() = runBlocking {
        val database = buildGradeyDatabase(context, databaseName("scope-copy-rollback"))
        try {
            val cache = RoomGradeyCache(database.cacheEntries(), GradeyJson)
            val source = "linked-account-a"
            val destination = "bakalari-school.example-local-a"
            cache.saveDashboard(source, DashboardData(MarksResponse()))
            cache.saveMarks(source, MarksResponse())
            database.openHelper.writableDatabase.execSQL(
                """
                CREATE TRIGGER fail_scope_copy
                BEFORE INSERT ON cache_entries
                WHEN NEW.`key` = 'marks:$destination'
                BEGIN
                    SELECT RAISE(ABORT, 'forced scope-copy failure');
                END
                """.trimIndent(),
            )

            val failure = runCatching {
                cache.copySchoolScope(source, destination)
            }.exceptionOrNull()

            assertThat(failure).isNotNull()
            assertThat(cache.loadDashboard(destination)).isNull()
            assertThat(cache.loadMarks(destination)).isNull()
            assertThat(cache.loadDashboard(source)).isNotNull()
            assertThat(cache.loadMarks(source)).isNotNull()
        } finally {
            database.close()
        }
    }

    private fun databaseName(kind: String): String = "gradey-$kind-${System.nanoTime()}.db"
        .also(databaseNames::add)

    private fun sharedPreferenceName(kind: String): String = "gradey-$kind-${System.nanoTime()}"
        .also(sharedPreferenceNames::add)

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
