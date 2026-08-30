package com.bukovinafilip.gradey.domain

enum class GradeyAIEntryState {
    SIGN_IN_REQUIRED,
    NOT_CONFIGURED,
    SERVICE,
}

object GradeyAIEntryPolicy {
    fun resolve(isGuestMode: Boolean, isConfigured: Boolean): GradeyAIEntryState = when {
        isGuestMode -> GradeyAIEntryState.SIGN_IN_REQUIRED
        !isConfigured -> GradeyAIEntryState.NOT_CONFIGURED
        else -> GradeyAIEntryState.SERVICE
    }
}
