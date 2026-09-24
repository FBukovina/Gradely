package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AbsencePresentationStatesTest {
    @Test
    fun `first request without cached response is loading`() {
        assertThat(resolve(hasResponse = false, isLoading = true))
            .isEqualTo(AbsencePresentationState.INITIAL_LOADING)
    }

    @Test
    fun `missing response after failure receives full retry`() {
        assertThat(resolve(hasResponse = false, hasError = true))
            .isEqualTo(AbsencePresentationState.FIRST_LOAD_ERROR)
    }

    @Test
    fun `missing response without a server message still receives retry`() {
        assertThat(resolve(hasResponse = false))
            .isEqualTo(AbsencePresentationState.FIRST_LOAD_ERROR)
    }

    @Test
    fun `loaded response without day or subject records is empty`() {
        assertThat(resolve(hasResponse = true, hasRecords = false))
            .isEqualTo(AbsencePresentationState.EMPTY)
    }

    @Test
    fun `response with records is loaded`() {
        assertThat(resolve(hasResponse = true, hasRecords = true))
            .isEqualTo(AbsencePresentationState.LOADED)
    }

    @Test
    fun `refresh retains response and wins over an earlier error`() {
        assertThat(resolve(hasResponse = true, hasRecords = true, isLoading = true, hasError = true))
            .isEqualTo(AbsencePresentationState.REFRESHING)
    }

    @Test
    fun `refresh failure with retained response is non destructive`() {
        assertThat(resolve(hasResponse = true, hasRecords = true, hasError = true))
            .isEqualTo(AbsencePresentationState.BACKGROUND_ERROR)
    }

    private fun resolve(
        hasResponse: Boolean,
        hasRecords: Boolean = false,
        isLoading: Boolean = false,
        hasError: Boolean = false,
    ) = AbsencePresentationStates.resolve(
        hasResponse = hasResponse,
        hasRecords = hasRecords,
        isLoading = isLoading,
        hasError = hasError,
    )
}
