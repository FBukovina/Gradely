package com.bukovinafilip.gradey

import com.bukovinafilip.gradey.model.NotificationPreferences

internal fun onboardingNotificationPreferences(
    current: NotificationPreferences,
    enabled: Boolean,
): NotificationPreferences = current.copy(newMarksEnabled = enabled)

internal fun prepareNotificationPreferencesForUpdate(
    preferences: NotificationPreferences,
    timeZoneID: String,
): NotificationPreferences = preferences.copy(
    quietHoursStartMinute = preferences.quietHoursStartMinute.coerceIn(0, 1439),
    quietHoursEndMinute = preferences.quietHoursEndMinute.coerceIn(0, 1439),
    quietHoursTimeZone = timeZoneID,
)

internal fun onboardingNotificationsEnabled(
    preferences: NotificationPreferences,
    permissionGranted: Boolean,
): Boolean = preferences.newMarksEnabled && permissionGranted
