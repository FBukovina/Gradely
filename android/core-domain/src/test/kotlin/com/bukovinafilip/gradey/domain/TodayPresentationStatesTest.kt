package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class TodayPresentationStatesTest {
    @Test
    fun `initial request without content is loading`() {
        assertThat(resolve(hasDashboard = false, isLoading = true))
            .isEqualTo(TodayPresentationState.INITIAL_LOADING)
    }

    @Test
    fun `missing content after request receives full retry state`() {
        assertThat(resolve(hasDashboard = false, hasError = true))
            .isEqualTo(TodayPresentationState.FIRST_LOAD_ERROR)
    }

    @Test
    fun `missing content without a server message still receives retry state`() {
        assertThat(resolve(hasDashboard = false))
            .isEqualTo(TodayPresentationState.FIRST_LOAD_ERROR)
    }

    @Test
    fun `loaded dashboard with no subjects is an honest empty state`() {
        assertThat(resolve(hasDashboard = true, hasSubjects = false))
            .isEqualTo(TodayPresentationState.EMPTY)
    }

    @Test
    fun `dashboard with subjects is loaded`() {
        assertThat(resolve(hasDashboard = true, hasSubjects = true))
            .isEqualTo(TodayPresentationState.LOADED)
    }

    @Test
    fun `refresh retains content and wins over an earlier error`() {
        assertThat(resolve(hasDashboard = true, hasSubjects = true, isLoading = true, hasError = true))
            .isEqualTo(TodayPresentationState.REFRESHING)
    }

    @Test
    fun `refresh failure with retained content is non destructive`() {
        assertThat(resolve(hasDashboard = true, hasSubjects = true, hasError = true))
            .isEqualTo(TodayPresentationState.BACKGROUND_ERROR)
    }

    private fun resolve(
        hasDashboard: Boolean,
        hasSubjects: Boolean = false,
        isLoading: Boolean = false,
        hasError: Boolean = false,
    ) = TodayPresentationStates.resolve(
        hasDashboard = hasDashboard,
        hasSubjects = hasSubjects,
        isLoading = isLoading,
        hasError = hasError,
    )
}
