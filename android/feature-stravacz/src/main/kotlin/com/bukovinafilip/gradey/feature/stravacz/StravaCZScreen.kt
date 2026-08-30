package com.bukovinafilip.gradey.feature.stravacz

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun StravaCZScreen(
    menu: StravaCZMenu?,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier) {
        GradeyHero("StravaCZ", "Canteen menu, cached balances, and order-change hooks.")
        if (menu == null) {
            GradeySectionCard { Text("Connect your canteen account to load meals.") }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                items(menu.days, key = { it.id }) { day ->
                    GradeySectionCard(title = day.title) {
                        day.meals.forEach { meal ->
                            Text(meal.title, fontWeight = FontWeight.SemiBold)
                            meal.description?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            if (meal.ordered) {
                                AssistChip(
                                    onClick = {},
                                    label = { Text("Ordered") },
                                    leadingIcon = { Icon(Icons.Default.Restaurant, contentDescription = null) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

