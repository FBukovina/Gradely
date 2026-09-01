package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.AppLanguage
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AppLanguageStoreTest {
    @Test
    fun `selection uses the cross-platform key values and persists changes`() {
        var persisted: String? = null
        val store = AppLanguageStore(
            readValue = { persisted },
            writeValue = { persisted = it },
        )

        assertThat(store.selection).isEqualTo(AppLanguage.SYSTEM)

        store.selection = AppLanguage.CZECH_CHRONICALLY_ONLINE

        assertThat(persisted).isEqualTo("czechChronicallyOnline")
        assertThat(store.selection).isEqualTo(AppLanguage.CZECH_CHRONICALLY_ONLINE)
    }
}
