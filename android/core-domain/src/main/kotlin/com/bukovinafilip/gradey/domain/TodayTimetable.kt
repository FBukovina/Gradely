package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.Duration
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

enum class TodayTimetableState {
    UNAVAILABLE,
    WEEKEND,
    HOLIDAY,
    EMPTY,
    BEFORE_SCHOOL,
    CURRENT,
    BETWEEN_LESSONS,
    AFTER_SCHOOL,
}

data class TodayTimetableSummary(
    val state: TodayTimetableState,
    val currentLesson: ScheduledLesson? = null,
    val nextLesson: ScheduledLesson? = null,
    val changedLessons: List<ScheduledLesson> = emptyList(),
    val minutesRemainingInCurrent: Int? = null,
    val minutesUntilNext: Int? = null,
    val dayDescription: String? = null,
) {
    val hasChanges: Boolean get() = changedLessons.isNotEmpty()
}

object TodayTimetableSummaries {
    private val PragueZone = ZoneId.of("Europe/Prague")
    private val HourFormatter = DateTimeFormatter.ofPattern("H:mm")

    fun resolve(
        timetable: TimetableWeek?,
        now: ZonedDateTime = ZonedDateTime.now(PragueZone),
    ): TodayTimetableSummary {
        val pragueNow = now.withZoneSameInstant(PragueZone)
        val today = pragueNow.toLocalDate()
        val day = timetable?.todayDay(today)

        if (day == null) {
            return TodayTimetableSummary(
                state = if (today.dayOfWeek.value >= 6 && timetable?.covers(today) == true) {
                    TodayTimetableState.WEEKEND
                } else {
                    TodayTimetableState.UNAVAILABLE
                },
            )
        }

        val description = day.dayDescription.trim().takeIf(String::isNotEmpty)
        when (day.dayType.trim().lowercase()) {
            "weekend" -> return TodayTimetableSummary(
                state = TodayTimetableState.WEEKEND,
                dayDescription = description,
            )

            "celebration", "holiday", "directorday" -> return TodayTimetableSummary(
                state = TodayTimetableState.HOLIDAY,
                dayDescription = description,
            )
        }

        val changedLessons = day.lessons.filter { it.changeKind != LessonChangeKind.NONE }
        val timedLessons = day.lessons.mapNotNull { lesson ->
            val start = lesson.hour.beginTime.asLocalTime() ?: return@mapNotNull null
            val end = lesson.hour.endTime.asLocalTime() ?: return@mapNotNull null
            if (end.isBefore(start)) return@mapNotNull null
            TimedLesson(
                lesson = lesson,
                start = today.atTime(start).atZone(PragueZone),
                end = today.atTime(end).atZone(PragueZone),
            )
        }.sortedBy(TimedLesson::start)
        val activeLessons = timedLessons.filter { it.lesson.changeKind != LessonChangeKind.CANCELED }

        if (activeLessons.isEmpty()) {
            return TodayTimetableSummary(
                state = if (day.lessons.isEmpty()) TodayTimetableState.EMPTY else TodayTimetableState.AFTER_SCHOOL,
                changedLessons = changedLessons,
                dayDescription = description,
            )
        }

        val current = activeLessons.firstOrNull { !pragueNow.isBefore(it.start) && !pragueNow.isAfter(it.end) }
        if (current != null) {
            return TodayTimetableSummary(
                state = TodayTimetableState.CURRENT,
                currentLesson = current.lesson,
                nextLesson = activeLessons.firstOrNull { it.start.isAfter(current.end) }?.lesson,
                changedLessons = changedLessons,
                minutesRemainingInCurrent = positiveMinutes(pragueNow, current.end),
                dayDescription = description,
            )
        }

        val next = activeLessons.firstOrNull { it.start.isAfter(pragueNow) }
        if (next != null) {
            return TodayTimetableSummary(
                state = if (next === activeLessons.first()) {
                    TodayTimetableState.BEFORE_SCHOOL
                } else {
                    TodayTimetableState.BETWEEN_LESSONS
                },
                nextLesson = next.lesson,
                changedLessons = changedLessons,
                minutesUntilNext = positiveMinutes(pragueNow, next.start),
                dayDescription = description,
            )
        }

        return TodayTimetableSummary(
            state = TodayTimetableState.AFTER_SCHOOL,
            changedLessons = changedLessons,
            dayDescription = description,
        )
    }

    private fun TimetableWeek.todayDay(today: LocalDate): ScheduledDay? =
        days.firstOrNull { it.date.asLocalDate() == today }
            ?: days.firstOrNull { it.date.isNullOrBlank() && it.isToday }

    private fun TimetableWeek.covers(date: LocalDate): Boolean = weekStart.asLocalDate()?.let { start ->
        !date.isBefore(start) && !date.isAfter(start.plusDays(6))
    } == true

    private fun String?.asLocalDate(): LocalDate? =
        this?.trim()?.takeIf(String::isNotEmpty)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    private fun String.asLocalTime(): LocalTime? =
        runCatching { LocalTime.parse(trim(), HourFormatter) }.getOrNull()

    private fun positiveMinutes(start: ZonedDateTime, end: ZonedDateTime): Int =
        ((Duration.between(start, end).toMillis().coerceAtLeast(0) + 59_999) / 60_000).toInt()

    private data class TimedLesson(
        val lesson: ScheduledLesson,
        val start: ZonedDateTime,
        val end: ZonedDateTime,
    )
}
