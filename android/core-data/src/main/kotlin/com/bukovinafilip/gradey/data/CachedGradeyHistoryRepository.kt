package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import java.security.MessageDigest
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class CachedGradeyHistoryRepository(
    private val remote: GradeyHistoryRepository,
    private val cache: RoomGradeyCache,
) : GradeyHistoryRepository {
    private val cacheMutationMutex = Mutex()
    private var cacheEpoch = 0L

    override suspend fun loadCachedGradeHistory(accountID: String?): GradeHistoryResponse? =
        cacheMutationMutex.withLock {
            accountID.cacheScope()?.let { cache.loadGradeHistory(it) }
        }

    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        val requestEpoch = cacheMutationMutex.withLock { cacheEpoch }
        val response = remote.gradeHistory(accountID, days)
        cacheMutationMutex.withLock {
            if (requestEpoch != cacheEpoch) throw GradeyIdentityChangedException()
            accountID.cacheScope()?.let { cache.saveGradeHistory(it, response) }
        }
        return response
    }

    override suspend fun clearCachedGradeHistory(accountID: String?) {
        cacheMutationMutex.withLock {
            invalidatePendingWrites()
            accountID.cacheScope()?.let { cache.clearGradeHistory(it) }
        }
    }

    override suspend fun clearAllCachedGradeHistory() {
        cacheMutationMutex.withLock {
            invalidatePendingWrites()
            cache.clearAllGradeHistory()
        }
    }

    private fun invalidatePendingWrites() {
        cacheEpoch = if (cacheEpoch == Long.MAX_VALUE) Long.MIN_VALUE else cacheEpoch + 1L
    }
}

private fun String?.cacheScope(): String? {
    val normalized = this?.trim()?.takeIf(String::isNotEmpty) ?: return null
    return MessageDigest.getInstance("SHA-256")
        .digest(normalized.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
