package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeyWearLessonSelection
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeyWearTimetable
import com.bukovinafilip.gradey.model.GradeyWearTimetableDay
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import com.bukovinafilip.gradey.model.GradeyWearUser
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetSelection
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.NextLessonWidgetTiming
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import java.time.DayOfWeek
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.time.format.TextStyle
import java.util.Locale

object TimetableDates {
    private val ApiFormatter: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    val SchoolZone: ZoneId = ZoneId.of("Europe/Prague")

    fun today(clock: Clock = Clock.systemUTC()): LocalDate = LocalDate.now(clock.withZone(SchoolZone))

    fun todayString(clock: Clock = Clock.systemUTC()): String = apiDateString(today(clock))

    fun monday(date: LocalDate = today()): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun apiDateString(date: LocalDate): String = ApiFormatter.format(date)

    fun parseApiDate(value: String?): LocalDate? {
        val candidate = value?.trim().orEmpty()
        if (candidate.length < 10) return null
        return runCatching { LocalDate.parse(candidate.take(10), ApiFormatter) }.getOrNull()
    }
}

object TimetableMapper {
    fun makeWeek(
        response: TimetableResponse,
        weekStart: String,
        today: String = TimetableDates.todayString(),
    ): TimetableWeek {
        val todayDate = TimetableDates.parseApiDate(today)
        val subjects = index(response.subjects)
        val teachers = index(response.teachers)
        val rooms = index(response.rooms)
        val groups = response.groups.associateBy { it.id }
        val hoursByID = response.hours.associateBy { it.id }
        val hourOrder = response.hours.mapIndexed { index, hour -> hour.id to index }.toMap()

        val days = response.days.map { day ->
            val rawDate = day.date.trim()
            val parsedDate = TimetableDates.parseApiDate(rawDate)
            val dayID = rawDate.ifBlank { "dow-${day.dayOfWeek}" }
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
                    change = atom.change,
                )
            }.sortedWith(
                compareBy<ScheduledLesson> { hourOrder[it.hour.id] ?: Int.MAX_VALUE }
                    .thenBy { it.hour.id.toIntOrNull() ?: Int.MAX_VALUE }
                    .thenBy { it.hour.id },
            )

