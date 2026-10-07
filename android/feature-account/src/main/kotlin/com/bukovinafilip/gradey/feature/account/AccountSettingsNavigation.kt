package com.bukovinafilip.gradey.feature.account

import androidx.annotation.StringRes

enum class AccountSettingsDestination(
    @get:StringRes internal val titleResource: Int,
    @get:StringRes internal val subtitleResource: Int,
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

internal enum class AccountSettingsServiceStatus {
    CONNECTED,
    NOT_CONNECTED,
    ACTION_REQUIRED,
}

internal data class AccountSettingsServicesOverview(
    val bakalari: AccountSettingsServiceStatus,
    val strava: AccountSettingsServiceStatus,
)

internal fun accountSettingsServicesOverview(
    hasBakalariConnection: Boolean,
    bakalariNeedsAttention: Boolean,
    hasStravaConnection: Boolean,
    stravaNeedsAttention: Boolean,
): AccountSettingsServicesOverview = AccountSettingsServicesOverview(
    bakalari = accountSettingsServiceStatus(hasBakalariConnection, bakalariNeedsAttention),
    strava = accountSettingsServiceStatus(hasStravaConnection, stravaNeedsAttention),
)

private fun accountSettingsServiceStatus(
    isConnected: Boolean,
    needsAttention: Boolean,
): AccountSettingsServiceStatus = when {
    needsAttention -> AccountSettingsServiceStatus.ACTION_REQUIRED
    isConnected -> AccountSettingsServiceStatus.CONNECTED
    else -> AccountSettingsServiceStatus.NOT_CONNECTED
}

internal enum class AccountSettingsNotificationStatus {
    UNAVAILABLE,
    OFF,
    PERMISSION_REQUIRED,
    QUIET_HOURS,
    ON,
}

internal fun accountSettingsNotificationStatus(
    isAvailable: Boolean,
    isEnabled: Boolean,
    isPermissionGranted: Boolean,
    isQuietHoursEnabled: Boolean,
): AccountSettingsNotificationStatus = when {
    !isAvailable -> AccountSettingsNotificationStatus.UNAVAILABLE
    !isEnabled -> AccountSettingsNotificationStatus.OFF
    !isPermissionGranted -> AccountSettingsNotificationStatus.PERMISSION_REQUIRED
    isQuietHoursEnabled -> AccountSettingsNotificationStatus.QUIET_HOURS
    else -> AccountSettingsNotificationStatus.ON
}
