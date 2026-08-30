package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.BakalariClient
import com.bukovinafilip.gradey.domain.BakalariDemoAccount
import com.bukovinafilip.gradey.domain.InvalidDemoAccountCredentialsException
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.LoginResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.UserResponse
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Test

class DemoAwareBakalariClientTest {
    @Test
    fun `exact demo credentials use only the demo client`() = runTest {
        val live = LoginRecordingClient("live")
        val demo = LoginRecordingClient(BakalariDemoAccount.accessToken)
        val client = DemoAwareBakalariClient(liveClient = live, demoClient = demo)

        val response = client.login(
            baseURL = "https://demo.gradely.app",
            username = " APPLE-REVIEW ",
            password = "GradelyDemo2026!",
        )

        assertThat(response.accessToken).isEqualTo(BakalariDemoAccount.accessToken)
        assertThat(demo.loginCount).isEqualTo(1)
        assertThat(live.loginCount).isEqualTo(0)
    }

    @Test
    fun `wrong demo credentials are rejected without touching either client`() = runTest {
        val live = LoginRecordingClient("live")
        val demo = LoginRecordingClient("demo")
        val client = DemoAwareBakalariClient(liveClient = live, demoClient = demo)

        val failure = runCatching {
            client.login("https://demo.gradely.app", "apple-review", "wrong")
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(InvalidDemoAccountCredentialsException::class.java)
        assertThat(failure?.message).isEqualTo(
            "Use demo.gradely.app, apple-review, and GradelyDemo2026! for the demo account.",
        )
        assertThat(demo.loginCount).isEqualTo(0)
        assertThat(live.loginCount).isEqualTo(0)
    }

    @Test
    fun `demo credentials on another host still use the live client`() = runTest {
        val live = LoginRecordingClient("live")
        val demo = LoginRecordingClient("demo")
        val client = DemoAwareBakalariClient(liveClient = live, demoClient = demo)

        val response = client.login(
            baseURL = "https://school.example.cz",
            username = BakalariDemoAccount.username,
            password = BakalariDemoAccount.password,
        )

        assertThat(response.accessToken).isEqualTo("live")
        assertThat(live.loginCount).isEqualTo(1)
        assertThat(demo.loginCount).isEqualTo(0)
    }
}

private class LoginRecordingClient(private val accessToken: String) : BakalariClient {
    var loginCount = 0

    override suspend fun login(baseURL: String, username: String, password: String): LoginResponse {
        loginCount += 1
        return LoginResponse(accessToken, "refresh", "Bearer", 3_600)
    }

    override suspend fun refreshToken(baseURL: String, refreshToken: String): LoginResponse =
        error("Not used")

    override suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse =
        error("Not used")

    override suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse =
        error("Not used")

    override suspend fun fetchUser(baseURL: String, accessToken: String): UserResponse =
        error("Not used")

    override suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): TimetableResponse =
        error("Not used")

    override suspend fun predictSubject(
        baseURL: String,
        accessToken: String,
        subject: Subject,
        markText: String,
        weight: Int,
    ): Subject = error("Not used")
}
