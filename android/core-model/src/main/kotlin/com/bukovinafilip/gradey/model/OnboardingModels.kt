package com.bukovinafilip.gradey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class OnboardingJourney {
    @SerialName("newUser")
    NEW_USER,

    @SerialName("upgrade")
    UPGRADE,
}

@Serializable
enum class OnboardingStep {
    @SerialName("welcome")
    WELCOME,

    @SerialName("account")
    ACCOUNT,

    @SerialName("school")
    SCHOOL,

    @SerialName("notifications")
    NOTIFICATIONS,

    @SerialName("ready")
    READY,

    @SerialName("support")
    SUPPORT,
}

@Serializable
data class OnboardingProgress(
    val journey: OnboardingJourney,
    val step: OnboardingStep,
) {
    companion object {
        fun initial(journey: OnboardingJourney) = OnboardingProgress(
            journey = journey,
            step = OnboardingStep.WELCOME,
        )
    }
}
