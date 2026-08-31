package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.StravaCZStoredSession
import kotlinx.coroutines.CancellationException

sealed interface RetainedStravaCloudLinkResult {
    data object NoLocalSession : RetainedStravaCloudLinkResult

    data class Linked(
        val session: StravaCZStoredSession,
    ) : RetainedStravaCloudLinkResult

    data class Failed(
        val session: StravaCZStoredSession,
        val cause: Throwable,
    ) : RetainedStravaCloudLinkResult
}

/**
 * Copies a retained local Strava.cz session to the cloud without owning any API
 * that can replace, refresh, or clear that local session.
 */
suspend fun linkRetainedStravaSession(
    loadSession: suspend () -> StravaCZStoredSession?,
    linkSession: suspend (StravaCZStoredSession) -> Unit,
): RetainedStravaCloudLinkResult {
    val session = loadSession() ?: return RetainedStravaCloudLinkResult.NoLocalSession
    return try {
        linkSession(session)
        RetainedStravaCloudLinkResult.Linked(session)
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        RetainedStravaCloudLinkResult.Failed(session, error)
    }
}
