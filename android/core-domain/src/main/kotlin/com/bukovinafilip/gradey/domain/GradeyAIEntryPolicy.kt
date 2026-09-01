package com.bukovinafilip.gradey.domain

enum class GradeyAIEntryState {
    SIGN_IN_REQUIRED,
    NOT_CONFIGURED,
    SERVICE,
}

object GradeyAIEntryPolicy {
    fun resolve(
        isServiceConfigured: Boolean,
        isGradeyCloudConfigured: Boolean,
        hasGradeyAccount: Boolean,
        isGuestMode: Boolean,
    ): GradeyAIEntryState = when {
        !isServiceConfigured || !isGradeyCloudConfigured -> GradeyAIEntryState.NOT_CONFIGURED
        isGuestMode || !hasGradeyAccount -> GradeyAIEntryState.SIGN_IN_REQUIRED
        else -> GradeyAIEntryState.SERVICE
    }
}
