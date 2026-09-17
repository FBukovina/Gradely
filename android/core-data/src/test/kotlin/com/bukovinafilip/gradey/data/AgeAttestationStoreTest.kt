package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AgeAttestationStoreTest {
    @Test
    fun `confirmation persists and restores the selected category`() {
        var persisted: String? = null
        val store = AgeAttestationStore(
            readValue = { persisted },
            writeValue = { persisted = it },
        )

        assertThat(store.kind).isNull()
        assertThat(store.allowsAppUse).isFalse()

        store.confirm(AgeAttestationKind.UNDER_THIRTEEN)

        assertThat(persisted).isEqualTo("underThirteen")
        assertThat(store.kind).isEqualTo(AgeAttestationKind.UNDER_THIRTEEN)
        assertThat(store.allowsAppUse).isTrue()
    }

    @Test
    fun `unknown stored category requires attestation again`() {
        val store = AgeAttestationStore(
            readValue = { "new-unknown-category" },
            writeValue = {},
        )

        assertThat(store.kind).isNull()
        assertThat(store.allowsAppUse).isFalse()
    }
}
