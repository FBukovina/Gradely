package com.bukovinafilip.gradey

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

class StravaDisconnectPolicyTest {
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `held cloud unlink starts after durable and visible local teardown without blocking`() = runTest {
        val events = mutableListOf<String>()
        val cloudStarted = CompletableDeferred<Unit>()
        val releaseCloud = CompletableDeferred<Unit>()
        var durableSessionPresent = true
        var visibleSessionPresent = true
        lateinit var cloudCleanup: Job

        completeLocalStravaDisconnectBeforeRemoteCleanup(
            takeLocalSessionForSignOut = {
                events += "local-clear"
                durableSessionPresent = false
                null
            },
            clearVisibleState = {
                events += "visible-clear"
                assertThat(durableSessionPresent).isFalse()
                visibleSessionPresent = false
            },
            captureGradeySessionForCleanup = {
                events += "capture-cloud-owner"
                assertThat(durableSessionPresent).isFalse()
                assertThat(visibleSessionPresent).isFalse()
                null
            },
            launchRemoteCleanup = { _, _ ->
                events += "launch-cloud-unlink"
                assertThat(durableSessionPresent).isFalse()
                assertThat(visibleSessionPresent).isFalse()
                cloudCleanup = backgroundScope.launch {
                    cloudStarted.complete(Unit)
                    releaseCloud.await()
                }
            },
        )

        runCurrent()
        assertThat(events).containsExactly(
            "local-clear",
            "visible-clear",
            "capture-cloud-owner",
            "launch-cloud-unlink",
        ).inOrder()
        assertThat(cloudStarted.isCompleted).isTrue()
        assertThat(cloudCleanup.isCompleted).isFalse()
        assertThat(durableSessionPresent).isFalse()
        assertThat(visibleSessionPresent).isFalse()

        releaseCloud.complete(Unit)
        cloudCleanup.join()
    }
}
