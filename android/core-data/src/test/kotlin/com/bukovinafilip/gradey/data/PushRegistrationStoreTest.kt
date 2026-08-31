package com.bukovinafilip.gradey.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class PushRegistrationStoreTest {
    @Test
    fun `successful identity deduplicates but token account and environment rotation retry`() {
        var stored: String? = null
        val store = PushRegistrationStore({ stored }, { stored = it })

        assertThat(store.needsRegistration("token-a", "account-a", "sandbox")).isTrue()
        store.markRegistered("token-a", "account-a", "sandbox")

        assertThat(store.needsRegistration("token-a", "account-a", "sandbox")).isFalse()
        assertThat(store.needsRegistration("token-b", "account-a", "sandbox")).isTrue()
        assertThat(store.needsRegistration("token-a", "account-b", "sandbox")).isTrue()
        assertThat(store.needsRegistration("token-a", "account-a", "production")).isTrue()

        store.clear()
        assertThat(store.needsRegistration("token-a", "account-a", "sandbox")).isTrue()
        assertThat(store.needsRegistration("fresh-token", "account-b", "sandbox")).isTrue()
        assertThat(stored).isNull()
    }
}
