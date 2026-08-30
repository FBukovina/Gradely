package com.bukovinafilip.gradey.widgets

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.bukovinafilip.gradey.domain.NextLessonSelector
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSelection
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import java.time.LocalDate
import java.time.ZoneId

class NextLessonWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextLessonWidget()
}

class NextLessonWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            NextLessonWidgetContent(selection = NextLessonSelector.select(sampleSnapshot()))
        }
    }

    private fun sampleSnapshot(): NextLessonWidgetSnapshot {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val start = today.atTime(8, 55).atZone(zone).toInstant().toEpochMilli()
        val end = today.atTime(9, 40).atZone(zone).toInstant().toEpochMilli()
        return NextLessonWidgetSnapshot(
            cachedAtEpochMillis = System.currentTimeMillis(),
            lessons = listOf(
                NextLessonWidgetLesson(
                    id = "demo-next",
                    dayStartEpochMillis = today.atStartOfDay(zone).toInstant().toEpochMilli(),
                    startEpochMillis = start,
                    endEpochMillis = end,
                    subjectName = "Mathematics",
                    subjectAbbrev = "M",
                    timeRange = "08:55-09:40",
                    room = "12",
                ),
            ),
        )
    }
}

@Composable
private fun NextLessonWidgetContent(selection: NextLessonWidgetSelection) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ColorProvider(Color(0xFFEAF8F3)))
            .cornerRadius(16.dp)
            .padding(14.dp),
    ) {
        when (selection) {
            is NextLessonWidgetSelection.Lesson -> {
                Text(
                    text = if (selection.timing.name == "CURRENT") "Now" else "Next",
                    style = TextStyle(color = ColorProvider(Color(0xFF137C68)), fontWeight = FontWeight.Bold),
                )
                Spacer(GlanceModifier.height(4.dp))
                Text(
                    text = selection.lesson.detailTitle,
                    style = TextStyle(color = ColorProvider(Color(0xFF031F1B)), fontWeight = FontWeight.Bold),
                    modifier = GlanceModifier.fillMaxWidth(),
                )
                Text(
                    text = listOfNotNull(selection.lesson.timeRange, selection.lesson.room).joinToString(" - "),
                    style = TextStyle(color = ColorProvider(Color(0xFF24534B))),
                )
            }

            NextLessonWidgetSelection.NoSnapshot -> EmptyWidget("Open Gradey", "Load timetable")
            NextLessonWidgetSelection.NoLessons -> EmptyWidget("No lessons", "Open Gradey")
            NextLessonWidgetSelection.Stale -> EmptyWidget("Refresh timetable", "Open Gradey")
        }
    }
}

@Composable
private fun EmptyWidget(title: String, subtitle: String) {
    Text(title, style = TextStyle(color = ColorProvider(Color(0xFF031F1B)), fontWeight = FontWeight.Bold))
    Spacer(GlanceModifier.height(4.dp))
    Text(subtitle, style = TextStyle(color = ColorProvider(Color(0xFF24534B))))
}
