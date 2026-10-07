package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableWeek
import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import org.junit.Test

class NextLessonSnapshotBuilderTest {
    @Test
    fun convertsLessonMetadataAndPragueTimes() {
        val week = week(
            "2026-08-31",
            day(
                date = "2026-09-01",
                dayOfWeek = 2,
                lessons = listOf(
                    lesson(
                        id = "math",
                        begin = "08:00",
                        end = "08:45",
                        subjectName = "Mathematics",
                        subjectAbbrev = "M",
                        teacherAbbrev = "AB",
                        roomAbbrev = "203",
                        changeKind = LessonChangeKind.ROOM_CHANGED,
                    ),
                ),
            ),
        )

        val result = NextLessonSnapshotBuilder.lessons(week).single()

        assertThat(result.id).isEqualTo("math")
        assertThat(result.subjectName).isEqualTo("Mathematics")
        assertThat(result.subjectAbbrev).isEqualTo("M")
        assertThat(result.teacher).isEqualTo("AB")
        assertThat(result.room).isEqualTo("203")
        assertThat(result.timeRange).isEqualTo("08:00-08:45")
        assertThat(result.changeKind).isEqualTo(NextLessonWidgetChangeKind.ROOM_CHANGED)
        assertThat(result.dayStartEpochMillis).isEqualTo(epoch("2026-09-01", 0, 0))
        assertThat(result.startEpochMillis).isEqualTo(epoch("2026-09-01", 8, 0))
        assertThat(result.endEpochMillis).isEqualTo(epoch("2026-09-01", 8, 45))
    }

    @Test
    fun fallsBackToWeekDayAndHandlesInvalidAndOvernightTimes() {
        val week = week(
            "2026-10-26",
            day(
                date = null,
                dayOfWeek = 3,
                lessons = listOf(
                    lesson("invalid", "25:00", "not-a-time"),
                    lesson("overnight", "23:30", "00:15"),
                ),
            ),
        )

        val result = NextLessonSnapshotBuilder.lessons(week).associateBy { it.id }

        assertThat(result.getValue("invalid").dayStartEpochMillis).isEqualTo(epoch("2026-10-28", 0, 0))
        assertThat(result.getValue("invalid").startEpochMillis).isNull()
        assertThat(result.getValue("invalid").endEpochMillis).isNull()
        assertThat(result.getValue("overnight").startEpochMillis).isEqualTo(epoch("2026-10-28", 23, 30))
        assertThat(result.getValue("overnight").endEpochMillis).isEqualTo(epoch("2026-10-29", 0, 15))
    }

    @Test
    fun refreshingAWeekReplacesOnlyThatWeekAndKeepsOtherWeeks() {
        val oldCurrentWeek = widgetLesson("old", "2026-08-31", 8)
        val nextWeek = widgetLesson("next", "2026-09-07", 8)
        val existing = NextLessonWidgetSnapshot(1, listOf(oldCurrentWeek, nextWeek))
        val refreshed = week(
            "2026-08-31",
            day("2026-08-31", 1, listOf(lesson("new", "09:00", "09:45"))),
        )

        val result = NextLessonSnapshotBuilder.update(existing, refreshed, cachedAtEpochMillis = 2)

        assertThat(result.cachedAtEpochMillis).isEqualTo(2)
        assertThat(result.lessons.map { it.id }).containsExactly("new", "next").inOrder()
    }

    private fun week(start: String, vararg days: ScheduledDay) = TimetableWeek(start, days.toList(), emptyList())

    private fun day(date: String?, dayOfWeek: Int, lessons: List<ScheduledLesson>) = ScheduledDay(
        id = date ?: "dow-$dayOfWeek",
        date = date,
        dayOfWeek = dayOfWeek,
        dayDescription = "",
        dayType = "WorkDay",
        lessons = lessons,
        isToday = false,
    )

    private fun lesson(
        id: String,
        begin: String,
        end: String,
        subjectName: String? = "Subject",
        subjectAbbrev: String? = "SUB",
        teacherAbbrev: String? = null,
        roomAbbrev: String? = null,
        changeKind: LessonChangeKind = LessonChangeKind.NONE,
    ) = ScheduledLesson(
        id = id,
        hour = TimetableHour(id = id, beginTime = begin, endTime = end),
        subjectName = subjectName,
        subjectAbbrev = subjectAbbrev,
        teacherName = null,
        teacherAbbrev = teacherAbbrev,
        roomAbbrev = roomAbbrev,
        roomName = null,
        groups = emptyList(),
        theme = null,
        hasHomework = false,
        changeKind = changeKind,
    )

    private fun widgetLesson(id: String, date: String, hour: Int) = NextLessonWidgetLesson(
        id = id,
        dayStartEpochMillis = epoch(date, 0, 0),
        startEpochMillis = epoch(date, hour, 0),
        endEpochMillis = epoch(date, hour, 45),
    )

    private fun epoch(date: String, hour: Int, minute: Int): Long =
        LocalDate.parse(date)
            .atTime(hour, minute)
            .atZone(TimetableDates.SchoolZone)
            .toInstant()
            .toEpochMilli()
}
