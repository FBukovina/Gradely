package com.bukovinafilip.gradey.domain

import kotlinx.coroutines.CancellationException

suspend fun <T> loadCacheFirst(
    loadCached: suspend () -> T?,
    loadFresh: suspend () -> T,
    onCached: (T?) -> Unit,
    onFresh: suspend (T) -> Unit,
): Throwable? {
    val cached = try {
        loadCached()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        null
    }
    onCached(cached)

    return try {
        onFresh(loadFresh())
        null
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        error
    }
}
