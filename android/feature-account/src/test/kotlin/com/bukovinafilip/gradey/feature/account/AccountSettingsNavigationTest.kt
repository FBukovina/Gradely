package com.bukovinafilip.gradey.feature.account

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AccountSettingsNavigationTest {
    @Test
    fun `compact layout keeps overview as the root destination`() {
        assertThat(accountSettingsPaneMode(839f)).isEqualTo(AccountSettingsPaneMode.COMPACT)
        assertThat(
            resolvedAccountSettingsDestination(AccountSettingsPaneMode.COMPACT, null),
        ).isNull()
    }

    @Test
    fun `expanded layout defaults to account detail`() {
        assertThat(accountSettingsPaneMode(840f)).isEqualTo(AccountSettingsPaneMode.EXPANDED)
        assertThat(
            resolvedAccountSettingsDestination(AccountSettingsPaneMode.EXPANDED, null),
        ).isEqualTo(AccountSettingsDestination.ACCOUNT)
    }

    @Test
    fun `explicit destination survives layout changes`() {
        AccountSettingsPaneMode.entries.forEach { mode ->
            assertThat(
                resolvedAccountSettingsDestination(mode, AccountSettingsDestination.PRIVACY_DATA),
            ).isEqualTo(AccountSettingsDestination.PRIVACY_DATA)
        }
    }

    @Test
    fun `restored support destination resolves back to support detail`() {
        AccountSettingsPaneMode.entries.forEach { mode ->
            assertThat(
                resolvedAccountSettingsDestination(mode, AccountSettingsDestination.SUPPORT_ABOUT),
            ).isEqualTo(AccountSettingsDestination.SUPPORT_ABOUT)
        }
    }

    @Test
    fun `overview exposes all six authoritative destinations in order`() {
        assertThat(AccountSettingsDestination.entries).containsExactly(
            AccountSettingsDestination.ACCOUNT,
            AccountSettingsDestination.CONNECTED_SERVICES,
            AccountSettingsDestination.NOTIFICATIONS,
            AccountSettingsDestination.PRIVACY_DATA,
            AccountSettingsDestination.APP_PREFERENCES,
            AccountSettingsDestination.SUPPORT_ABOUT,
        ).inOrder()
    }

    @Test
    fun `services overview reports Bakalari and Strava independently`() {
        assertThat(
            accountSettingsServicesOverview(
                hasBakalariConnection = true,
                bakalariNeedsAttention = false,
                hasStravaConnection = false,
                stravaNeedsAttention = false,
            ),
        ).isEqualTo(
            AccountSettingsServicesOverview(
                bakalari = AccountSettingsServiceStatus.CONNECTED,
                strava = AccountSettingsServiceStatus.NOT_CONNECTED,
            ),
        )
    }

    @Test
    fun `service attention takes precedence over a connection snapshot`() {
        assertThat(
            accountSettingsServicesOverview(
                hasBakalariConnection = true,
                bakalariNeedsAttention = true,
                hasStravaConnection = true,
                stravaNeedsAttention = true,
            ),
        ).isEqualTo(
            AccountSettingsServicesOverview(
                bakalari = AccountSettingsServiceStatus.ACTION_REQUIRED,
                strava = AccountSettingsServiceStatus.ACTION_REQUIRED,
            ),
        )
    }

    @Test
    fun `notification overview reflects availability enabled permission and quiet hours`() {
        assertThat(
            accountSettingsNotificationStatus(
                isAvailable = false,
                isEnabled = true,
                isPermissionGranted = true,
                isQuietHoursEnabled = false,
            ),
        ).isEqualTo(AccountSettingsNotificationStatus.UNAVAILABLE)
        assertThat(
            accountSettingsNotificationStatus(
                isAvailable = true,
                isEnabled = false,
                isPermissionGranted = false,
                isQuietHoursEnabled = true,
            ),
        ).isEqualTo(AccountSettingsNotificationStatus.OFF)
        assertThat(
            accountSettingsNotificationStatus(
                isAvailable = true,
                isEnabled = true,
                isPermissionGranted = false,
                isQuietHoursEnabled = true,
            ),
        ).isEqualTo(AccountSettingsNotificationStatus.PERMISSION_REQUIRED)
        assertThat(
            accountSettingsNotificationStatus(
                isAvailable = true,
                isEnabled = true,
                isPermissionGranted = true,
                isQuietHoursEnabled = true,
            ),
        ).isEqualTo(AccountSettingsNotificationStatus.QUIET_HOURS)
        assertThat(
            accountSettingsNotificationStatus(
                isAvailable = true,
                isEnabled = true,
                isPermissionGranted = true,
                isQuietHoursEnabled = false,
            ),
        ).isEqualTo(AccountSettingsNotificationStatus.ON)
    }
}
