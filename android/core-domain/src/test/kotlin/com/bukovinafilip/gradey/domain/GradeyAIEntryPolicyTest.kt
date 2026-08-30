package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyAIEntryPolicyTest {
    @Test
    fun `guest mode requires Gradey ID even when firebase is configured`() {
        val state = GradeyAIEntryPolicy.resolve(isGuestMode = true, isConfigured = true)

        assertThat(state).isEqualTo(GradeyAIEntryState.SIGN_IN_REQUIRED)
    }

    @Test
    fun `signed in build without firebase reports configuration state`() {
        val state = GradeyAIEntryPolicy.resolve(isGuestMode = false, isConfigured = false)

        assertThat(state).isEqualTo(GradeyAIEntryState.NOT_CONFIGURED)
    }

    @Test
    fun `signed in configured build loads live service`() {
        val state = GradeyAIEntryPolicy.resolve(isGuestMode = false, isConfigured = true)

        assertThat(state).isEqualTo(GradeyAIEntryState.SERVICE)
    }
}
