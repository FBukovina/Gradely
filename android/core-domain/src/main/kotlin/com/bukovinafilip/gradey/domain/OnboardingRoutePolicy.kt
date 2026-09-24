package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep

fun reconcileOnboardingProgress(
    progress: OnboardingProgress,
    isGuestMode: Boolean,
    hasGradeySession: Boolean,
    hasSchoolSession: Boolean,
    isSchoolCloudLinked: Boolean = true,
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
                !isSchoolCloudLinked -> OnboardingStep.READY
                else -> OnboardingStep.NOTIFICATIONS
            }
            OnboardingStep.SCHOOL -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                isGuestMode -> OnboardingStep.READY
                !isSchoolCloudLinked -> OnboardingStep.READY
                else -> OnboardingStep.NOTIFICATIONS
            }
            OnboardingStep.NOTIFICATIONS -> when {
                !hasAccountChoice -> OnboardingStep.ACCOUNT
                !hasSchoolSession -> OnboardingStep.SCHOOL
                isGuestMode -> OnboardingStep.READY
                !isSchoolCloudLinked -> OnboardingStep.READY
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

fun shouldShowOnboardingSchoolCloudLinkWarning(
    progress: OnboardingProgress?,
    isGuestMode: Boolean,
    hasGradeySession: Boolean,
    hasSchoolSession: Boolean,
    isSchoolCloudLinked: Boolean,
): Boolean =
    progress?.journey == OnboardingJourney.NEW_USER &&
        progress.step == OnboardingStep.READY &&
        !isGuestMode &&
        hasGradeySession &&
        hasSchoolSession &&
        !isSchoolCloudLinked

fun isCurrentSchoolCloudLinked(
    linkedAccountID: String?,
    refreshedAccounts: List<LinkedSchoolAccount>?,
): Boolean {
    if (linkedAccountID.isNullOrBlank()) return false
    return refreshedAccounts?.any { account ->
        account.id == linkedAccountID &&
            account.provider.isSupportedSchoolProvider &&
            account.status == LinkedAccountStatus.ACTIVE
    } ?: true
}

fun canFinishUpgradeOnboarding(
    isGuestMode: Boolean,
    hasGradeySession: Boolean,
    hasRecordedSchoolMigration: Boolean,
    hasRecordedMealsMigration: Boolean,
    isWorking: Boolean,
): Boolean {
    if (isWorking) return false
    val hasCompleteGradeyMigration =
        hasGradeySession &&
            hasRecordedSchoolMigration &&
            hasRecordedMealsMigration
    return isGuestMode || hasCompleteGradeyMigration
}
