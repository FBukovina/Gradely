package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDate

class TodayMealsTest {
    private val today = LocalDate.of(2026, 8, 30)

    @Test
    fun `connected session shows the first ordered meal for today`() {
        val ordered = meal(id = 2, ordered = true)
        val menu = menu(
            day(
                date = today.toString(),
                meals = listOf(meal(id = 1, ordered = false), ordered, meal(id = 3, ordered = true)),
            ),
        )

        val state = TodayMeals.resolve(isConnected = true, menu = menu, today = today)

        assertThat(state).isEqualTo(TodayMealState.Ordered(ordered))
    }

    @Test
    fun `connected session without an ordered meal today reports no meal`() {
        val menu = menu(
            day(date = today.minusDays(1).toString(), meals = listOf(meal(1, ordered = true))),
            day(date = today.toString(), meals = listOf(meal(2, ordered = false))),
        )

        val state = TodayMeals.resolve(isConnected = true, menu = menu, today = today)

        assertThat(state).isEqualTo(TodayMealState.NoOrderedMeal)
    }

    @Test
    fun `connected session without a loaded menu still reports no meal`() {
        val state = TodayMeals.resolve(isConnected = true, menu = null, today = today)

        assertThat(state).isEqualTo(TodayMealState.NoOrderedMeal)
    }

    @Test
    fun `missing session never exposes a cached ordered meal`() {
        val menu = menu(day(date = today.toString(), meals = listOf(meal(1, ordered = true))))

        val state = TodayMeals.resolve(isConnected = false, menu = menu, today = today)

        assertThat(state).isEqualTo(TodayMealState.NotConnected)
    }

    private fun menu(vararg days: StravaCZMenuDay) = StravaCZMenu(days.toList())

    private fun day(date: String, meals: List<StravaCZMeal>) = StravaCZMenuDay(
        id = date,
        title = date,
        date = date,
        meals = meals,
    )

    private fun meal(id: Int, ordered: Boolean) = StravaCZMeal(
        id = id,
        dateKey = "2026-08-30",
        name = "Lunch $id",
        ordered = ordered,
    )
}
