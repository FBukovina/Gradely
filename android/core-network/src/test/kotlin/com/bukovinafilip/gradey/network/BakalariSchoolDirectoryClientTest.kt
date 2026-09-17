package com.bukovinafilip.gradey.network

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class BakalariSchoolDirectoryClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: BakalariSchoolDirectoryClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        client = BakalariSchoolDirectoryClient(serviceURL = server.url("api/v1/municipality").toString())
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `municipalities decode from the Bakalari directory endpoint`() = runTest {
        server.enqueue(jsonResponse("""[{"name":"Praha","schoolCount":12}]"""))

        val municipalities = client.fetchMunicipalities()
        val request = server.takeRequest()

        assertThat(municipalities).hasSize(1)
        assertThat(municipalities.single().name).isEqualTo("Praha")
        assertThat(municipalities.single().schoolCount).isEqualTo(12)
        assertThat(request.path).isEqualTo("/api/v1/municipality")
        assertThat(request.getHeader("Accept")).isEqualTo("application/json")
    }

    @Test
    fun `town request encodes its query and drops unusable schools`() = runTest {
        server.enqueue(
            jsonResponse(
                """
                {
                  "name":" České Budějovice ",
                  "schools":[
                    {"id":"valid","name":" School One ","schoolUrl":" https://school.example.cz "},
                    {"id":"blank-name","name":" ","schoolUrl":"https://blank.example.cz"},
                    {"id":"blank-url","name":"School Two","schoolUrl":" "}
                  ]
                }
                """.trimIndent(),
            ),
        )

        val schools = client.fetchSchools("České Budějovice")
        val request = server.takeRequest()

        assertThat(request.requestUrl?.queryParameter("name")).isEqualTo("České Budějovice")
        assertThat(schools).containsExactly(
            com.bukovinafilip.gradey.model.SchoolDirectorySchool(
                id = "valid",
                name = "School One",
                town = "České Budějovice",
                schoolURL = "https://school.example.cz",
            ),
        )
    }

    @Test
    fun `HTTP body is not exposed by directory error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(503).setBody("<html>private proxy details</html>"))

        val failure = runCatching { client.fetchMunicipalities() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(SchoolDirectoryNetworkException::class.java)
        failure as SchoolDirectoryNetworkException
        assertThat(failure.statusCode).isEqualTo(503)
        assertThat(failure.message).isEqualTo("School directory request failed (HTTP 503).")
        assertThat(failure.message).doesNotContain("private proxy")
    }

    private fun jsonResponse(body: String): MockResponse = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)
}
