package com.bukovinafilip.gradey.wear

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneWearSyncPublisherTest {
    @Test
    fun firstPublicationUsesRequestedWallClockGeneration() {
        assertThat(nextWearPayloadGeneration(previous = null, requested = 100)).isEqualTo(100)
    }

    @Test
    fun equalAndRolledBackClockStillAdvanceGeneration() {
        assertThat(nextWearPayloadGeneration(previous = 100, requested = 100)).isEqualTo(101)
        assertThat(nextWearPayloadGeneration(previous = 101, requested = 50)).isEqualTo(102)
    }

    @Test
    fun processRestartSeedAndOverflowRemainMonotonic() {
        assertThat(nextWearPayloadGeneration(previous = 500, requested = 300)).isEqualTo(501)
        assertThat(nextWearPayloadGeneration(previous = Long.MAX_VALUE, requested = 300))
            .isEqualTo(Long.MAX_VALUE)
    }

    @Test
    fun coordinatorKeepsTheWholePublishInGenerationOrder() = runTest {
        val coordinator = WearPublishCoordinator()
        val firstEntered = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val order = mutableListOf<String>()

        val first = async {
            coordinator.run {
                order += "first-start"
                firstEntered.complete(Unit)
                releaseFirst.await()
                order += "first-end"
            }
        }
        firstEntered.await()
        val second = async {
            coordinator.run { order += "second" }
        }

        runCurrent()
        assertThat(order).containsExactly("first-start").inOrder()

        releaseFirst.complete(Unit)
        first.await()
        second.await()

        assertThat(order).containsExactly("first-start", "first-end", "second").inOrder()
    }

    @Test
    fun coordinatorRejectsAQueuedSignedInPublishAfterSessionInvalidation() = runTest {
        val coordinator = WearPublishCoordinator()
        val signedOutStarted = CompletableDeferred<Unit>()
        val releaseSignedOut = CompletableDeferred<Unit>()
        var sessionIsCurrent = true
        var staleSignedInPublished = false

        val signedOut = async {
            coordinator.run {
                sessionIsCurrent = false
                signedOutStarted.complete(Unit)
                releaseSignedOut.await()
            }
        }
        signedOutStarted.await()
        val staleSignedIn = async {
            coordinator.runIf(
                isStillCurrent = { sessionIsCurrent },
                block = { staleSignedInPublished = true },
            )
        }

        runCurrent()
        releaseSignedOut.complete(Unit)
        signedOut.await()

        assertThat(staleSignedIn.await()).isFalse()
        assertThat(staleSignedInPublished).isFalse()
    }
}
