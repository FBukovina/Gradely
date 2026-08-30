package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import java.security.MessageDigest

class CachedGradeyHistoryRepository(
    private val remote: GradeyHistoryRepository,
    private val cache: RoomGradeyCache,
) : GradeyHistoryRepository {
    override suspend fun loadCachedGradeHistory(accountID: String?): GradeHistoryResponse? =
        accountID.cacheScope()?.let { cache.loadGradeHistory(it) }

    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        val response = remote.gradeHistory(accountID, days)
        accountID.cacheScope()?.let { cache.saveGradeHistory(it, response) }
        return response
    }

    override suspend fun clearCachedGradeHistory(accountID: String?) {
        accountID.cacheScope()?.let { cache.clearGradeHistory(it) }
    }

    override suspend fun clearAllCachedGradeHistory() = cache.clearAllGradeHistory()
}

private fun String?.cacheScope(): String? {
    val normalized = this?.trim()?.takeIf(String::isNotEmpty) ?: return null
    return MessageDigest.getInstance("SHA-256")
        .digest(normalized.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
