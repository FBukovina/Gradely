package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep

fun reconcileOnboardingProgress(
    progress: OnboardingProgress,
    isGuestMode: Boolean,
    hasGradeySession: Boolean,
    hasSchoolSession: Boolean,
): OnboardingProgress {
    val hasAccountChoice = isGuestMode || hasGradeySession
    val step = when (progress.journey) {
        OnboardingJourney.UPGRADE -> when (progress.step) {
            OnboardingStep.WELCOME -> OnboardingStep.WELCOME
            OnboardingStep.ACCOUNT -> if (hasAccountChoice) OnboardingStep.SUPPORT else OnboardingStep.ACCOUNT
            OnboardingStep.SUPPORT -> OnboardingStep.SUPPORT
            else -> if (hasAccountChoice) OnboardingStep.SUPPORT else OnboardingStep.ACCOUNT
        }

        OnboardingJourney.NEW_USER -> when (progress.step) {
            OnboardingStep.WELCOME -> OnboardingStep.WELCOME
            OnboardingStep.ACCOUNT -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                isGuestMode -> OnboardingStep.READY
                else -> OnboardingStep.NOTIFICATIONS
            }
            OnboardingStep.SCHOOL -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                isGuestMode -> OnboardingStep.READY
                else -> OnboardingStep.NOTIFICATIONS
            }
            OnboardingStep.NOTIFICATIONS -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                isGuestMode -> OnboardingStep.READY
                else -> OnboardingStep.NOTIFICATIONS
            }
            OnboardingStep.READY -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                else -> OnboardingStep.READY
            }
            OnboardingStep.SUPPORT -> OnboardingStep.ACCOUNT
        }
    }
    return progress.copy(step = step)
}
