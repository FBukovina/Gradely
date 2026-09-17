package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import java.time.LocalDate

sealed interface TodayMealState {
    data class Ordered(val meal: StravaCZMeal) : TodayMealState

    data object NoOrderedMeal : TodayMealState

    data object NotConnected : TodayMealState
}

object TodayMeals {
    fun resolve(
        isConnected: Boolean,
        menu: StravaCZMenu?,
        today: LocalDate,
    ): TodayMealState {
        if (!isConnected) return TodayMealState.NotConnected

        val orderedMeal = menu
            ?.days
            ?.firstOrNull { it.date == today.toString() }
            ?.meals
            ?.firstOrNull(StravaCZMeal::ordered)

        return orderedMeal?.let(TodayMealState::Ordered) ?: TodayMealState.NoOrderedMeal
    }
}
