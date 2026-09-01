package com.bukovinafilip.gradey.domain

import kotlinx.coroutines.CancellationException

data class RetainedRefresh<out T>(
    val value: T,
    val failure: Throwable? = null,
)

suspend fun <T> refreshRetainingContent(
    current: T,
    loadFresh: suspend () -> T,
): RetainedRefresh<T> = try {
    RetainedRefresh(value = loadFresh())
} catch (error: CancellationException) {
    throw error
} catch (error: Throwable) {
    RetainedRefresh(value = current, failure = error)
}
