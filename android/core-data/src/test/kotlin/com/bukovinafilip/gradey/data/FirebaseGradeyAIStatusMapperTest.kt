package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.GradeyAIIdentityTier
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class FirebaseGradeyAIStatusMapperTest {
    @Test
    fun `decodes camel case firebase status values`() {
        val status = FirebaseGradeyAIStatusMapper.decode(
            mapOf(
                "enabled" to true,
                "consentRequired" to false,
                "termsVersion" to "2026-08",
                "dailyLimit" to 10L,
                "dailyUsed" to 3L,
                "remaining" to 7L,
                "resetAt" to 1_777_777_777_000.0,
                "tier" to "linked",
            ),
        )

        assertThat(status.enabled).isTrue()
        assertThat(status.consentRequired).isFalse()
        assertThat(status.termsVersion).isEqualTo("2026-08")
        assertThat(status.dailyLimit).isEqualTo(10)
        assertThat(status.dailyUsed).isEqualTo(3)
        assertThat(status.remaining).isEqualTo(7)
        assertThat(status.resetAtEpochMillis).isEqualTo(1_777_777_777_000L)
        assertThat(status.tier).isEqualTo(GradeyAIIdentityTier.LINKED)
        assertThat(status.canSend).isTrue()
    }

    @Test
    fun `decodes snake case and flexible scalar values`() {
        val status = FirebaseGradeyAIStatusMapper.decode(
            mapOf(
                "enabled" to "true",
                "consent_required" to 1,
                "terms_version" to 4,
                "daily_limit" to "5.0",
                "daily_used" to "2",
                "reset_at" to "1777777777000",
                "tier" to "unknown",
            ),
        )

        assertThat(status.enabled).isTrue()
        assertThat(status.consentRequired).isTrue()
        assertThat(status.termsVersion).isEqualTo("4")
        assertThat(status.dailyLimit).isEqualTo(5)
        assertThat(status.dailyUsed).isEqualTo(2)
        assertThat(status.remaining).isEqualTo(3)
        assertThat(status.resetAtEpochMillis).isEqualTo(1_777_777_777_000L)
        assertThat(status.tier).isEqualTo(GradeyAIIdentityTier.ANONYMOUS)
        assertThat(status.canSend).isFalse()
    }

    @Test(expected = IllegalStateException::class)
    fun `rejects non object status payload`() {
        FirebaseGradeyAIStatusMapper.decode("invalid")
    }
}
