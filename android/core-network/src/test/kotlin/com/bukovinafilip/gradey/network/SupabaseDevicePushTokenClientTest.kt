package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class SupabaseDevicePushTokenClientTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `register sends android token and environment with Gradey authorization`() = runTest {
        server.enqueue(success())

        client().registerDeviceToken("fcm-token", "android", "production", session)
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject

        assertThat(request.path).isEqualTo("/functions/v1/register-device")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer access-token")
        assertThat(request.getHeader("apikey")).isEqualTo("anon-key")
        assertThat(body.getValue("token").jsonPrimitive.content).isEqualTo("fcm-token")
        assertThat(body.getValue("platform").jsonPrimitive.content).isEqualTo("android")
        assertThat(body.getValue("environment").jsonPrimitive.content).isEqualTo("production")
    }

    @Test
    fun `preferences use canonical snake case notification contract`() = runTest {
        server.enqueue(success())
        val preferences = NotificationPreferences(
            newMarksEnabled = false,
            lockScreenDetail = NotificationLockScreenDetail.PRIVATE_SUMMARY,
            quietHoursEnabled = true,
            quietHoursStartMinute = 20 * 60 + 30,
            quietHoursEndMinute = 7 * 60,
            quietHoursTimeZone = "Europe/Prague",
        )

        client().updateNotificationPreferences(preferences, session)
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject

        assertThat(request.path).isEqualTo("/functions/v1/update-notification-preferences")
        assertThat(body.getValue("new_marks_enabled").jsonPrimitive.content).isEqualTo("false")
        assertThat(body.getValue("lock_screen_detail").jsonPrimitive.content).isEqualTo("private_summary")
        assertThat(body.getValue("quiet_hours_enabled").jsonPrimitive.content).isEqualTo("true")
        assertThat(body.getValue("quiet_hours_start_minute").jsonPrimitive.content).isEqualTo("1230")
        assertThat(body.getValue("quiet_hours_end_minute").jsonPrimitive.content).isEqualTo("420")
        assertThat(body.getValue("quiet_hours_time_zone").jsonPrimitive.content).isEqualTo("Europe/Prague")
    }

    @Test
    fun `data export returns server json through authenticated endpoint`() = runTest {
        val export = """{"schemaVersion":2,"profile":{"id":"account"}}"""
        server.enqueue(success(export))

        val result = client().requestDataExport(session)
        val request = server.takeRequest()

        assertThat(result).isEqualTo(export)
        assertThat(request.path).isEqualTo("/functions/v1/request-data-export")
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer access-token")
        assertThat(request.body.readUtf8()).isEqualTo("{}")
    }

    @Test
    fun `account deletion uses authenticated delete function`() = runTest {
        server.enqueue(success())

        client().deleteAccount(session)
        val request = server.takeRequest()

        assertThat(request.path).isEqualTo("/functions/v1/delete-account")
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer access-token")
        assertThat(request.body.readUtf8()).isEqualTo("{}")
    }

    private fun client() = SupabaseDevicePushTokenClient(
        SupabaseConfiguration(server.url("/").toString(), "anon-key"),
    )

    private fun success(body: String = "{}") = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)

    private val session = GradeyAuthSession(
        accessToken = "access-token",
        account = GradeyAccount(id = "account"),
    )
}
