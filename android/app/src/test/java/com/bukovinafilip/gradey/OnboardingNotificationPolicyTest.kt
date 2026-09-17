package com.bukovinafilip.gradey

import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class OnboardingNotificationPolicyTest {
    @Test
    fun `onboarding choice updates only the canonical new-marks preference`() {
        val current = NotificationPreferences(
            newMarksEnabled = true,
            lockScreenDetail = NotificationLockScreenDetail.PRIVATE_SUMMARY,
            quietHoursEnabled = true,
            quietHoursStartMinute = 21 * 60,
            quietHoursEndMinute = 7 * 60,
            quietHoursTimeZone = "Europe/Prague",
        )

        val skipped = onboardingNotificationPreferences(current, enabled = false)
        val enabled = onboardingNotificationPreferences(skipped, enabled = true)

        assertThat(skipped).isEqualTo(current.copy(newMarksEnabled = false))
        assertThat(enabled).isEqualTo(current)
    }

    @Test
    fun `ready reports enabled only when preference and device permission agree`() {
        val enabled = NotificationPreferences.Default
        val disabled = enabled.copy(newMarksEnabled = false)

        assertThat(onboardingNotificationsEnabled(enabled, permissionGranted = true)).isTrue()
        assertThat(onboardingNotificationsEnabled(enabled, permissionGranted = false)).isFalse()
        assertThat(onboardingNotificationsEnabled(disabled, permissionGranted = true)).isFalse()
        assertThat(onboardingNotificationsEnabled(disabled, permissionGranted = false)).isFalse()
    }

    @Test
    fun `onboarding and settings share server-update normalization`() {
        val unprepared = NotificationPreferences.Default.copy(
            quietHoursStartMinute = -1,
            quietHoursEndMinute = 1_500,
            quietHoursTimeZone = "stale-zone",
        )

        assertThat(prepareNotificationPreferencesForUpdate(unprepared, "Europe/Prague"))
            .isEqualTo(
                unprepared.copy(
                    quietHoursStartMinute = 0,
                    quietHoursEndMinute = 1_439,
                    quietHoursTimeZone = "Europe/Prague",
                ),
            )
    }
}
