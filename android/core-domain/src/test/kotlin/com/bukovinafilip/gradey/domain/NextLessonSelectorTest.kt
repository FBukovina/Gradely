package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSelection
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.NextLessonWidgetTiming
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class NextLessonSelectorTest {
    @Test
    fun selectsCurrentLessonBeforeUpcomingLesson() {
        val snapshot = NextLessonWidgetSnapshot(
            cachedAtEpochMillis = 1_000,
            lessons = listOf(
                lesson("current", start = 2_000, end = 3_000),
                lesson("upcoming", start = 4_000, end = 5_000),
            ),
        )

        val selection = NextLessonSelector.select(snapshot, nowEpochMillis = 2_500)

        assertThat(selection).isInstanceOf(NextLessonWidgetSelection.Lesson::class.java)
        val lesson = selection as NextLessonWidgetSelection.Lesson
        assertThat(lesson.lesson.id).isEqualTo("current")
        assertThat(lesson.timing).isEqualTo(NextLessonWidgetTiming.CURRENT)
    }

    @Test
    fun staleSnapshotWinsOverLessons() {
        val snapshot = NextLessonWidgetSnapshot(
            cachedAtEpochMillis = 1,
            lessons = listOf(lesson("old", 2, 3)),
        )

        assertThat(
            NextLessonSelector.select(snapshot, nowEpochMillis = 10, staleIntervalMillis = 5),
        ).isEqualTo(NextLessonWidgetSelection.Stale)
    }

    private fun lesson(id: String, start: Long, end: Long) = NextLessonWidgetLesson(
        id = id,
        dayStartEpochMillis = start,
        startEpochMillis = start,
        endEpochMillis = end,
        subjectAbbrev = id,
    )
}

