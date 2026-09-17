package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.SchoolDirectoryClient
import com.bukovinafilip.gradey.model.CachedSchoolDirectory
import com.bukovinafilip.gradey.model.SchoolDirectoryMunicipality
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.google.common.truth.Truth.assertThat
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AndroidSchoolDirectoryRepositoryTest {
    @Test
    fun `healthy refresh filters sorts deduplicates and caches`() = runTest {
        val client = FakeDirectoryClient(
            municipalities = listOf(
                municipality("", 10),
                municipality("Praha", 1),
                municipality("Brno", 1),
            ),
            schoolsByTown = mapOf(
                "Praha" to listOf(school("praha", "Základní škola", "Praha", "HTTPS://SCHOOL.EXAMPLE")),
                "Brno" to listOf(
                    school("brno", "Gymnázium", "Brno", "https://brno.example"),
                    school("duplicate", "Duplicate", "Brno", "https://school.example"),
                ),
            ),
        )
        val storage = FakeDirectoryStorage()
        val repository = repository(client, storage)

        val result = repository.refreshDirectory()

        assertThat(result.map { it.id }).containsExactly("duplicate", "brno").inOrder()
        assertThat(storage.directory?.schools).isEqualTo(result)
        assertThat(storage.directory?.formatVersion).isEqualTo(CachedSchoolDirectory.CURRENT_FORMAT_VERSION)
    }

    @Test
    fun `partial refresh merges cache without replacing it`() = runTest {
        val cached = listOf(school("cached", "Cached", "Praha", "https://cached.example"))
        val storage = FakeDirectoryStorage(
            CachedSchoolDirectory(cached, cachedAtEpochMillis = 1_000),
        )
        val client = FakeDirectoryClient(
            municipalities = listOf(municipality("Praha", 1), municipality("Brno", 9)),
            schoolsByTown = mapOf(
                "Praha" to listOf(school("new", "New", "Praha", "https://new.example")),
            ),
        )
        val repository = repository(client, storage, maximumAttempts = 1)

        val result = repository.refreshDirectory()

        assertThat(result.map { it.id }).containsExactly("cached", "new")
        assertThat(storage.saveCount).isEqualTo(0)
        assertThat(storage.directory?.schools).isEqualTo(cached)
    }

    @Test
    fun `town failure is retried once before succeeding`() = runTest {
        val client = FakeDirectoryClient(
            municipalities = listOf(municipality("Praha", 1)),
            schoolsByTown = mapOf("Praha" to listOf(school("school", "School", "Praha", "https://school.example"))),
            failuresBeforeSuccess = mutableMapOf("Praha" to 1),
        )
        val repository = repository(client, FakeDirectoryStorage())

        val result = repository.refreshDirectory()

        assertThat(result.map { it.id }).containsExactly("school")
        assertThat(client.townRequestCount["Praha"]).isEqualTo(2)
    }

    @Test
    fun `town request concurrency is bounded`() = runTest {
        val towns = (1..5).map { municipality("Town $it", 1) }
        val client = FakeDirectoryClient(
            municipalities = towns,
            schoolsByTown = towns.associate { town ->
                town.name to listOf(
                    school(town.name, town.name, town.name, "https://${town.name.replace(" ", "-")}.example"),
                )
            },
            townDelayMillis = 100,
        )
        val repository = repository(client, FakeDirectoryStorage())

        repository.refreshDirectory()

        assertThat(client.maximumActiveTownRequests).isEqualTo(2)
    }

    @Test
    fun `batch timeout returns existing cache without overwriting it`() = runTest {
        val cached = listOf(school("cached", "Cached", "Praha", "https://cached.example"))
        val storage = FakeDirectoryStorage(CachedSchoolDirectory(cached, cachedAtEpochMillis = 1_000))
        val client = FakeDirectoryClient(
            municipalities = listOf(municipality("Slow", 1)),
            schoolsByTown = emptyMap(),
            townDelayMillis = 5_000,
        )
        val repository = repository(client, storage, batchTimeoutMillis = 100)

        val result = repository.refreshDirectory()

        assertThat(result).isEqualTo(cached)
        assertThat(storage.saveCount).isEqualTo(0)
    }

    @Test
    fun `empty first load fails instead of caching an empty directory`() = runTest {
        val repository = repository(
            FakeDirectoryClient(municipalities = emptyList()),
            FakeDirectoryStorage(),
        )

        val failure = runCatching { repository.refreshDirectory() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(SchoolDirectoryException::class.java)
    }

    private fun repository(
        client: SchoolDirectoryClient,
        storage: SchoolDirectoryStorage,
        maximumAttempts: Int = 2,
        batchTimeoutMillis: Long = 25_000,
    ) = AndroidSchoolDirectoryRepository(
        client = client,
        storage = storage,
        maxConcurrentTownRequests = 2,
        batchTimeoutMillis = batchTimeoutMillis,
        maximumTownRequestAttempts = maximumAttempts,
        nowEpochMillis = { 123_456 },
        retryDelay = {},
    )

    private fun municipality(name: String, count: Int) = SchoolDirectoryMunicipality(name, count)

    private fun school(id: String, name: String, town: String, url: String) =
        SchoolDirectorySchool(id, name, town, url)

    private class FakeDirectoryStorage(
        var directory: CachedSchoolDirectory? = null,
    ) : SchoolDirectoryStorage {
        var saveCount = 0

        override suspend fun load(): CachedSchoolDirectory? = directory

        override suspend fun save(directory: CachedSchoolDirectory) {
            saveCount += 1
            this.directory = directory
        }
    }

    private class FakeDirectoryClient(
        private val municipalities: List<SchoolDirectoryMunicipality>,
        private val schoolsByTown: Map<String, List<SchoolDirectorySchool>> = emptyMap(),
        private val failuresBeforeSuccess: MutableMap<String, Int> = mutableMapOf(),
        private val townDelayMillis: Long = 0,
    ) : SchoolDirectoryClient {
        val townRequestCount = mutableMapOf<String, Int>()
        var maximumActiveTownRequests = 0
            private set
        private var activeTownRequests = 0

        override suspend fun fetchMunicipalities(): List<SchoolDirectoryMunicipality> = municipalities

        override suspend fun fetchSchools(municipalityName: String): List<SchoolDirectorySchool> {
            townRequestCount[municipalityName] = townRequestCount.getOrDefault(municipalityName, 0) + 1
            activeTownRequests += 1
            maximumActiveTownRequests = maxOf(maximumActiveTownRequests, activeTownRequests)
            try {
                if (townDelayMillis > 0) delay(townDelayMillis)
                val remainingFailures = failuresBeforeSuccess.getOrDefault(municipalityName, 0)
                if (remainingFailures > 0) {
                    failuresBeforeSuccess[municipalityName] = remainingFailures - 1
                    throw IOException("temporary failure")
                }
                return schoolsByTown[municipalityName] ?: throw IOException("missing town response")
            } finally {
                activeTownRequests -= 1
            }
        }
    }
}
