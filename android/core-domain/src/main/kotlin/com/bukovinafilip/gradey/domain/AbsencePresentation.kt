package com.bukovinafilip.gradey.domain

enum class AbsencePresentationState {
    INITIAL_LOADING,
    LOADED,
    EMPTY,
    REFRESHING,
    BACKGROUND_ERROR,
    FIRST_LOAD_ERROR,
}

object AbsencePresentationStates {
    fun resolve(
        hasResponse: Boolean,
        hasRecords: Boolean,
        isLoading: Boolean,
        hasError: Boolean,
    ): AbsencePresentationState = when {
        !hasResponse && isLoading -> AbsencePresentationState.INITIAL_LOADING
        !hasResponse -> AbsencePresentationState.FIRST_LOAD_ERROR
        isLoading -> AbsencePresentationState.REFRESHING
        hasError -> AbsencePresentationState.BACKGROUND_ERROR
        !hasRecords -> AbsencePresentationState.EMPTY
        else -> AbsencePresentationState.LOADED
    }
}
