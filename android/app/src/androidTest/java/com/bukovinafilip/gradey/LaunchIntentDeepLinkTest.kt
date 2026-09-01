package com.bukovinafilip.gradey

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LaunchIntentDeepLinkTest {
    @Test
    fun backgroundFcmLauncherIntentReadsAndCanonicalizesTheUrlExtra() {
        val marksIntent = Intent(Intent.ACTION_MAIN).apply {
            putExtra(FCM_DEEP_LINK_URL_EXTRA, "gradey://marks?event=private-event-id")
        }
        val timetableIntent = Intent(Intent.ACTION_MAIN).apply {
            putExtra(FCM_DEEP_LINK_URL_EXTRA, "gradely:///timetable?week=next")
        }

        assertEquals("gradey://marks", marksIntent.resolvedGradeyLaunchDeepLink())
        assertEquals("gradey://timetable", timetableIntent.resolvedGradeyLaunchDeepLink())
    }

    @Test
    fun explicitViewDataWinsAndAnUnsupportedExplicitUriFailsClosed() {
        val explicitTimetable = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("gradey://timetable?week=current")
            putExtra(FCM_DEEP_LINK_URL_EXTRA, "gradey://marks?event=private-event-id")
        }
        val hostileExplicitData = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("https://example.com/marks")
            putExtra(FCM_DEEP_LINK_URL_EXTRA, "gradey://marks?event=private-event-id")
        }

        assertEquals("gradey://timetable", explicitTimetable.resolvedGradeyLaunchDeepLink())
        assertNull(hostileExplicitData.resolvedGradeyLaunchDeepLink())
    }
}
