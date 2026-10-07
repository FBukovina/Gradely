package com.bukovinafilip.gradey

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AccountNotificationPermissionPolicyTest {
    @Test
    fun androidThirteenAndNewerRequestsRuntimePermission() {
        assertThat(accountNotificationPermissionRecoveryAction(32))
            .isEqualTo(AccountNotificationPermissionRecoveryAction.OPEN_APP_NOTIFICATION_SETTINGS)
        assertThat(accountNotificationPermissionRecoveryAction(33))
            .isEqualTo(AccountNotificationPermissionRecoveryAction.REQUEST_RUNTIME_PERMISSION)
        assertThat(accountNotificationPermissionRecoveryAction(37))
            .isEqualTo(AccountNotificationPermissionRecoveryAction.REQUEST_RUNTIME_PERMISSION)
    }

    @Test
    fun restoredMatchingOwnerPersistsTheAuthoritativePermissionResult() {
        assertThat(
            resolve(
                permissionGranted = true,
                currentAccountID = AccountA,
                currentGeneration = Generation,
                isIdentityRestoring = false,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.PERSIST_ENABLED)
        assertThat(
            resolve(
                permissionGranted = false,
                currentAccountID = AccountA,
                currentGeneration = Generation,
                isIdentityRestoring = false,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.PERSIST_DISABLED)
    }

    @Test
    fun resultWaitsDuringBootstrapThenDiscardsForAReplacementIdentity() {
        assertThat(
            resolve(
                permissionGranted = true,
                currentAccountID = AccountA,
                currentGeneration = Generation,
                isIdentityRestoring = true,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.WAIT_FOR_IDENTITY_RESTORE)
        assertThat(
            resolve(
                permissionGranted = true,
                currentAccountID = null,
                currentGeneration = Generation,
                isIdentityRestoring = true,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.WAIT_FOR_IDENTITY_RESTORE)
        assertThat(
            resolve(
                permissionGranted = true,
                currentAccountID = AccountB,
                currentGeneration = Generation,
                isIdentityRestoring = false,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.DISCARD)
        assertThat(
            resolve(
                permissionGranted = true,
                currentAccountID = AccountA,
                currentGeneration = Generation + 1,
                isIdentityRestoring = false,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.DISCARD)
    }

    @Test
    fun incompletePendingStateDoesNothing() {
        assertThat(
            pendingAccountNotificationPermissionAction(
                pendingAccountID = null,
                pendingGeneration = null,
                permissionGranted = null,
                currentAccountID = AccountA,
                currentGeneration = Generation,
                currentGuestMode = false,
                isIdentityRestoring = false,
            ),
        ).isEqualTo(PendingAccountNotificationPermissionAction.NONE)
    }

    private fun resolve(
        permissionGranted: Boolean,
        currentAccountID: String?,
        currentGeneration: Long,
        isIdentityRestoring: Boolean,
    ): PendingAccountNotificationPermissionAction = pendingAccountNotificationPermissionAction(
        pendingAccountID = AccountA,
        pendingGeneration = Generation,
        permissionGranted = permissionGranted,
        currentAccountID = currentAccountID,
        currentGeneration = currentGeneration,
        currentGuestMode = false,
        isIdentityRestoring = isIdentityRestoring,
    )

    private companion object {
        const val AccountA = "account-a"
        const val AccountB = "account-b"
        const val Generation = 7L
    }
}
