package com.bukovinafilip.gradey.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.bukovinafilip.gradey.domain.WearLessonSelector
import com.bukovinafilip.gradey.model.GradeyWearLessonSelection
import com.bukovinafilip.gradey.model.GradeyWearTimetable
import com.bukovinafilip.gradey.model.GradeyWearTimetableDay
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import java.time.LocalDate
import java.time.ZoneId

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                WearGradeyScreen(sampleTimetable())
            }
        }
    }

    private fun sampleTimetable(): GradeyWearTimetable {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val dayStart = today.atStartOfDay(zone).toInstant().toEpochMilli()
        val start = today.atTime(8, 55).atZone(zone).toInstant().toEpochMilli()
        val end = today.atTime(9, 40).atZone(zone).toInstant().toEpochMilli()
        return GradeyWearTimetable(
            weekStart = today.toString(),
            cachedAtEpochMillis = System.currentTimeMillis(),
            days = listOf(
                GradeyWearTimetableDay(
                    id = today.toString(),
                    date = today.toString(),
                    dayStartEpochMillis = dayStart,
                    weekdayTitle = "Today",
                    detailTitle = "Demo timetable",
                    isToday = true,
                    isSchoolDay = true,
                    lessons = listOf(
                        GradeyWearTimetableLesson(
                            id = "demo-wear-lesson",
                            dayStartEpochMillis = dayStart,
                            startEpochMillis = start,
                            endEpochMillis = end,
                            subjectName = "Mathematics",
                            subjectAbbrev = "M",
                            timeRange = "08:55-09:40",
                            room = "12",
                        ),
                    ),
                ),
            ),
        )
    }
}

@Composable
private fun WearGradeyScreen(timetable: GradeyWearTimetable) {
    val selection = WearLessonSelector.select(timetable)
    ScalingLazyColumn {
        item {
            Text("Gradey", style = MaterialTheme.typography.title1)
        }
        item {
            when (selection) {
                is GradeyWearLessonSelection.Lesson -> {
                    Text(selection.lesson.detailTitle, style = MaterialTheme.typography.title2)
                    Text(selection.lesson.timeRange ?: "")
                    Text(selection.lesson.room?.let { "Room $it" } ?: "")
                }

                GradeyWearLessonSelection.NoTimetable -> Text("Sync timetable")
                GradeyWearLessonSelection.NoLessons -> Text("Done for today")
                GradeyWearLessonSelection.Stale -> Text("Open phone to refresh")
            }
        }
        item {
            Button(onClick = {}) {
                Text("Refresh")
            }
        }
    }
}

