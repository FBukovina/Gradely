package com.bukovinafilip.gradey.push

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
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
import com.google.firebase.messaging.RemoteMessage
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyMessagingServiceTest {
    @Test
    fun foregroundDataMessagePostsProductionNotificationAndDeepLink() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        val messageId = "instrumentation-${SystemClock.elapsedRealtimeNanos()}"
        val notificationId = messageId.hashCode()
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

            val message = RemoteMessage.Builder("local-instrumentation")
                .setMessageId(messageId)
                .addData("title", EXPECTED_TITLE)
                .addData("body", EXPECTED_BODY)
                .addData(FCM_DEEP_LINK_URL_EXTRA, INPUT_DEEP_LINK)
                .build()
            val incomingIntent = message.asFirebaseIncomingIntent()

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
            launchedActivity = waitForMainActivity(instrumentation)
            assertEquals(Intent.ACTION_VIEW, launchedActivity.intent.action)
            assertEquals(EXPECTED_CANONICAL_DEEP_LINK, launchedActivity.intent.dataString)
            assertTrue(launchedActivity.intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
            assertTrue(launchedActivity.intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)

            val channel = notificationManager.getNotificationChannel(GradeyMessagingService.CHANNEL_ID)
            assertNotNull(channel)
            assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance)
        } finally {
            notificationManager.cancel(notificationId)
            launchedActivity?.let { activity ->
                instrumentation.runOnMainSync {
                    if (!activity.isFinishing) activity.finishAndRemoveTask()
                }
                instrumentation.waitForIdleSync()
            }
        }
    }

    private fun RemoteMessage.asFirebaseIncomingIntent(): Intent =
        Intent(ACTION_REMOTE_INTENT).apply {
            messageId?.let { putExtra(EXTRA_MESSAGE_ID, it) }
            this@asFirebaseIncomingIntent.data.forEach { (key, value) -> putExtra(key, value) }
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

    private fun waitForMainActivity(
        instrumentation: android.app.Instrumentation,
    ): MainActivity {
        val deadline = SystemClock.elapsedRealtime() + ACTIVITY_TIMEOUT_MILLIS
        val resumedActivity = AtomicReference<MainActivity?>()
        while (SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync {
                resumedActivity.set(
                    ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .filterIsInstance<MainActivity>()
                        .firstOrNull(),
                )
            }
            resumedActivity.get()?.let { return it }
            SystemClock.sleep(POLL_INTERVAL_MILLIS)
        }
        fail("Notification content intent did not open MainActivity")
        throw AssertionError("Unreachable")
    }

    private companion object {
        const val ACTION_REMOTE_INTENT = "com.google.android.c2dm.intent.RECEIVE"
        const val EXTRA_MESSAGE_ID = "google.message_id"
        const val EXPECTED_TITLE = "Foreground mark title"
        const val EXPECTED_BODY = "Foreground mark body"
        const val INPUT_DEEP_LINK = "gradely:///subjects?event=private-event-id"
        const val EXPECTED_CANONICAL_DEEP_LINK = "gradey://marks"
        const val PROCESS_TIMEOUT_SECONDS = 10L
        const val NOTIFICATION_TIMEOUT_MILLIS = 10_000L
        const val ACTIVITY_TIMEOUT_MILLIS = 10_000L
        const val POLL_INTERVAL_MILLIS = 50L
    }
}
