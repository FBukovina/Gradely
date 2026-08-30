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
        val strings = WidgetStrings.from(context)
        provideContent {
            NextLessonWidgetContent(
                selection = NextLessonSelector.select(snapshot),
                strings = strings,
            )
        }
    }
}

suspend fun updateNextLessonWidgets(context: Context) {
    NextLessonWidget().updateAll(context)
}

@Composable
private fun NextLessonWidgetContent(
    selection: NextLessonWidgetSelection,
    strings: WidgetStrings,
) {
    val localizedLessonStatus = (selection as? NextLessonWidgetSelection.Lesson)?.let {
        lessonStatus(strings, it)
    }
    val emptyCopy = when (selection) {
        NextLessonWidgetSelection.NoSnapshot -> strings.openGradey to strings.loadTimetable
        NextLessonWidgetSelection.NoLessons -> strings.noLessons to strings.openGradey
        NextLessonWidgetSelection.Stale -> strings.refreshTimetable to strings.openGradey
        is NextLessonWidgetSelection.Lesson -> null
    }
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
                Text(
                    text = localizedLessonStatus.orEmpty(),
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

            NextLessonWidgetSelection.NoSnapshot,
            NextLessonWidgetSelection.NoLessons,
            NextLessonWidgetSelection.Stale,
            -> EmptyWidget(emptyCopy?.first.orEmpty(), emptyCopy?.second.orEmpty())
        }
    }
}

private fun lessonStatus(strings: WidgetStrings, selection: NextLessonWidgetSelection.Lesson): String {
    val timing = if (selection.timing == NextLessonWidgetTiming.CURRENT) strings.now else strings.next
    val change = when (selection.lesson.changeKind) {
        NextLessonWidgetChangeKind.NONE -> null
        NextLessonWidgetChangeKind.CANCELED -> strings.canceled
        NextLessonWidgetChangeKind.SUBSTITUTION -> strings.substitution
        NextLessonWidgetChangeKind.ROOM_CHANGED -> strings.roomChanged
        NextLessonWidgetChangeKind.ADDED -> strings.added
    }
    return listOfNotNull(timing, change).joinToString(" · ")
}

private data class WidgetStrings(
    val openGradey: String,
    val loadTimetable: String,
    val noLessons: String,
    val refreshTimetable: String,
    val now: String,
    val next: String,
    val canceled: String,
    val substitution: String,
    val roomChanged: String,
    val added: String,
) {
    companion object {
        fun from(context: Context) = WidgetStrings(
            openGradey = context.getString(R.string.widget_open_gradey),
            loadTimetable = context.getString(R.string.widget_load_timetable),
            noLessons = context.getString(R.string.widget_no_lessons),
            refreshTimetable = context.getString(R.string.widget_refresh_timetable),
            now = context.getString(R.string.widget_now),
            next = context.getString(R.string.widget_next),
            canceled = context.getString(R.string.widget_canceled),
            substitution = context.getString(R.string.widget_substitution),
            roomChanged = context.getString(R.string.widget_room_changed),
            added = context.getString(R.string.widget_added),
        )
    }
}

@Composable
private fun EmptyWidget(title: String, subtitle: String) {
    Text(title, style = TextStyle(color = ColorProvider(Color(0xFF031F1B)), fontWeight = FontWeight.Bold))
    Spacer(GlanceModifier.height(4.dp))
    Text(subtitle, style = TextStyle(color = ColorProvider(Color(0xFF24534B))))
}
