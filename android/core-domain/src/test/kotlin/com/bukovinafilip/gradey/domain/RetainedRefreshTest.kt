package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RetainedRefreshTest {
    @Test
    fun `successful refresh replaces cached content`() = runTest {
        val result = refreshRetainingContent(current = "cached") { "fresh" }

        assertThat(result.value).isEqualTo("fresh")
        assertThat(result.failure).isNull()
    }

    @Test
    fun `failed refresh retains cached content and reports its failure`() = runTest {
        val failure = IllegalStateException("offline")

        val result = refreshRetainingContent(current = "cached") { throw failure }

        assertThat(result.value).isEqualTo("cached")
        assertThat(result.failure).isSameInstanceAs(failure)
    }

    @Test
    fun `mixed source failures cannot erase independently refreshed content`() = runTest {
        val timetable = refreshRetainingContent(current = "cached timetable") { "fresh timetable" }
        val absence = refreshRetainingContent(current = "cached absence") {
            throw IllegalStateException("absence unavailable")
        }
        val meals = refreshRetainingContent(current = "cached meal") { "fresh meal" }
        val history = refreshRetainingContent(current = "cached history") {
            throw IllegalStateException("history unavailable")
        }
        val accounts = refreshRetainingContent(current = "cached accounts") {
            throw IllegalStateException("accounts unavailable")
        }

        assertThat(timetable.value).isEqualTo("fresh timetable")
        assertThat(absence.value).isEqualTo("cached absence")
        assertThat(meals.value).isEqualTo("fresh meal")
        assertThat(history.value).isEqualTo("cached history")
        assertThat(accounts.value).isEqualTo("cached accounts")
    }

    @Test(expected = CancellationException::class)
    fun `cancellation is never converted into retained content`() = runTest {
        refreshRetainingContent(current = "cached") { throw CancellationException("stop") }
    }
}
