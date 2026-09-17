package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test

class StravaCZNetworkClientTest {
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
    fun `client sends iOS-compatible login menu order save rollback and logout contracts`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("ok"))
        server.enqueue(jsonResponse(loginResponse))
        server.enqueue(jsonResponse(menuResponse))
        repeat(3) { server.enqueue(jsonResponse("""{"konto":"60.00"}""")) }
        server.enqueue(MockResponse().setResponseCode(204))
        val client = client()

        val session = client.login("1234", "student", "secret")
        val menu = client.fetchMenu(session)
        assertThat(client.changeMealOrder(session, 7, true)).isEqualTo(60.0)
        assertThat(client.saveOrders(session)).isEqualTo(60.0)
        assertThat(client.cancelOrderChanges(session)).isEqualTo(60.0)
        client.logout(session)

        val initialize = server.takeRequest()
        val login = server.takeRequest()
        val menuRequest = server.takeRequest()
        val change = server.takeRequest()
        val save = server.takeRequest()
        val rollback = server.takeRequest()
        val logout = server.takeRequest()
        val loginBody = login.jsonBody()
        val menuBody = menuRequest.jsonBody()
        val changeBody = change.jsonBody()
        assertThat(initialize.path).isEqualTo("/en/prihlasit-se?jidelna")
        assertThat(login.path).isEqualTo("/api/login")
        assertThat(login.getHeader("Content-Type")).startsWith("text/plain")
        assertThat(loginBody.jsonPrimitive("cislo")).isEqualTo("1234")
        assertThat(menuRequest.path).isEqualTo("/api/objednavky")
        assertThat(menuBody.jsonPrimitive("s5url")).contains("strava.cz")
        assertThat(change.path).isEqualTo("/api/pridejJidloS5")
        assertThat(changeBody.jsonPrimitive("veta")).isEqualTo("7")
        assertThat(changeBody.jsonPrimitive("pocet")).isEqualTo("1")
        assertThat(save.path).isEqualTo("/api/saveOrders")
        assertThat(rollback.path).isEqualTo("/api/nactiVlastnostiPA")
        assertThat(logout.path).isEqualTo("/api/logOut")
        assertThat(menu.days.single().meals.single().type).isEqualTo(StravaCZMealType.MAIN)
    }

    @Test
    fun `http errors classify insufficient balance and authentication`() = runTest {
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"number":35,"message":"low balance"}"""))
        server.enqueue(MockResponse().setResponseCode(403).setBody("""{"message":"expired"}"""))
        val client = client()

        val lowBalance = runCatching { client.fetchMenu(session()) }.exceptionOrNull() as StravaCZException
        val expired = runCatching { client.fetchMenu(session()) }.exceptionOrNull() as StravaCZException

        assertThat(lowBalance.kind).isEqualTo(StravaCZErrorKind.INSUFFICIENT_BALANCE)
        assertThat(lowBalance.message).isEqualTo("low balance")
        assertThat(expired.kind).isEqualTo(StravaCZErrorKind.AUTHENTICATION)
    }

    private fun client() = StravaCZNetworkClient(baseURL = server.url("/").toString().trimEnd('/'))

    private fun session() = StravaCZStoredSession(
        sessionID = "session",
        serviceURL = "https://wss5.strava.cz/service",
        canteenNumber = "1234",
        username = "student",
    )

    private fun jsonResponse(body: String) = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)

    private fun okhttp3.mockwebserver.RecordedRequest.jsonBody() =
        GradeyJson.parseToJsonElement(body.readUtf8()).jsonObject

    private fun kotlinx.serialization.json.JsonObject.jsonPrimitive(key: String) = getValue(key).jsonPrimitive.content

    private val loginResponse =
        """{"sid":"session","s5url":"https://wss5.strava.cz/service","cislo":"1234","jmeno":"student","uzivatel":{"jmeno":"Student","konto":"100","mena":"Kč"}}"""

    private val menuResponse =
        """{"table0":[{"datum":"15.09.2025","druh_popis":"Oběd 1","nazev":"Meal","delsiPopis":"Meal detail","alergeny":[["01","Grain"]],"omezeniObj":{"den":""},"pocet":0,"veta":7,"cena":40}]}"""
}
