package com.bukovinafilip.gradey

internal enum class RestoredSchoolDestination {
    NONE,
    ADD_SCHOOL,
    RECONNECT_SCHOOL,
}

internal data class RestoredSchoolRoute(
    val destination: RestoredSchoolDestination,
    val reconnectAccountID: String? = null,
)

internal enum class SchoolLoginBackAction {
    NONE,
    RETURN_TO_ACCOUNT,
    SIGN_OUT_GRADEY_ID,
}

/**
 * Keeps account-management school routes dismissible without allowing the mandatory school gate
 * to trap a signed-in Gradey ID. Local/guest school login remains a root destination.
 */
internal fun schoolLoginBackAction(
    hasGradeyAccount: Boolean,
    isGuestMode: Boolean,
    isAddingSchool: Boolean,
    isReconnectingSchool: Boolean,
): SchoolLoginBackAction = when {
    isAddingSchool || isReconnectingSchool -> SchoolLoginBackAction.RETURN_TO_ACCOUNT
    hasGradeyAccount && !isGuestMode -> SchoolLoginBackAction.SIGN_OUT_GRADEY_ID
    else -> SchoolLoginBackAction.NONE
}

/**
 * Restores an account-management school route only while the original signed-in school session
 * still exists. Without that session, the normal startup login/recovery route remains authoritative
 * and must not expose a Back action into an unusable signed-in screen.
 */
internal fun restoreSchoolRoute(
    isAddingSchool: Boolean,
    reconnectAccountID: String?,
    hasSchoolSession: Boolean,
    availableLinkedAccountIDs: Set<String>,
): RestoredSchoolRoute {
    if (!hasSchoolSession) return RestoredSchoolRoute(RestoredSchoolDestination.NONE)

    val normalizedReconnectID = reconnectAccountID?.trim()?.takeIf(String::isNotEmpty)
    if (normalizedReconnectID != null && normalizedReconnectID in availableLinkedAccountIDs) {
        return RestoredSchoolRoute(
            destination = RestoredSchoolDestination.RECONNECT_SCHOOL,
            reconnectAccountID = normalizedReconnectID,
        )
    }
    if (isAddingSchool) return RestoredSchoolRoute(RestoredSchoolDestination.ADD_SCHOOL)
    return RestoredSchoolRoute(RestoredSchoolDestination.NONE)
}
