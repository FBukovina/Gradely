package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class FirebaseGradeyAIErrorMapperTest {
    @Test
    fun `generic Firebase resource exhaustion is a retryable server failure`() {
        val mapped = FirebaseGradeyAIErrorMapper.mapFunctionsFailure(
            firebaseCode = "resource_exhausted",
            details = null,
            fallbackMessage = "Firebase quota exhausted",
        )

        assertThat(mapped.kind).isEqualTo(GradeyAIErrorKind.SERVER)
        assertThat(mapped.retryable).isTrue()
        assertThat(mapped.serverCode).isEqualTo("resource_exhausted")
    }

    @Test
    fun `explicit backend daily limit code remains a nonretryable user limit`() {
        val mapped = FirebaseGradeyAIErrorMapper.mapFunctionsFailure(
            firebaseCode = "resource_exhausted",
            fallbackMessage = "Firebase resource exhausted",
            details = mapOf(
                "code" to "daily_limit",
                "message" to "Daily limit reached",
                "retryable" to false,
            ),
        )

        assertThat(mapped.kind).isEqualTo(GradeyAIErrorKind.LIMIT_REACHED)
        assertThat(mapped.retryable).isFalse()
        assertThat(mapped.serverCode).isEqualTo("daily_limit")
    }
}
