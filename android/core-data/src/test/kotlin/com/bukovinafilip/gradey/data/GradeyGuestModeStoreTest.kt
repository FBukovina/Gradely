package com.bukovinafilip.gradey.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyGuestModeStoreTest {
    @Test
    fun `guest choice is read from and written to persistent preference`() {
        var persisted = false
        val store = GradeyGuestModeStore(
            readEnabled = { persisted },
            writeEnabled = { persisted = it },
        )

        assertThat(store.isEnabled).isFalse()

        store.isEnabled = true
        assertThat(persisted).isTrue()
        assertThat(store.isEnabled).isTrue()

        store.isEnabled = false
        assertThat(persisted).isFalse()
        assertThat(store.isEnabled).isFalse()
    }
}