            ScheduledDay(
                id = dayID,
                date = parsedDate?.let(TimetableDates::apiDateString),
                dayOfWeek = day.dayOfWeek,
                dayDescription = day.dayDescription.trim(),
                dayType = day.dayType,
                lessons = lessons,
                isToday = parsedDate != null && parsedDate == todayDate,
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

object NextLessonSnapshotBuilder {
    fun update(
        existing: NextLessonWidgetSnapshot?,
        week: TimetableWeek,
        cachedAtEpochMillis: Long = System.currentTimeMillis(),
    ): NextLessonWidgetSnapshot {
        val newLessons = lessons(week)
        val weekStart = runCatching { LocalDate.parse(week.weekStart) }.getOrNull()
        val retained = if (weekStart == null) {
            existing?.lessons.orEmpty()
        } else {
            val start = weekStart.atStartOfDay(TimetableDates.SchoolZone).toInstant().toEpochMilli()
            val end = weekStart.plusDays(7).atStartOfDay(TimetableDates.SchoolZone).toInstant().toEpochMilli()
            existing?.lessons.orEmpty().filter { it.dayStartEpochMillis < start || it.dayStartEpochMillis >= end }
        }
        val combined = (retained + newLessons)
            .associateBy(NextLessonWidgetLesson::id)
            .values
            .sortedWith(compareBy(NextLessonWidgetLesson::sortEpochMillis, NextLessonWidgetLesson::id))
        return NextLessonWidgetSnapshot(cachedAtEpochMillis, combined)
    }

    fun lessons(week: TimetableWeek): List<NextLessonWidgetLesson> {
        val weekStart = runCatching { LocalDate.parse(week.weekStart) }.getOrNull()
        return week.days.flatMap { day ->
            val date = day.date?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                ?: weekStart?.plusDays((day.dayOfWeek - 1).coerceAtLeast(0).toLong())
                ?: return@flatMap emptyList()
            val dayStart = date.atStartOfDay(TimetableDates.SchoolZone).toInstant().toEpochMilli()
            day.lessons.map { lesson ->
                val start = epochMillis(date, lesson.hour.beginTime)
                var end = epochMillis(date, lesson.hour.endTime)
                if (start != null && end != null && end < start) end = epochMillis(date.plusDays(1), lesson.hour.endTime)
                NextLessonWidgetLesson(
                    id = lesson.id,
                    dayStartEpochMillis = dayStart,
                    startEpochMillis = start,
                    endEpochMillis = end,
                    subjectName = lesson.subjectName,
                    subjectAbbrev = lesson.subjectAbbrev,
                    timeRange = timeRange(lesson.hour),
                    room = lesson.roomAbbrev ?: lesson.roomName,
                    teacher = lesson.teacherAbbrev ?: lesson.teacherName,
                    changeKind = lesson.changeKind.toWidgetKind(),
                )
            }
        }
    }

    private fun epochMillis(date: LocalDate, rawTime: String): Long? {
        val parts = rawTime.trim().split(':')
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return date.atTime(hour, minute).atZone(TimetableDates.SchoolZone).toInstant().toEpochMilli()
    }

    private fun timeRange(hour: TimetableHour): String? {
        val start = hour.beginTime.trim()
        val end = hour.endTime.trim()
        return if (start.isEmpty() || end.isEmpty()) null else "$start-$end"
    }

    private fun LessonChangeKind.toWidgetKind(): NextLessonWidgetChangeKind = when (this) {
        LessonChangeKind.NONE -> NextLessonWidgetChangeKind.NONE
        LessonChangeKind.CANCELED -> NextLessonWidgetChangeKind.CANCELED
        LessonChangeKind.SUBSTITUTION -> NextLessonWidgetChangeKind.SUBSTITUTION
        LessonChangeKind.ROOM_CHANGED -> NextLessonWidgetChangeKind.ROOM_CHANGED
        LessonChangeKind.ADDED -> NextLessonWidgetChangeKind.ADDED
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

object WearPayloadBuilder {
    fun signedIn(
        week: TimetableWeek,
        user: UserResponse? = null,
        supportTier: GradeySupportTier = GradeySupportTier.NONE,
        generatedAtEpochMillis: Long = System.currentTimeMillis(),
        locale: Locale = Locale.getDefault(),
    ): GradeyWearSyncPayload = GradeyWearSyncPayload(
        generatedAtEpochMillis = generatedAtEpochMillis,
        isSignedIn = true,
        supportTier = supportTier,
        user = user?.let {
            GradeyWearUser(
                fullName = it.fullName,
                schoolName = it.displaySchoolName,
                classAbbrev = it.classAbbrev,
            )
        },
        timetable = timetable(week, generatedAtEpochMillis, locale),
    )

    fun timetable(
        week: TimetableWeek,
        cachedAtEpochMillis: Long = System.currentTimeMillis(),
        locale: Locale = Locale.getDefault(),
    ): GradeyWearTimetable {
        val weekStart = runCatching { LocalDate.parse(week.weekStart) }.getOrNull()
        val widgetLessons = NextLessonSnapshotBuilder.lessons(week).associateBy { it.id }
        val detailFormatter = DateTimeFormatter.ofPattern("d MMM", locale)
        return GradeyWearTimetable(
            weekStart = week.weekStart,
            cachedAtEpochMillis = cachedAtEpochMillis,
            days = week.days.map { day ->
                val date = day.date?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                    ?: weekStart?.plusDays((day.dayOfWeek - 1).coerceAtLeast(0).toLong())
                val dayStart = date
                    ?.atStartOfDay(TimetableDates.SchoolZone)
                    ?.toInstant()
                    ?.toEpochMilli()
                    ?: 0L
                GradeyWearTimetableDay(
                    id = day.id,
                    date = day.date,
                    dayStartEpochMillis = dayStart,
                    weekdayTitle = date?.dayOfWeek?.getDisplayName(TextStyle.SHORT, locale)
                        ?: fallbackWeekdayTitle(day.dayOfWeek, locale),
                    detailTitle = date?.format(detailFormatter)
                        ?: day.dayDescription.trim().takeIf(String::isNotEmpty),
                    isToday = day.isToday,
                    isSchoolDay = day.dayType.equals("WorkDay", ignoreCase = true),
                    lessons = day.lessons.map { lesson ->
                        val mapped = widgetLessons[lesson.id]
                        GradeyWearTimetableLesson(
                            id = lesson.id,
                            dayStartEpochMillis = mapped?.dayStartEpochMillis ?: dayStart,
                            startEpochMillis = mapped?.startEpochMillis,
                            endEpochMillis = mapped?.endEpochMillis,
                            subjectName = lesson.subjectName,
                            subjectAbbrev = lesson.subjectAbbrev,
                            timeRange = mapped?.timeRange,
                            room = mapped?.room,
                            teacher = mapped?.teacher,
                            changeKind = mapped?.changeKind ?: NextLessonWidgetChangeKind.NONE,
                        )
                    },
                )
            },
        )
    }

    private fun fallbackWeekdayTitle(dayOfWeek: Int, locale: Locale): String =
        runCatching { DayOfWeek.of(dayOfWeek).getDisplayName(TextStyle.SHORT, locale) }
            .getOrDefault(dayOfWeek.toString())
}
