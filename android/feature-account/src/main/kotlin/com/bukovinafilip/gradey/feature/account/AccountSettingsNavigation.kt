package com.bukovinafilip.gradey.feature.account

import androidx.annotation.StringRes

internal enum class AccountSettingsDestination(
    @get:StringRes val titleResource: Int,
    @get:StringRes val subtitleResource: Int,
) {
    ACCOUNT(R.string.settings_destination_account, R.string.settings_destination_account_subtitle),
    CONNECTED_SERVICES(
        R.string.settings_destination_connected,
        R.string.settings_destination_connected_subtitle,
    ),
    NOTIFICATIONS(
        R.string.settings_destination_notifications,
        R.string.settings_destination_notifications_subtitle,
    ),
    PRIVACY_DATA(R.string.settings_destination_privacy, R.string.settings_destination_privacy_subtitle),
    APP_PREFERENCES(
        R.string.settings_destination_preferences,
        R.string.settings_destination_preferences_subtitle,
    ),
    SUPPORT_ABOUT(R.string.settings_destination_support, R.string.settings_destination_support_subtitle),
}

internal enum class AccountSettingsPaneMode {
    COMPACT,
    EXPANDED,
}

internal fun accountSettingsPaneMode(widthDp: Float): AccountSettingsPaneMode =
    if (widthDp >= ACCOUNT_SETTINGS_EXPANDED_WIDTH_DP) {
        AccountSettingsPaneMode.EXPANDED
    } else {
        AccountSettingsPaneMode.COMPACT
    }

internal fun resolvedAccountSettingsDestination(
    paneMode: AccountSettingsPaneMode,
    selectedDestination: AccountSettingsDestination?,
): AccountSettingsDestination? = when (paneMode) {
    AccountSettingsPaneMode.COMPACT -> selectedDestination
    AccountSettingsPaneMode.EXPANDED -> selectedDestination ?: AccountSettingsDestination.ACCOUNT
}

internal const val ACCOUNT_SETTINGS_EXPANDED_WIDTH_DP = 840f
