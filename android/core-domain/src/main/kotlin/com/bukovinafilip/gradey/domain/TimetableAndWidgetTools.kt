package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeyWearLessonSelection
import com.bukovinafilip.gradey.model.GradeyWearTimetable
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSelection
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.NextLessonWidgetTiming
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.DayOfWeek
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

object TimetableDates {
    private val ApiFormatter: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    val SchoolZone: ZoneId = ZoneId.of("Europe/Prague")

    fun today(clock: Clock = Clock.systemUTC()): LocalDate = LocalDate.now(clock.withZone(SchoolZone))

    fun todayString(clock: Clock = Clock.systemUTC()): String = apiDateString(today(clock))

    fun monday(date: LocalDate = today()): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun apiDateString(date: LocalDate): String = ApiFormatter.format(date)
}

object TimetableMapper {
    fun makeWeek(
        response: TimetableResponse,
        weekStart: String,
        today: String = TimetableDates.todayString(),
    ): TimetableWeek {
        val subjects = index(response.subjects)
        val teachers = index(response.teachers)
        val rooms = index(response.rooms)
        val groups = response.groups.associateBy { it.id }
        val hoursByID = response.hours.associateBy { it.id }
        val hourOrder = response.hours.mapIndexed { index, hour -> hour.id to index }.toMap()

        val days = response.days.map { day ->
            val dayID = day.date.ifBlank { "dow-${day.dayOfWeek}" }
            val lessons = day.atoms.mapIndexed { offset, atom ->
                val hour = hoursByID[atom.hourID] ?: TimetableHour(atom.hourID, atom.hourID, "", "")
                val subject = atom.subjectID?.let(subjects::get)
                val teacher = atom.teacherID?.let(teachers::get)
                val room = atom.roomID?.let(rooms::get)
                val groupAbbrevs = atom.groupIDs.mapNotNull { groups[it]?.abbrev?.trimmed() }

                ScheduledLesson(
                    id = "$dayID#${atom.hourID}#$offset",
                    hour = hour,
                    subjectName = subject?.name?.trimmed(),
                    subjectAbbrev = subject?.abbrev?.trimmed(),
                    teacherName = teacher?.name?.trimmed(),
                    teacherAbbrev = teacher?.abbrev?.trimmed(),
                    roomAbbrev = room?.abbrev?.trimmed(),
                    roomName = room?.name?.trimmed(),
                    groups = groupAbbrevs,
                    theme = atom.theme?.trimmed(),
                    hasHomework = atom.homeworkIDs.isNotEmpty(),
                    changeDescription = atom.change?.description?.trimmed(),
                    changeKind = LessonChangeKind.fromApi(atom.change?.changeType),
                )
            }.sortedBy { hourOrder[it.hour.id] ?: Int.MAX_VALUE }

            ScheduledDay(
                id = dayID,
                date = day.date.trimmed(),
                dayOfWeek = day.dayOfWeek,
                dayDescription = day.dayDescription.trim(),
                dayType = day.dayType,
                lessons = lessons,
                isToday = day.date == today,
            )
        }

        return TimetableWeek(weekStart = weekStart, days = days, hours = response.hours)
    }

    private fun index(entities: List<TimetableEntity>): Map<String, TimetableEntity> =
        entities.associateBy { it.id }

    private fun String.trimmed(): String? = trim().takeIf { it.isNotEmpty() }
}

object NextLessonSelector {
    const val DefaultStaleIntervalMillis: Long = 7L * 24L * 60L * 60L * 1000L

    fun select(
        snapshot: NextLessonWidgetSnapshot?,
        nowEpochMillis: Long = System.currentTimeMillis(),
        staleIntervalMillis: Long = DefaultStaleIntervalMillis,
    ): NextLessonWidgetSelection {
        if (snapshot == null) return NextLessonWidgetSelection.NoSnapshot
        if (nowEpochMillis - snapshot.cachedAtEpochMillis > staleIntervalMillis) return NextLessonWidgetSelection.Stale

        val lessons = snapshot.lessons.sortedWith(compareBy<NextLessonWidgetLesson> { it.sortEpochMillis }.thenBy { it.id })
        if (lessons.isEmpty()) return NextLessonWidgetSelection.NoLessons

        val current = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            val end = lesson.endEpochMillis
            start != null && end != null && start <= nowEpochMillis && nowEpochMillis <= end
        }
        if (current != null) return NextLessonWidgetSelection.Lesson(current, NextLessonWidgetTiming.CURRENT)

        val upcoming = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            if (start == null) lesson.sortEpochMillis >= nowEpochMillis else start > nowEpochMillis
        }
        return upcoming?.let { NextLessonWidgetSelection.Lesson(it, NextLessonWidgetTiming.UPCOMING) }
            ?: NextLessonWidgetSelection.NoLessons
    }

    fun timelineDates(snapshot: NextLessonWidgetSnapshot?, afterEpochMillis: Long, limit: Int = 16): List<Long> {
        if (snapshot == null) return emptyList()
        return snapshot.lessons
            .flatMap { listOfNotNull(it.startEpochMillis, it.endEpochMillis) }
            .filter { it > afterEpochMillis }
            .sorted()
            .distinct()
            .take(limit)
    }
}

object WearLessonSelector {
    const val StaleIntervalMillis: Long = NextLessonSelector.DefaultStaleIntervalMillis

    fun select(
        timetable: GradeyWearTimetable?,
        nowEpochMillis: Long = System.currentTimeMillis(),
        staleIntervalMillis: Long = StaleIntervalMillis,
    ): GradeyWearLessonSelection {
        if (timetable == null) return GradeyWearLessonSelection.NoTimetable
        if (nowEpochMillis - timetable.cachedAtEpochMillis > staleIntervalMillis) return GradeyWearLessonSelection.Stale

        val lessons = timetable.days
            .flatMap { it.lessons }
            .sortedWith(compareBy({ it.sortEpochMillis }, { it.id }))
        if (lessons.isEmpty()) return GradeyWearLessonSelection.NoLessons

        val current = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            val end = lesson.endEpochMillis
            start != null && end != null && start <= nowEpochMillis && nowEpochMillis <= end
        }
        if (current != null) return GradeyWearLessonSelection.Lesson(current, NextLessonWidgetTiming.CURRENT)

        val upcoming = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            if (start == null) lesson.sortEpochMillis >= nowEpochMillis else start > nowEpochMillis
        }
        return upcoming?.let { GradeyWearLessonSelection.Lesson(it, NextLessonWidgetTiming.UPCOMING) }
            ?: GradeyWearLessonSelection.NoLessons
    }
}
