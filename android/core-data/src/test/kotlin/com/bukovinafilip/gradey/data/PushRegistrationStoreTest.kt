package com.bukovinafilip.gradey.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class PushRegistrationStoreTest {
    @Test
    fun `successful identity deduplicates but token account and environment rotation retry`() {
        var stored: String? = null
        val store = PushRegistrationStore({ stored }, { stored = it })

        assertThat(store.needsRegistration("token-a", "account-a", "debug")).isTrue()
        store.markRegistered("token-a", "account-a", "debug")

        assertThat(store.needsRegistration("token-a", "account-a", "debug")).isFalse()
        assertThat(store.needsRegistration("token-b", "account-a", "debug")).isTrue()
        assertThat(store.needsRegistration("token-a", "account-b", "debug")).isTrue()
        assertThat(store.needsRegistration("token-a", "account-a", "production")).isTrue()

        store.clear()
        assertThat(store.needsRegistration("token-a", "account-a", "debug")).isTrue()
        assertThat(stored).isNull()
    }
}
