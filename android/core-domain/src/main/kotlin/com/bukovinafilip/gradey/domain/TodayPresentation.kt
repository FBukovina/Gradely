package com.bukovinafilip.gradey.domain

enum class TodayPresentationState {
    INITIAL_LOADING,
    LOADED,
    EMPTY,
    REFRESHING,
    BACKGROUND_ERROR,
    FIRST_LOAD_ERROR,
}

object TodayPresentationStates {
    fun resolve(
        hasDashboard: Boolean,
        hasSubjects: Boolean,
        isLoading: Boolean,
        hasError: Boolean,
    ): TodayPresentationState = when {
        !hasDashboard && isLoading -> TodayPresentationState.INITIAL_LOADING
        !hasDashboard -> TodayPresentationState.FIRST_LOAD_ERROR
        isLoading -> TodayPresentationState.REFRESHING
        hasError -> TodayPresentationState.BACKGROUND_ERROR
        !hasSubjects -> TodayPresentationState.EMPTY
        else -> TodayPresentationState.LOADED
    }
}
