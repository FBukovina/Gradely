package com.bukovinafilip.gradey.domain

enum class GradeyStartupDestination {
    SIGNED_OUT,
    NEEDS_SCHOOL,
    SIGNED_IN,
}

fun selectGradeyStartupDestination(
    isCloudConfigured: Boolean,
    isGuestMode: Boolean,
    hasGradeySession: Boolean,
    hasSchoolSession: Boolean,
): GradeyStartupDestination = when {
    isCloudConfigured && !isGuestMode && !hasGradeySession -> GradeyStartupDestination.SIGNED_OUT
    !hasSchoolSession -> GradeyStartupDestination.NEEDS_SCHOOL
    else -> GradeyStartupDestination.SIGNED_IN
}
