package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZOrderType
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class StravaCZResponseMapperTest {
    @Test
    fun `login decodes flexible profile values and validates service host`() {
        val session = StravaCZResponseMapper.login(
            """
            {
              "sid":"session",
              "s5url":"https://wss5.strava.cz/WSStravne5_15/WSStravne5.svc",
              "cislo":1234,
              "jmeno":"student",
              "uzivatel":{
                "jmeno":"Student One",
                "email":"student@example.com",
                "konto":"100,50",
                "mena":"Kč",
                "nazevJidelny":"Demo jídelna"
              }
            }
            """.trimIndent(),
            nowEpochMillis = 42,
        )

        assertThat(session.sessionID).isEqualTo("session")
        assertThat(session.canteenNumber).isEqualTo("1234")
        assertThat(session.displayName).isEqualTo("Student One")
        assertThat(session.balance).isEqualTo(100.5)
        assertThat(session.savedAtEpochMillis).isEqualTo(42)
    }

    @Test
    fun `menu filters structural rows and maps dates types restrictions allergens price and ordering`() {
        val menu = StravaCZResponseMapper.menu(
            """
            {
              "ignored": [{"datum":"15.09.2025"}],
              "table0": [
                {
                  "datum":"15.09.2025", "druh_popis":"Polévka", "nazev":"Vývar",
                  "delsiPopis":"Vývar se zeleninou", "alergeny":[["01","Obiloviny"]],
                  "omezeniObj":{"den":""}, "pocet":"0", "veta":"75", "cena":"0"
                },
                {
                  "datum":"15.09.2025", "druh_popis":"Oběd 2", "nazev":"Rizoto",
                  "delsiPopis":"Zeleninové rizoto", "alergeny":[["07","Mléko"]],
                  "omezeniObj":{"den":"T"}, "pocet":1, "veta":2, "cena":"42,50"
                },
                {
                  "datum":"15.09.2025", "druh_popis":"Oběd 1", "nazev":"Řízek",
                  "delsiPopis":"Kuřecí řízek", "alergeny":[],
                  "omezeniObj":{"den":"CO"}, "pocet":0, "veta":1, "cena":45
                },
                {
                  "datum":"15.09.2025", "druh_popis":"Info", "nazev":"Info",
                  "delsiPopis":"metadata", "alergeny":[], "omezeniObj":{"den":""},
                  "pocet":0, "veta":90, "cena":0
                },
                {
                  "datum":"15.09.2025", "druh_popis":"Oběd", "nazev":"Blocked",
                  "delsiPopis":"Blocked", "alergeny":[], "omezeniObj":{"den":"VP"},
                  "pocet":0, "veta":91, "cena":0
                }
              ],
              "table1": [
                {
                  "datum":"16-09-2025", "druh_popis":"Snack", "nazev":"Fruit",
                  "delsiPopis":"Fruit bowl", "alergeny":[[12,"Seeds"]],
                  "omezeniObj":{"den":""}, "pocet":0, "veta":4, "cena":10
                }
              ]
            }
            """.trimIndent(),
        )

        assertThat(menu.days.map { it.date }).containsExactly("2025-09-15", "2025-09-16").inOrder()
        val firstDay = menu.days.first()
        assertThat(firstDay.ordered).isTrue()
        assertThat(firstDay.meals.map { it.id }).containsExactly(75, 1, 2).inOrder()
        assertThat(firstDay.meals[0].type).isEqualTo(StravaCZMealType.SOUP)
        assertThat(firstDay.meals[1].orderType).isEqualTo(StravaCZOrderType.RESTRICTED)
        assertThat(firstDay.meals[1].canModify).isFalse()
        assertThat(firstDay.meals[2].orderType).isEqualTo(StravaCZOrderType.OPTIONAL)
        assertThat(firstDay.meals[2].price).isEqualTo(42.5)
        assertThat(firstDay.meals[2].allergenText).isEqualTo("07 Mléko")
        assertThat(firstDay.orderedMainMeal?.id).isEqualTo(2)
    }

    @Test
    fun `malformed login and menu payloads fail safely`() {
        val unsafe = runCatching {
            StravaCZResponseMapper.login(
                """{"sid":"s","s5url":"https://evil.example","cislo":"1","jmeno":"u","uzivatel":{}}""",
            )
        }.exceptionOrNull() as StravaCZException
        val malformed = runCatching { StravaCZResponseMapper.menu("not json") }.exceptionOrNull() as StravaCZException

        assertThat(unsafe.kind).isEqualTo(StravaCZErrorKind.INVALID_RESPONSE)
        assertThat(malformed.kind).isEqualTo(StravaCZErrorKind.DECODING)
    }
}
