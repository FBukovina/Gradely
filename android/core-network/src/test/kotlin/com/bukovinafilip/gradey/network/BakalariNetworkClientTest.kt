package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class BakalariNetworkClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: BakalariNetworkClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        client = BakalariNetworkClient()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun loginSendsBakalariPasswordGrantAsEncodedForm() = runTest {
        server.enqueue(jsonResponse(LOGIN_RESPONSE))

        val result = client.login(baseURL(), "first last", "p+&")
        val request = server.takeRequest()

        assertThat(result.accessToken).isEqualTo("access")
        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/api/login")
        assertThat(request.getHeader("Accept")).isEqualTo("application/json")
        assertThat(request.getHeader("Content-Type")).startsWith("application/x-www-form-urlencoded")
        assertThat(request.body.readUtf8()).isEqualTo(
            "client_id=ANDR&grant_type=password&username=first%20last&password=p%2B%26",
        )
    }

    @Test
    fun refreshSendsBakalariRefreshGrantAsEncodedForm() = runTest {
        server.enqueue(jsonResponse(LOGIN_RESPONSE))

        client.refreshToken(baseURL(), "refresh +&")
        val request = server.takeRequest()

        assertThat(request.path).isEqualTo("/api/login")
        assertThat(request.body.readUtf8()).isEqualTo(
            "client_id=ANDR&grant_type=refresh_token&refresh_token=refresh%20%2B%26",
        )
    }

    @Test
    fun whatIfSendsAuthenticatedJsonPayload() = runTest {
        server.enqueue(
            jsonResponse(
                """{"Marks":[],"Subject":{"Id":"math","Name":"Mathematics"}}""",
            ),
        )

        client.predictSubject(
            baseURL = baseURL(),
            accessToken = "access-token",
            subject = Subject(subjectInfo = SubjectInfo(id = "math", name = "Mathematics")),
            markText = "1",
            weight = 2,
        )
        val request = server.takeRequest()
        val payload = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonArray.single().jsonObject

        assertThat(request.path).isEqualTo("/api/3/marks/what-if")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer access-token")
        assertThat(request.getHeader("Content-Type")).startsWith("application/json")
        assertThat(payload["MarkText"]?.jsonPrimitive?.content).isEqualTo("1")
        assertThat(payload["Weight"]?.jsonPrimitive?.content).isEqualTo("2")
        assertThat(payload["SubjectId"]?.jsonPrimitive?.content).isEqualTo("math")
    }

    @Test
    fun structuredLoginErrorUsesReadableServerDescription() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"error":"invalid_grant","error_description":"Bad credentials"}"""),
        )

        val failure = runCatching { client.login(baseURL(), "student", "wrong") }.exceptionOrNull()

        assertThat(failure).isInstanceOf(BakalariApiException::class.java)
        failure as BakalariApiException
        assertThat(failure.statusCode).isEqualTo(400)
        assertThat(failure.message).isEqualTo("Bad credentials")
    }

    @Test
    fun htmlServerFailureIsNotExposedToTheUser() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(503)
                .setHeader("Content-Type", "text/html")
                .setBody("<html><body>proxy secret details</body></html>"),
        )

        val failure = runCatching { client.fetchMarks(baseURL(), "token") }.exceptionOrNull()

        assertThat(failure).isInstanceOf(BakalariApiException::class.java)
        failure as BakalariApiException
        assertThat(failure.statusCode).isEqualTo(503)
        assertThat(failure.message).isEqualTo("The Bakaláři server is temporarily unavailable (HTTP 503).")
        assertThat(failure.message).doesNotContain("proxy secret")
    }

    @Test
    fun malformedSuccessResponseBecomesSafeDecodingError() = runTest {
        server.enqueue(jsonResponse("not-json"))

        val failure = runCatching { client.fetchMarks(baseURL(), "token") }.exceptionOrNull()

        assertThat(failure).isInstanceOf(BakalariApiException::class.java)
        failure as BakalariApiException
        assertThat(failure.statusCode).isNull()
        assertThat(failure.message).isEqualTo("The school returned data Gradey could not read.")
    }

    @Test
    fun marksAcceptStringWeightAndMissingOptionalFields() = runTest {
        server.enqueue(
            jsonResponse(
                """
                {
                  "ServerSpecificField":{"ignored":true},
                  "Subjects":[{
                    "Marks":[
                      {"Weight":"2,5","MarkText":"1","IsNew":true},
                      {"Weight":{"unexpected":true},"MarkText":"2"}
                    ],
                    "Subject":{"Id":"math","Abbrev":"M","Name":"Mathematics"}
                  }]
                }
                """.trimIndent(),
            ),
        )

        val marks = client.fetchMarks(baseURL(), "token").subjects.single()

        assertThat(marks.marks[0].weight).isEqualTo(2.5)
        assertThat(marks.marks[0].isNew).isTrue()
        assertThat(marks.marks[0].subjectID).isEmpty()
        assertThat(marks.marks[1].weight).isNull()
        assertThat(marks.marks[0].id).isNotEmpty()
        assertThat(marks.marks[0].id).isNotEqualTo(marks.marks[1].id)
        assertThat(marks.markPredictionEnabled).isFalse()
    }

    @Test
    fun missingTopLevelCollectionsUseEmptyDefaults() = runTest {
        server.enqueue(jsonResponse("{}"))

        val marks = client.fetchMarks(baseURL(), "token")

        assertThat(marks.subjects).isEmpty()
    }

    @Test
    fun userDecodesRealClassObjectAndPreferredOrganizationName() = runTest {
        server.enqueue(
            jsonResponse(
                """
                {
                  "UserUID":"student-id",
                  "FullName":"Student Name",
                  "Class":{"Id":"class-id","Abbrev":"3.A","Name":"Third A"},
                  "SchoolOrganizationName":" Real School ",
                  "SchoolName":"Název školy",
                  "UserType":"student",
                  "UserTypeText":"Student",
                  "StudyYear":3
                }
                """.trimIndent(),
            ),
        )

        val user = client.fetchUser(baseURL(), "token")

        assertThat(user.classAbbrev).isEqualTo("3.A")
        assertThat(user.displaySchoolName).isEqualTo("Real School")
        assertThat(user.studyYear).isEqualTo(3)
    }

    @Test
    fun userAcceptsLegacyStringClassFromExistingAndroidCacheShape() = runTest {
        server.enqueue(jsonResponse("""{"FullName":"Student","Class":"4.B"}"""))

        val user = client.fetchUser(baseURL(), "token")

        assertThat(user.classAbbrev).isEqualTo("4.B")
    }

    @Test
    fun timetableAcceptsNumericHourIdsAndMissingDisplayFields() = runTest {
        server.enqueue(
            jsonResponse(
                """
                {
                  "Hours":[{"Id":1}],
                  "Days":[{"Atoms":[{"HourId":1}]}],
                  "Classes":[]
                }
                """.trimIndent(),
            ),
        )

        val timetable = client.fetchTimetable(baseURL(), "token", "2026-08-24")

        assertThat(timetable.hours.single().id).isEqualTo("1")
        assertThat(timetable.hours.single().caption).isEmpty()
        assertThat(timetable.days.single().atoms.single().hourID).isEqualTo("1")
        assertThat(timetable.days.single().dayType).isEqualTo("WorkDay")
        assertThat(timetable.classes).isEmpty()
    }

    private fun baseURL(): String = server.url("/").toString().removeSuffix("/")

    private fun jsonResponse(body: String): MockResponse = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)

    private companion object {
        const val LOGIN_RESPONSE =
            """{"access_token":"access","refresh_token":"refresh","token_type":"Bearer","expires_in":3600}"""
    }
}
