package com.bukovinafilip.gradey.data

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class FirebaseGradeyAIIdentityCoordinatorTest {
    @Test
    fun `identity work is serialized across concurrent callable requests`() = runTest {
        val coordinator = FirebaseGradeyAIIdentityCoordinator()
        val firstEntered = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        var active = 0
        var maximumActive = 0
        var secondEntered = false

        val first = async {
            coordinator.serialized {
                active += 1
                maximumActive = maxOf(maximumActive, active)
                firstEntered.complete(Unit)
                releaseFirst.await()
                active -= 1
            }
        }
        firstEntered.await()
        val second = async {
            coordinator.serialized {
                secondEntered = true
                active += 1
                maximumActive = maxOf(maximumActive, active)
                active -= 1
            }
        }
        runCurrent()

        assertThat(secondEntered).isFalse()
        assertThat(maximumActive).isEqualTo(1)

        releaseFirst.complete(Unit)
        awaitAll(first, second)

        assertThat(secondEntered).isTrue()
        assertThat(maximumActive).isEqualTo(1)
    }
}
