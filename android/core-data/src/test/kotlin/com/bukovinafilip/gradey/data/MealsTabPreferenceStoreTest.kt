package com.bukovinafilip.gradey.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MealsTabPreferenceStoreTest {
    @Test
    fun `meals tab is visible by default and persists changes`() {
        var persisted = true
        val store = MealsTabPreferenceStore(
            readVisible = { persisted },
            writeVisible = { persisted = it },
        )

        assertThat(store.isVisible).isTrue()

        store.isVisible = false
        assertThat(store.isVisible).isFalse()

        store.isVisible = true
        assertThat(store.isVisible).isTrue()
    }
}
