package com.bukovinafilip.gradey.feature.account

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AccountNotificationPermissionPolicyTest {
    @Test
    fun `enabling persists only when device permission is granted`() {
        assertThat(
            resolveNewMarksToggleAction(
                requestedEnabled = true,
                permissionGranted = true,
            ),
        ).isEqualTo(NewMarksToggleAction.Persist(enabled = true))
    }

    @Test
    fun `enabling without device permission requests recovery instead of persisting`() {
        assertThat(
            resolveNewMarksToggleAction(
                requestedEnabled = true,
                permissionGranted = false,
            ),
        ).isEqualTo(NewMarksToggleAction.RequestPermission)
    }

    @Test
    fun `disabling always persists regardless of device permission`() {
        listOf(false, true).forEach { permissionGranted ->
            assertThat(
                resolveNewMarksToggleAction(
                    requestedEnabled = false,
                    permissionGranted = permissionGranted,
                ),
            ).isEqualTo(NewMarksToggleAction.Persist(enabled = false))
        }
    }
}
