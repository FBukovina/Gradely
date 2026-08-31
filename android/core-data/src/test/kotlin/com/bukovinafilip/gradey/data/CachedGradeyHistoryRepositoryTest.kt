package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.security.MessageDigest

class CachedGradeyHistoryRepositoryTest {
    @Test
    fun `successful cloud history is scoped per linked account and restored offline`() = runTest {
        val dao = HistoryCacheDao()
        val remote = FakeHistoryRepository(history("fresh-a"))
        val repository = CachedGradeyHistoryRepository(remote, RoomGradeyCache(dao, GradeyJson))

        assertThat(repository.loadCachedGradeHistory("account-a")).isNull()
        assertThat(repository.gradeHistory(" account-a ", 400)).isEqualTo(history("fresh-a"))
        assertThat(repository.loadCachedGradeHistory("account-a")).isEqualTo(history("fresh-a"))
        assertThat(repository.loadCachedGradeHistory("account-b")).isNull()

        remote.failure = java.io.IOException("offline")
        val failure = runCatching { repository.gradeHistory("account-a", 400) }.exceptionOrNull()

        assertThat(failure).isInstanceOf(java.io.IOException::class.java)
        assertThat(repository.loadCachedGradeHistory("account-a")).isEqualTo(history("fresh-a"))
    }

    @Test
    fun `corrupt history is ignored and a fresh response repairs it`() = runTest {
        val dao = HistoryCacheDao()
        val accountID = "account-a"
        dao.save(CacheEntryEntity("grade-history:${scope(accountID)}", "not-json", 1))
        val repository = CachedGradeyHistoryRepository(
            FakeHistoryRepository(history("recovered")),
            RoomGradeyCache(dao, GradeyJson),
        )

        assertThat(repository.loadCachedGradeHistory(accountID)).isNull()

        repository.gradeHistory(accountID, 400)

        assertThat(repository.loadCachedGradeHistory(accountID)).isEqualTo(history("recovered"))
    }

    @Test
    fun `targeted and account reset clearing never leak another account history`() = runTest {
        val repository = CachedGradeyHistoryRepository(
            FakeHistoryRepository(),
            RoomGradeyCache(HistoryCacheDao(), GradeyJson),
        )

        repository.gradeHistory("account-a", 400)
        repository.gradeHistory("account-b", 400)
        repository.clearCachedGradeHistory("account-a")

        assertThat(repository.loadCachedGradeHistory("account-a")).isNull()
        assertThat(repository.loadCachedGradeHistory("account-b")).isNotNull()

        repository.clearAllCachedGradeHistory()

        assertThat(repository.loadCachedGradeHistory("account-b")).isNull()
    }

    @Test
    fun `identity reset rejects a held response before it can repopulate cleared history`() = runTest {
        val remote = HeldHistoryRepository(history("late-a"))
        val repository = CachedGradeyHistoryRepository(
            remote,
            RoomGradeyCache(HistoryCacheDao(), GradeyJson),
        )
        val heldRequest = async { repository.gradeHistory("account-a", 400) }
        remote.requestStarted.await()

        repository.clearAllCachedGradeHistory()
        remote.releaseResponse.complete(Unit)
        val failure = runCatching { heldRequest.await() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(repository.loadCachedGradeHistory("account-a")).isNull()
    }

    private fun history(id: String) = GradeHistoryResponse(
        recentNewMarkEvents = listOf(
            NewMarkEvent(
                id = id,
                linkedAccountID = "account",
                provider = LinkedAccountProvider.BAKALARI,
                subjectID = "math",
                markText = "1",
                createdAt = "2026-08-30T10:00:00Z",
            ),
        ),
    )

    private fun scope(accountID: String): String = MessageDigest.getInstance("SHA-256")
        .digest(accountID.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

private class FakeHistoryRepository(
    private var response: GradeHistoryResponse = GradeHistoryResponse(),
) : GradeyHistoryRepository {
    var failure: Throwable? = null

    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        failure?.let { throw it }
        return response
    }
}

private class HeldHistoryRepository(
    private val response: GradeHistoryResponse,
) : GradeyHistoryRepository {
    val requestStarted = CompletableDeferred<Unit>()
    val releaseResponse = CompletableDeferred<Unit>()

    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        requestStarted.complete(Unit)
        releaseResponse.await()
        return response
    }
}

private class HistoryCacheDao : CacheEntryDao {
    private val entries = mutableMapOf<String, CacheEntryEntity>()

    override suspend fun load(key: String) = entries[key]
    override suspend fun save(entity: CacheEntryEntity) { entries[entity.key] = entity }
    override suspend fun clear(key: String) { entries.remove(key) }
    override suspend fun clearPrefix(prefix: String) {
        entries.keys.filter { it.startsWith(prefix) }.forEach(entries::remove)
    }
    override suspend fun clearAll() { entries.clear() }
}
