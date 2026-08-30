package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay

object StravaCZMenuMapper {
    fun demoMenu(): StravaCZMenu = com.bukovinafilip.gradey.domain.DemoData.stravaMenu

    fun normalize(mealsByDay: Map<String, List<StravaCZMeal>>): StravaCZMenu =
        StravaCZMenu(
            days = mealsByDay.map { (date, meals) ->
                StravaCZMenuDay(
                    id = date,
                    title = date,
                    date = date,
                    meals = meals,
                )
            },
        )
}

