package com.bukovinafilip.gradey.feature.account

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyDebugModeStoreTest {
    @Test
    fun `seventh version tap persistently unlocks debug mode`() {
        var persisted = false
        val store = GradeyDebugModeStore(
            readEnabled = { persisted },
            writeEnabled = { persisted = it },
        )
        var tapCount = 0

        repeat(6) {
            val result = store.registerVersionTap(tapCount)
            tapCount = result.tapCount
            assertThat(result.unlocked).isFalse()
            assertThat(persisted).isFalse()
        }

        val result = store.registerVersionTap(tapCount)

        assertThat(result.unlocked).isTrue()
        assertThat(result.tapCount).isEqualTo(0)
        assertThat(persisted).isTrue()
        assertThat(store.isEnabled).isTrue()
    }

    @Test
    fun `disabling debug mode persists`() {
        var persisted = true
        val store = GradeyDebugModeStore(
            readEnabled = { persisted },
            writeEnabled = { persisted = it },
        )

        store.isEnabled = false

        assertThat(persisted).isFalse()
        assertThat(store.isEnabled).isFalse()
    }
}
