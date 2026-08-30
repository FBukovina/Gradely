package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableWeek
import com.google.common.truth.Truth.assertThat
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Test

class TodayTimetableSummariesTest {
    private val prague = ZoneId.of("Europe/Prague")

    @Test
    fun `selects current and next active lessons and rounds remaining minutes up`() {
        val summary = TodayTimetableSummaries.resolve(
            timetable = week(
                lessons = listOf(
                    lesson("math", "8:00", "8:45"),
                    lesson("czech", "8:55", "9:40"),
                ),
            ),
            now = at(8, 20, 1),
        )

        assertThat(summary.state).isEqualTo(TodayTimetableState.CURRENT)
        assertThat(summary.currentLesson?.id).isEqualTo("math")
        assertThat(summary.nextLesson?.id).isEqualTo("czech")
        assertThat(summary.minutesRemainingInCurrent).isEqualTo(25)
    }

    @Test
    fun `distinguishes before school from between lessons`() {
        val timetable = week(
            lessons = listOf(
                lesson("math", "8:00", "8:45"),
                lesson("czech", "8:55", "9:40"),
            ),
        )

        val before = TodayTimetableSummaries.resolve(timetable, at(7, 50))
        val between = TodayTimetableSummaries.resolve(timetable, at(8, 50))

        assertThat(before.state).isEqualTo(TodayTimetableState.BEFORE_SCHOOL)
        assertThat(before.nextLesson?.id).isEqualTo("math")
        assertThat(before.minutesUntilNext).isEqualTo(10)
        assertThat(between.state).isEqualTo(TodayTimetableState.BETWEEN_LESSONS)
        assertThat(between.nextLesson?.id).isEqualTo("czech")
        assertThat(between.minutesUntilNext).isEqualTo(5)
    }

    @Test
    fun `reports after school when all active lessons have ended`() {
        val summary = TodayTimetableSummaries.resolve(
            week(lessons = listOf(lesson("math", "8:00", "8:45"))),
            at(10, 0),
        )

        assertThat(summary.state).isEqualTo(TodayTimetableState.AFTER_SCHOOL)
        assertThat(summary.currentLesson).isNull()
        assertThat(summary.nextLesson).isNull()
    }

    @Test
    fun `reports empty work day`() {
        val summary = TodayTimetableSummaries.resolve(week(lessons = emptyList()), at(10, 0))

        assertThat(summary.state).isEqualTo(TodayTimetableState.EMPTY)
    }

    @Test
    fun `reports weekend when loaded week does not contain a weekend day`() {
        val timetable = TimetableWeek("2026-08-24", emptyList(), emptyList())
        val summary = TodayTimetableSummaries.resolve(timetable = timetable, now = at(10, 0, day = 29))

        assertThat(summary.state).isEqualTo(TodayTimetableState.WEEKEND)
    }

    @Test
    fun `weekend without timetable remains unavailable`() {
        val summary = TodayTimetableSummaries.resolve(timetable = null, now = at(10, 0, day = 29))

        assertThat(summary.state).isEqualTo(TodayTimetableState.UNAVAILABLE)
    }

    @Test
    fun `reports holiday and preserves its description`() {
        val summary = TodayTimetableSummaries.resolve(
            week(lessons = emptyList(), dayType = "Holiday", description = "Autumn holiday"),
            at(10, 0),
        )

        assertThat(summary.state).isEqualTo(TodayTimetableState.HOLIDAY)
        assertThat(summary.dayDescription).isEqualTo("Autumn holiday")
    }

    @Test
    fun `keeps changed lessons while canceled lessons cannot become current or next`() {
        val summary = TodayTimetableSummaries.resolve(
            week(
                lessons = listOf(
                    lesson("canceled", "8:00", "8:45", LessonChangeKind.CANCELED),
                    lesson("moved", "8:55", "9:40", LessonChangeKind.ROOM_CHANGED),
                ),
            ),
            at(8, 20),
        )

        assertThat(summary.state).isEqualTo(TodayTimetableState.BEFORE_SCHOOL)
        assertThat(summary.nextLesson?.id).isEqualTo("moved")
        assertThat(summary.changedLessons.map { it.id }).containsExactly("canceled", "moved").inOrder()
    }

    @Test
    fun `weekday without a matching today record is unavailable`() {
        val staleDay = day(date = "2026-08-29", lessons = emptyList())
        val timetable = TimetableWeek("2026-08-24", listOf(staleDay), emptyList())

        val summary = TodayTimetableSummaries.resolve(timetable, at(10, 0))

        assertThat(summary.state).isEqualTo(TodayTimetableState.UNAVAILABLE)
    }

    private fun week(
        lessons: List<ScheduledLesson>,
        dayType: String = "WorkDay",
        description: String = "",
    ) = TimetableWeek(
        weekStart = "2026-08-31",
        days = listOf(day(lessons = lessons, dayType = dayType, description = description)),
        hours = lessons.map(ScheduledLesson::hour),
    )

    private fun day(
        date: String = "2026-08-31",
        lessons: List<ScheduledLesson>,
        dayType: String = "WorkDay",
        description: String = "",
    ) = ScheduledDay(
        id = date,
        date = date,
        dayOfWeek = 1,
        dayDescription = description,
        dayType = dayType,
        lessons = lessons,
        isToday = true,
    )

    private fun lesson(
        id: String,
        begin: String,
        end: String,
        changeKind: LessonChangeKind = LessonChangeKind.NONE,
    ) = ScheduledLesson(
        id = id,
        hour = TimetableHour(id, id, begin, end),
        subjectName = id.replaceFirstChar(Char::uppercase),
        subjectAbbrev = id.take(3).uppercase(),
        teacherName = null,
        teacherAbbrev = null,
        roomAbbrev = "A1",
        roomName = null,
        groups = emptyList(),
        theme = null,
        hasHomework = false,
        changeKind = changeKind,
    )

    private fun at(hour: Int, minute: Int, second: Int = 0, day: Int = 31): ZonedDateTime =
        ZonedDateTime.of(2026, 8, day, hour, minute, second, 0, prague)
}
