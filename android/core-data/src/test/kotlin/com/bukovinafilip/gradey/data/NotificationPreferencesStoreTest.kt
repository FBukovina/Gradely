package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class NotificationPreferencesStoreTest {
    @Test
    fun `preferences default persist restore and recover from corruption`() {
        var stored: String? = null
        val store = NotificationPreferencesStore({ stored }, { stored = it }, GradeyJson)

        assertThat(store.preferences).isEqualTo(NotificationPreferences.Default)
        val updated = NotificationPreferences(
            newMarksEnabled = false,
            lockScreenDetail = NotificationLockScreenDetail.PRIVATE_SUMMARY,
            quietHoursEnabled = true,
            quietHoursStartMinute = 21 * 60,
            quietHoursEndMinute = 7 * 60,
            quietHoursTimeZone = "Europe/Prague",
        )

        store.preferences = updated
        assertThat(store.preferences).isEqualTo(updated)

        stored = "not-json"
        assertThat(store.preferences).isEqualTo(NotificationPreferences.Default)

        store.clear()
        assertThat(stored).isNull()
    }
}
