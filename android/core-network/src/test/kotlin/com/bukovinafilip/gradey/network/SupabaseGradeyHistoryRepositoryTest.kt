package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.GradeHistoryEventType
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class SupabaseGradeyHistoryRepositoryTest {
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
    fun `history request uses active linked account range and Gradey authorization`() = runTest {
        server.enqueue(jsonResponse(historyResponse))

        val response = repository().gradeHistory(accountID = " school ", days = 400)
        val request = server.takeRequest()
        val body = GradeyJson.parseToJsonElement(request.body.readUtf8()).jsonObject

        assertThat(request.method).isEqualTo("POST")
        assertThat(request.path).isEqualTo("/functions/v1/grade-history")
        assertThat(request.getHeader("apikey")).isEqualTo("anon-key")
        assertThat(request.getHeader("Authorization")).isEqualTo("Bearer auth-access")
        assertThat(body.getValue("linked_account_id").jsonPrimitive.content).isEqualTo("school")
        assertThat(body.getValue("days").jsonPrimitive.content).isEqualTo("400")
        assertThat(response.events.map { it.id }).containsExactly("first", "latest").inOrder()
        assertThat(response.events.last().eventType).isEqualTo(GradeHistoryEventType.CHANGED)
        assertThat(response.events.last().averageValue).isEqualTo(1.8)
        assertThat(response.recentNewMarkEvents).hasSize(1)
        assertThat(response.recentNewMarkEvents.single().id).isEqualTo("new-mark")
        assertThat(response.recentNewMarkEvents.single().subjectAbbrev).isEqualTo("M")
    }

    @Test
    fun `missing events decode as empty and omitted account lets backend choose the active account`() = runTest {
        server.enqueue(jsonResponse("""{"recentNewMarkEvents":[{"future":"shape"}]}"""))

        val response = repository().gradeHistory(accountID = null, days = 90)
        val body = GradeyJson.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject

        assertThat(response.events).isEmpty()
        assertThat(response.recentNewMarkEvents).isEmpty()
        assertThat(body.containsKey("linked_account_id")).isFalse()
        assertThat(body.getValue("days").jsonPrimitive.content).isEqualTo("90")
    }

    @Test
    fun `server failures become bounded history errors`() = runTest {
        server.enqueue(MockResponse().setResponseCode(503).setBody("<html>private diagnostic</html>"))

        val failure = runCatching { repository().gradeHistory("school", 400) }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyFunctionException::class.java)
        failure as GradeyFunctionException
        assertThat(failure.function).isEqualTo("grade-history")
        assertThat(failure.statusCode).isEqualTo(503)
        assertThat(failure.message).doesNotContain("private diagnostic")
    }

    private fun repository() = SupabaseGradeyHistoryRepository(
        configuration = SupabaseConfiguration(server.url("/").toString(), "anon-key"),
        authRepository = FakeHistoryAuthRepository(),
    )

    private fun jsonResponse(body: String) = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)

    private val historyResponse =
        """
        {
          "events":[
            {
              "id":"first",
              "linked_account_id":"school",
              "provider":"bakalari",
              "subject_id":"math",
              "subject_abbrev":"M",
              "subject_name":"Mathematics",
              "average_value":2.1,
              "mark_count":2,
              "average_delta":null,
              "mark_count_delta":0,
              "event_type":"baseline",
              "captured_at":"2026-08-01T10:00:00Z"
            },
            {
              "id":"latest",
              "linked_account_id":"school",
              "provider":"bakalari",
              "subject_id":"math",
              "subject_abbrev":"M",
              "subject_name":"Mathematics",
              "average_value":1.8,
              "mark_count":4,
              "average_delta":-0.3,
              "mark_count_delta":2,
              "event_type":"changed",
              "captured_at":"2026-08-30T10:00:00Z"
            }
          ],
          "recentNewMarkEvents":[
            {
              "id":"new-mark",
              "linked_account_id":"school",
              "provider":"bakalari",
              "subject_id":"math",
              "subject_abbrev":"M",
              "subject_name":"Mathematics",
              "mark_text":"1",
              "fingerprint":{"future":"shape"},
              "created_at":"2026-08-30T10:05:00Z",
              "delivered_at":null
            }
          ]
        }
        """.trimIndent()
}

private class FakeHistoryAuthRepository : GradeyAuthRepository {
    private val session = GradeyAuthSession(
        accessToken = "auth-access",
        refreshToken = "auth-refresh",
        account = GradeyAccount("gradey-user"),
    )

    override suspend fun bootstrapSession() = session
    override suspend fun validSession() = session
    override suspend fun refreshAccount() = session.account
    override suspend fun updateFullName(fullName: String) = session.account.copy(fullName = fullName)
    override suspend fun signInWithGoogle(idToken: String, accessToken: String?, fullName: String?) = session
    override suspend fun signOut() = Unit
}
