package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.SchoolDirectoryClient
import com.bukovinafilip.gradey.domain.SchoolDirectoryRepository
import com.bukovinafilip.gradey.model.CachedSchoolDirectory
import com.bukovinafilip.gradey.model.SchoolDirectoryMunicipality
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import java.text.Collator
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull

class SchoolDirectoryException(
    message: String = "We couldn't load the Bakaláři school directory. You can still enter the school URL manually.",
    cause: Throwable? = null,
) : RuntimeException(message, cause)

interface SchoolDirectoryStorage {
    suspend fun load(): CachedSchoolDirectory?
    suspend fun save(directory: CachedSchoolDirectory)
}

class RoomSchoolDirectoryStorage(
    private val cache: RoomGradeyCache,
) : SchoolDirectoryStorage {
    override suspend fun load(): CachedSchoolDirectory? = cache.loadSchoolDirectory()

    override suspend fun save(directory: CachedSchoolDirectory) = cache.saveSchoolDirectory(directory)
}

class AndroidSchoolDirectoryRepository(
    private val client: SchoolDirectoryClient,
    private val storage: SchoolDirectoryStorage,
    private val maxConcurrentTownRequests: Int = 8,
    private val batchTimeoutMillis: Long = 25_000,
    private val maximumTownRequestAttempts: Int = 2,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
    private val retryDelay: suspend (Long) -> Unit = { delay(it) },
) : SchoolDirectoryRepository {
    override suspend fun loadCachedDirectory(): CachedSchoolDirectory? = storage.load()

    override suspend fun refreshDirectory(): List<SchoolDirectorySchool> {
        val municipalities = try {
            client.fetchMunicipalities()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            throw SchoolDirectoryException(cause = error)
        }.filter { municipality -> municipality.name.isNotBlank() && municipality.schoolCount > 0 }
        if (municipalities.isEmpty()) throw SchoolDirectoryException()

        val batch = fetchSchoolBatch(municipalities)
        val freshSchools = uniqueSortedSchools(batch.schools)
        val cachedDirectory = try {
            storage.load()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        val mergedSchools = uniqueSortedSchools(cachedDirectory.orEmpty() + freshSchools)
        if (mergedSchools.isEmpty()) throw SchoolDirectoryException()

        if (batch.isHealthyForCaching(cachedDirectory?.isCurrentFormat == true)) {
            storage.save(
                CachedSchoolDirectory(
                    schools = mergedSchools,
                    cachedAtEpochMillis = nowEpochMillis(),
                ),
            )
        }
        return mergedSchools
    }

    private suspend fun fetchSchoolBatch(
        municipalities: List<SchoolDirectoryMunicipality>,
    ): SchoolFetchBatch = supervisorScope {
        val schools = mutableListOf<SchoolDirectorySchool>()
        var successfulExpectedSchoolCount = 0
        val resultMutex = Mutex()
        val semaphore = Semaphore(maxConcurrentTownRequests.coerceAtLeast(1))
        val jobs = municipalities.map { municipality ->
            launch {
                semaphore.withPermit {
                    try {
                        val result = fetchSchoolsWithRetry(municipality.name)
                        resultMutex.withLock {
                            schools += result
                            successfulExpectedSchoolCount += municipality.schoolCount
                        }
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // A municipality failure is intentionally partial. Healthy coverage
                        // rules below decide whether the durable cache may be replaced.
                    }
                }
            }
        }

        val finished = withTimeoutOrNull(batchTimeoutMillis.coerceAtLeast(1)) {
            jobs.joinAll()
            true
        } ?: false
        if (!finished) {
            jobs.forEach(Job::cancel)
            jobs.joinAll()
        }

        SchoolFetchBatch(
            schools = resultMutex.withLock { schools.toList() },
            expectedSchoolCount = municipalities.sumOf { it.schoolCount },
            successfulExpectedSchoolCount = resultMutex.withLock { successfulExpectedSchoolCount },
        )
    }

    private suspend fun fetchSchoolsWithRetry(municipalityName: String): List<SchoolDirectorySchool> {
        var mostRecentError: Throwable? = null
        repeat(maximumTownRequestAttempts.coerceAtLeast(1)) { attemptIndex ->
            try {
                return client.fetchSchools(municipalityName)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                mostRecentError = error
                if (attemptIndex + 1 < maximumTownRequestAttempts.coerceAtLeast(1)) {
                    retryDelay((attemptIndex + 1) * 250L)
                }
            }
        }
        throw mostRecentError ?: SchoolDirectoryException()
    }

    private fun uniqueSortedSchools(schools: List<SchoolDirectorySchool>): List<SchoolDirectorySchool> {
        val collator = Collator.getInstance(Locale.forLanguageTag("cs-CZ"))
        val seenURLs = mutableSetOf<String>()
        return schools
            .sortedWith { left, right ->
                val townComparison = collator.compare(left.trimmedTown, right.trimmedTown)
                if (townComparison != 0) townComparison else collator.compare(left.trimmedName, right.trimmedName)
            }
            .filter { school -> seenURLs.add(school.trimmedSchoolURL.lowercase(Locale.ROOT)) }
    }

    private data class SchoolFetchBatch(
        val schools: List<SchoolDirectorySchool>,
        val expectedSchoolCount: Int,
        val successfulExpectedSchoolCount: Int,
    ) {
        fun isHealthyForCaching(hasTrustedCache: Boolean): Boolean {
            if (expectedSchoolCount <= 0) return false
            val requestCoverage = successfulExpectedSchoolCount.toDouble() / expectedSchoolCount
            val responseCoverage = schools.size.toDouble() / expectedSchoolCount
            return if (hasTrustedCache) {
                requestCoverage >= 0.90 && responseCoverage >= 0.70
            } else {
                requestCoverage >= 0.98 && responseCoverage >= 0.90
            }
        }
    }

    private fun CachedSchoolDirectory?.orEmpty(): List<SchoolDirectorySchool> = this?.schools.orEmpty()
}
