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
}
