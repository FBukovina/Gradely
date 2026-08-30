package com.bukovinafilip.gradey.widgets

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.action.clickable
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
import com.bukovinafilip.gradey.data.GradeyCacheOwner
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetSelection
import com.bukovinafilip.gradey.model.NextLessonWidgetTiming
import kotlinx.coroutines.CancellationException

class NextLessonWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextLessonWidget()
}

class NextLessonWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = try {
            (context.applicationContext as? GradeyCacheOwner)?.gradeyCache?.loadNextLessonSnapshot()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        provideContent {
            NextLessonWidgetContent(selection = NextLessonSelector.select(snapshot))
        }
    }
}

suspend fun updateNextLessonWidgets(context: Context) {
    NextLessonWidget().updateAll(context)
}

@Composable
private fun NextLessonWidgetContent(selection: NextLessonWidgetSelection) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .clickable(actionStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("gradey://timetable"))))
            .background(ColorProvider(Color(0xFFEAF8F3)))
            .cornerRadius(16.dp)
            .padding(14.dp),
    ) {
        when (selection) {
            is NextLessonWidgetSelection.Lesson -> {
                val status = lessonStatus(selection)
                Text(
                    text = status,
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

private fun lessonStatus(selection: NextLessonWidgetSelection.Lesson): String {
    val timing = if (selection.timing == NextLessonWidgetTiming.CURRENT) "Now" else "Next"
    val change = when (selection.lesson.changeKind) {
        NextLessonWidgetChangeKind.NONE -> null
        NextLessonWidgetChangeKind.CANCELED -> "Canceled"
        NextLessonWidgetChangeKind.SUBSTITUTION -> "Substitution"
        NextLessonWidgetChangeKind.ROOM_CHANGED -> "Room changed"
        NextLessonWidgetChangeKind.ADDED -> "Added"
    }
    return listOfNotNull(timing, change).joinToString(" · ")
}

@Composable
private fun EmptyWidget(title: String, subtitle: String) {
    Text(title, style = TextStyle(color = ColorProvider(Color(0xFF031F1B)), fontWeight = FontWeight.Bold))
    Spacer(GlanceModifier.height(4.dp))
    Text(subtitle, style = TextStyle(color = ColorProvider(Color(0xFF24534B))))
}
