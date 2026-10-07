package com.bukovinafilip.gradey.push

import com.google.common.truth.Truth.assertThat
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class GradeyPushRegistrationTest {
    @Test
    fun `debug and release builds use backend supported push environments`() {
        assertThat(pushEnvironment(isDebugBuild = true)).isEqualTo("sandbox")
        assertThat(pushEnvironment(isDebugBuild = false)).isEqualTo("production")
    }

    @Test
    fun `sign out token invalidation is best effort for provider failures`() = runTest {
        assertThat(invalidatePushToken { throw IOException("FCM unavailable") }).isFalse()
    }

    @Test
    fun `sign out token invalidation preserves coroutine cancellation`() = runTest {
        val failure = runCatching {
            invalidatePushToken { throw CancellationException("cancelled") }
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(CancellationException::class.java)
    }

    @Test
    fun `sign out token invalidation reports a completed deletion`() = runTest {
        var deleted = false

        assertThat(invalidatePushToken { deleted = true }).isTrue()
        assertThat(deleted).isTrue()
    }
}
