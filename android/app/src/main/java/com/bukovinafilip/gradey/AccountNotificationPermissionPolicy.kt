package com.bukovinafilip.gradey

internal enum class AccountNotificationPermissionRecoveryAction {
    REQUEST_RUNTIME_PERMISSION,
    OPEN_APP_NOTIFICATION_SETTINGS,
}

internal fun accountNotificationPermissionRecoveryAction(
    sdkInt: Int,
): AccountNotificationPermissionRecoveryAction =
    if (sdkInt >= 33) {
        AccountNotificationPermissionRecoveryAction.REQUEST_RUNTIME_PERMISSION
    } else {
        AccountNotificationPermissionRecoveryAction.OPEN_APP_NOTIFICATION_SETTINGS
    }

internal enum class PendingAccountNotificationPermissionAction {
    NONE,
    WAIT_FOR_IDENTITY_RESTORE,
    DISCARD,
    PERSIST_ENABLED,
    PERSIST_DISABLED,
}

internal fun pendingAccountNotificationPermissionAction(
    pendingAccountID: String?,
    pendingGeneration: Long?,
    permissionGranted: Boolean?,
    currentAccountID: String?,
    currentGeneration: Long,
    currentGuestMode: Boolean,
    isIdentityRestoring: Boolean,
): PendingAccountNotificationPermissionAction {
    if (pendingAccountID == null || pendingGeneration == null || permissionGranted == null) {
        return PendingAccountNotificationPermissionAction.NONE
    }
    if (isIdentityRestoring) {
        return PendingAccountNotificationPermissionAction.WAIT_FOR_IDENTITY_RESTORE
    }
    val ownerIsCurrent =
        !currentGuestMode &&
            pendingAccountID == currentAccountID &&
            pendingGeneration == currentGeneration
    if (ownerIsCurrent) {
        return if (permissionGranted) {
            PendingAccountNotificationPermissionAction.PERSIST_ENABLED
        } else {
            PendingAccountNotificationPermissionAction.PERSIST_DISABLED
        }
    }
    return PendingAccountNotificationPermissionAction.DISCARD
}
