package com.bukovinafilip.gradey.widgets

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class NextLessonWidgetLaunchSpecTest {
    @Test
    fun `timetable tap targets the host Gradey activity explicitly`() {
        val spec = nextLessonWidgetLaunchSpec("com.example.gradey.debug")

        assertThat(spec.action).isEqualTo("android.intent.action.VIEW")
        assertThat(spec.uri).isEqualTo("gradey://timetable")
        assertThat(spec.packageName).isEqualTo("com.example.gradey.debug")
        assertThat(spec.activityClassName).isEqualTo("com.bukovinafilip.gradey.MainActivity")
    }
}
