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

    @Test
    fun distinguishesMissingEmptyUpcomingAndFinishedSnapshots() {
        assertThat(NextLessonSelector.select(null, nowEpochMillis = 10))
            .isEqualTo(NextLessonWidgetSelection.NoSnapshot)
        assertThat(NextLessonSelector.select(NextLessonWidgetSnapshot(10, emptyList()), nowEpochMillis = 10))
            .isEqualTo(NextLessonWidgetSelection.NoLessons)

        val upcoming = NextLessonSelector.select(
            NextLessonWidgetSnapshot(10, listOf(lesson("next", 20, 30))),
            nowEpochMillis = 10,
        ) as NextLessonWidgetSelection.Lesson
        assertThat(upcoming.lesson.id).isEqualTo("next")
        assertThat(upcoming.timing).isEqualTo(NextLessonWidgetTiming.UPCOMING)

        assertThat(
            NextLessonSelector.select(
                NextLessonWidgetSnapshot(10, listOf(lesson("finished", 1, 5))),
                nowEpochMillis = 10,
            ),
        ).isEqualTo(NextLessonWidgetSelection.NoLessons)
    }

    @Test
    fun timelineDatesAreFutureUniqueSortedAndLimited() {
        val snapshot = NextLessonWidgetSnapshot(
            cachedAtEpochMillis = 1,
            lessons = listOf(
                lesson("second", 40, 50),
                lesson("first", 20, 40),
                lesson("past", 1, 5),
            ),
        )

        assertThat(NextLessonSelector.timelineDates(snapshot, afterEpochMillis = 10, limit = 2))
            .containsExactly(20L, 40L)
            .inOrder()
    }

    private fun lesson(id: String, start: Long, end: Long) = NextLessonWidgetLesson(
        id = id,
        dayStartEpochMillis = start,
        startEpochMillis = start,
        endEpochMillis = end,
        subjectAbbrev = id,
    )
}
