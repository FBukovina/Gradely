package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class LessonLabelsTest {
    @Test
    fun `scheduled lesson exposes only real nonblank subject labels`() {
        assertThat(scheduled(subjectName = " Mathematics ", subjectAbbrev = " MAT ").title)
            .isEqualTo("MAT")
        assertThat(scheduled(subjectName = " Mathematics ", subjectAbbrev = " ").title)
            .isEqualTo("Mathematics")
        assertThat(scheduled(subjectName = null, subjectAbbrev = " ").title).isNull()
    }

    @Test
    fun `widget and Wear lessons keep missing labels null for localized consumers`() {
        val widget = NextLessonWidgetLesson(
            id = "widget",
            dayStartEpochMillis = 1L,
            subjectName = " ",
            subjectAbbrev = null,
        )
        val wear = GradeyWearTimetableLesson(
            id = "wear",
            dayStartEpochMillis = 1L,
            subjectName = null,
            subjectAbbrev = " ",
        )

        assertThat(widget.title).isNull()
        assertThat(widget.detailTitle).isNull()
        assertThat(wear.title).isNull()
        assertThat(wear.detailTitle).isNull()
    }

    @Test
    fun `widget and Wear title variants preserve their intended priority`() {
        val widget = NextLessonWidgetLesson(
            id = "widget",
            dayStartEpochMillis = 1L,
            subjectName = " Mathematics ",
            subjectAbbrev = " MAT ",
        )
        val wear = GradeyWearTimetableLesson(
            id = "wear",
            dayStartEpochMillis = 1L,
            subjectName = " Mathematics ",
            subjectAbbrev = " MAT ",
        )

        assertThat(widget.title).isEqualTo("MAT")
        assertThat(widget.detailTitle).isEqualTo("Mathematics")
        assertThat(wear.title).isEqualTo("MAT")
        assertThat(wear.detailTitle).isEqualTo("Mathematics")
    }

    private fun scheduled(subjectName: String?, subjectAbbrev: String?) = ScheduledLesson(
        id = "lesson",
        hour = TimetableHour(id = "1", caption = "1", beginTime = "08:00", endTime = "08:45"),
        subjectName = subjectName,
        subjectAbbrev = subjectAbbrev,
        teacherName = null,
        teacherAbbrev = null,
        roomAbbrev = null,
        roomName = null,
        groups = emptyList(),
        theme = null,
        hasHomework = false,
    )
}
