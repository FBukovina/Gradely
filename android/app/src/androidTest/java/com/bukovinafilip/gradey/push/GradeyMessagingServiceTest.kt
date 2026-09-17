package com.bukovinafilip.gradey.push

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.bukovinafilip.gradey.FCM_DEEP_LINK_URL_EXTRA
import com.bukovinafilip.gradey.MainActivity
import com.google.android.gms.tasks.Tasks
import com.google.firebase.messaging.FcmBroadcastProcessor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyMessagingServiceTest {
    @Test
    fun foregroundBackendNotificationMessagePostsProductionNotificationAndDeepLink() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        val messageId = "instrumentation-${SystemClock.elapsedRealtimeNanos()}"
        val notificationId = messageId.hashCode()
        var originalActivity: MainActivity? = null
        var launchedActivity: MainActivity? = null

        if (
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // Revoking a runtime permission kills the instrumented app process. This test therefore
            // grants once and relies on the isolated connected-test installation for permission cleanup.
            instrumentation.uiAutomation.grantRuntimePermission(
                context.packageName,
                Manifest.permission.POST_NOTIFICATIONS,
            )
        }

        try {
            notificationManager.cancel(notificationId)
            GradeyMessagingService.createNotificationChannel(context)
            originalActivity = launchMainActivity(instrumentation)
            val initialDeepLinkRequest = originalActivity.currentDeepLinkRequestForTesting()

            val incomingIntent = backendNotificationIntent(messageId)

            Tasks.await(
                FcmBroadcastProcessor(context).process(incomingIntent),
                PROCESS_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )

            val posted = waitForNotification(notificationManager, notificationId)
            val notification = posted.notification
            assertEquals(GradeyMessagingService.CHANNEL_ID, notification.channelId)
            assertEquals(EXPECTED_TITLE, notification.extras.getString(Notification.EXTRA_TITLE))
            assertEquals(EXPECTED_BODY, notification.extras.getString(Notification.EXTRA_TEXT))
            assertTrue(notification.flags and Notification.FLAG_AUTO_CANCEL != 0)

            val contentIntent = notification.contentIntent
            assertNotNull(contentIntent)
            assertEquals(context.packageName, contentIntent.creatorPackage)
            assertTrue(contentIntent.isActivity)
            contentIntent.send()
            launchedActivity = waitForMainActivity(instrumentation) {
                it.intent.dataString == EXPECTED_CANONICAL_DEEP_LINK
            }
            val deliveredDeepLinkRequest = waitForDeepLinkRequest(
                instrumentation = instrumentation,
                activity = launchedActivity,
                afterSequence = initialDeepLinkRequest.sequence,
                expectedRawUri = EXPECTED_CANONICAL_DEEP_LINK,
            )
            assertSame(originalActivity, launchedActivity)
            assertTrue(deliveredDeepLinkRequest.sequence > initialDeepLinkRequest.sequence)
            assertEquals(EXPECTED_CANONICAL_DEEP_LINK, deliveredDeepLinkRequest.rawUri)
            assertEquals(Intent.ACTION_VIEW, launchedActivity.intent.action)
            assertEquals(EXPECTED_CANONICAL_DEEP_LINK, launchedActivity.intent.dataString)
            assertTrue(launchedActivity.intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
            assertTrue(launchedActivity.intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)

            val channel = notificationManager.getNotificationChannel(GradeyMessagingService.CHANNEL_ID)
            assertNotNull(channel)
            assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance)
        } finally {
            notificationManager.cancel(notificationId)
            finishIfNeeded(instrumentation, launchedActivity?.takeUnless { it === originalActivity })
            finishIfNeeded(instrumentation, originalActivity)
        }
    }

    @Test
    fun modeledFirebaseSystemWarmTapUsesClearTopAndReusesMainActivity() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        var originalActivity: MainActivity? = null
        var deliveredActivity: MainActivity? = null

        try {
            originalActivity = launchMainActivity(instrumentation)
            val initialDeepLinkRequest = originalActivity.currentDeepLinkRequestForTesting()

            // Firebase Messaging 24.1.0's system notification builder starts the package launcher
            // with CLEAR_TOP and the non-reserved data payload. This models that PendingIntent shape;
            // it does not invoke Firebase's background system-rendering branch.
            val systemTapIntent = requireNotNull(
                context.packageManager.getLaunchIntentForPackage(context.packageName),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(FCM_DEEP_LINK_URL_EXTRA, BACKEND_DEEP_LINK)
                putExtra(EVENT_ID_EXTRA, PRIVATE_EVENT_ID)
            }
            assertFalse(systemTapIntent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
            val pendingIntent = PendingIntent.getActivity(
                context,
                SystemClock.elapsedRealtimeNanos().hashCode(),
                systemTapIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
            )

            pendingIntent.send()

            deliveredActivity = waitForMainActivity(instrumentation) {
                it.intent.getStringExtra(FCM_DEEP_LINK_URL_EXTRA) == BACKEND_DEEP_LINK
            }
            val deliveredDeepLinkRequest = waitForDeepLinkRequest(
                instrumentation = instrumentation,
                activity = deliveredActivity,
                afterSequence = initialDeepLinkRequest.sequence,
                expectedRawUri = EXPECTED_CANONICAL_DEEP_LINK,
            )
            assertSame(originalActivity, deliveredActivity)
            assertTrue(deliveredDeepLinkRequest.sequence > initialDeepLinkRequest.sequence)
            assertEquals(EXPECTED_CANONICAL_DEEP_LINK, deliveredDeepLinkRequest.rawUri)
            assertEquals(Intent.ACTION_MAIN, deliveredActivity.intent.action)
            assertTrue(deliveredActivity.intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
            assertFalse(deliveredActivity.intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
        } finally {
            finishIfNeeded(instrumentation, deliveredActivity?.takeUnless { it === originalActivity })
            finishIfNeeded(instrumentation, originalActivity)
        }
    }

    private fun backendNotificationIntent(messageId: String): Intent =
        Intent(ACTION_REMOTE_INTENT).apply {
            putExtra(EXTRA_MESSAGE_ID, messageId)
            putExtra(NOTIFICATION_ENABLED_EXTRA, "1")
            putExtra(NOTIFICATION_TITLE_EXTRA, EXPECTED_TITLE)
            putExtra(NOTIFICATION_BODY_EXTRA, EXPECTED_BODY)
            putExtra(NOTIFICATION_CHANNEL_EXTRA, GradeyMessagingService.CHANNEL_ID)
            putExtra(NOTIFICATION_SOUND_EXTRA, "default")
            putExtra(FCM_DEEP_LINK_URL_EXTRA, BACKEND_DEEP_LINK)
            putExtra(EVENT_ID_EXTRA, PRIVATE_EVENT_ID)
        }

    private fun waitForNotification(
        notificationManager: NotificationManager,
        notificationId: Int,
    ): android.service.notification.StatusBarNotification {
        val deadline = SystemClock.elapsedRealtime() + NOTIFICATION_TIMEOUT_MILLIS
        while (SystemClock.elapsedRealtime() < deadline) {
            notificationManager.activeNotifications
                .firstOrNull { it.id == notificationId }
                ?.let { return it }
            SystemClock.sleep(POLL_INTERVAL_MILLIS)
        }
        fail("GradeyMessagingService did not post notification $notificationId")
        throw AssertionError("Unreachable")
    }

    private fun waitForDeepLinkRequest(
        instrumentation: android.app.Instrumentation,
        activity: MainActivity,
        afterSequence: Long,
        expectedRawUri: String,
    ): com.bukovinafilip.gradey.DeepLinkRequest {
        val deadline = SystemClock.elapsedRealtime() + ACTIVITY_TIMEOUT_MILLIS
        val request = AtomicReference<com.bukovinafilip.gradey.DeepLinkRequest?>()
        while (SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync {
                request.set(
                    activity.currentDeepLinkRequestForTesting()
                        .takeIf {
                            it.sequence > afterSequence &&
                                it.rawUri == expectedRawUri
                        },
                )
            }
            request.get()?.let { return it }
            SystemClock.sleep(POLL_INTERVAL_MILLIS)
        }
        fail("MainActivity did not accept $expectedRawUri after sequence $afterSequence")
        throw AssertionError("Unreachable")
    }

    private fun waitForMainActivity(
        instrumentation: android.app.Instrumentation,
        predicate: (MainActivity) -> Boolean = { true },
    ): MainActivity {
        val deadline = SystemClock.elapsedRealtime() + ACTIVITY_TIMEOUT_MILLIS
        val resumedActivity = AtomicReference<MainActivity?>()
        while (SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync {
                resumedActivity.set(
                    ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .filterIsInstance<MainActivity>()
                        .firstOrNull(predicate),
                )
            }
            resumedActivity.get()?.let { return it }
            SystemClock.sleep(POLL_INTERVAL_MILLIS)
        }
        fail("Notification content intent did not open MainActivity")
        throw AssertionError("Unreachable")
    }

    private fun launchMainActivity(
        instrumentation: android.app.Instrumentation,
    ): MainActivity {
        val context = instrumentation.targetContext
        context.startActivity(
            Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            },
        )
        return waitForMainActivity(instrumentation)
    }

    private fun finishIfNeeded(
        instrumentation: android.app.Instrumentation,
        activity: MainActivity?,
    ) {
        activity ?: return
        instrumentation.runOnMainSync {
            if (!activity.isFinishing && !activity.isDestroyed) activity.finishAndRemoveTask()
        }
        instrumentation.waitForIdleSync()
    }

    private companion object {
        const val ACTION_REMOTE_INTENT = "com.google.android.c2dm.intent.RECEIVE"
        const val EXTRA_MESSAGE_ID = "google.message_id"
        const val NOTIFICATION_ENABLED_EXTRA = "gcm.n.e"
        const val NOTIFICATION_TITLE_EXTRA = "gcm.n.title"
        const val NOTIFICATION_BODY_EXTRA = "gcm.n.body"
        const val NOTIFICATION_CHANNEL_EXTRA = "gcm.n.android_channel_id"
        const val NOTIFICATION_SOUND_EXTRA = "gcm.n.sound2"
        const val EVENT_ID_EXTRA = "eventID"
        const val PRIVATE_EVENT_ID = "private-event-id"
        const val EXPECTED_TITLE = "New mark"
        const val EXPECTED_BODY = "1 · Mathematics"
        const val BACKEND_DEEP_LINK = "gradey://marks?event=private-event-id"
        const val EXPECTED_CANONICAL_DEEP_LINK = "gradey://marks"
        const val PROCESS_TIMEOUT_SECONDS = 10L
        const val NOTIFICATION_TIMEOUT_MILLIS = 10_000L
        const val ACTIVITY_TIMEOUT_MILLIS = 10_000L
        const val POLL_INTERVAL_MILLIS = 50L
    }
}
