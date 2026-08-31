package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.ClassInfo
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import java.util.Locale
import org.junit.Test

class WearPayloadBuilderTest {
    @Test
    fun currentWeekProjectionPrefersFreshCurrentWeek() {
        val fresh = week("2026-08-31")
        val cached = week("2026-08-31")

        assertThat(
            WearPayloadBuilder.currentWeekProjection(
                preferred = fresh,
                cachedCurrent = cached,
                today = LocalDate.parse("2026-09-02"),
            ),
        ).isSameInstanceAs(fresh)
    }

    @Test
    fun currentWeekProjectionUsesCacheInsteadOfBrowsedWeek() {
        val browsed = week("2026-09-07")
        val cached = week("2026-08-31")

        assertThat(
            WearPayloadBuilder.currentWeekProjection(
                preferred = browsed,
                cachedCurrent = cached,
                today = LocalDate.parse("2026-09-02"),
            ),
        ).isSameInstanceAs(cached)
    }

    @Test
    fun currentWeekProjectionReturnsNullWithoutCurrentCandidate() {
        assertThat(
            WearPayloadBuilder.currentWeekProjection(
                preferred = week("2026-09-07"),
                cachedCurrent = week("not-a-date"),
                today = LocalDate.parse("2026-09-02"),
            ),
        ).isNull()
    }

    @Test
    fun buildsPhonePayloadWithoutCopyingSchoolCredentials() {
        val user = UserResponse(
            fullName = "Student Name",
            schoolName = "Fallback School",
            schoolOrganizationName = "Real School",
            userClass = ClassInfo(abbrev = "3A"),
        )
        val week = TimetableWeek(
            weekStart = "2026-08-31",
            days = listOf(
                day(
                    date = "2026-08-31",
                    dayOfWeek = 1,
                    dayType = "WorkDay",
                    lesson = lesson(changeKind = LessonChangeKind.SUBSTITUTION),
                ),
            ),
            hours = emptyList(),
        )

        val payload = WearPayloadBuilder.signedIn(
            week = week,
            user = user,
            supportTier = GradeySupportTier.PLUS,
            generatedAtEpochMillis = 123,
            locale = Locale.US,
        )

        assertThat(payload.schemaVersion).isEqualTo(GradeyWearSyncPayload.CURRENT_SCHEMA_VERSION)
        assertThat(payload.isSignedIn).isTrue()
        assertThat(payload.auth).isNull()
        assertThat(payload.supportTier).isEqualTo(GradeySupportTier.PLUS)
        assertThat(payload.user?.fullName).isEqualTo("Student Name")
        assertThat(payload.user?.schoolName).isEqualTo("Real School")
        assertThat(payload.user?.classAbbrev).isEqualTo("3A")
        assertThat(payload.timetable?.cachedAtEpochMillis).isEqualTo(123)
        assertThat(payload.timetable?.days?.single()?.weekdayTitle).isEqualTo("Mon")
        assertThat(payload.timetable?.days?.single()?.detailTitle).isEqualTo("31 Aug")

        val mapped = payload.timetable!!.days.single().lessons.single()
        assertThat(mapped.startEpochMillis).isEqualTo(epoch("2026-08-31", 23, 30))
        assertThat(mapped.endEpochMillis).isEqualTo(epoch("2026-09-01", 0, 15))
        assertThat(mapped.room).isEqualTo("203")
        assertThat(mapped.teacher).isEqualTo("AB")
        assertThat(mapped.changeKind).isEqualTo(NextLessonWidgetChangeKind.SUBSTITUTION)
    }

    @Test
    fun mapsNonWorkDayAsNotSchoolDayAndFallsBackFromMissingDate() {
        val week = TimetableWeek(
            weekStart = "2026-08-31",
            days = listOf(day(date = null, dayOfWeek = 2, dayType = "Holiday", lesson = lesson())),
            hours = emptyList(),
        )

        val day = WearPayloadBuilder.timetable(week, locale = Locale.US).days.single()

        assertThat(day.isSchoolDay).isFalse()
        assertThat(day.weekdayTitle).isEqualTo("Tue")
        assertThat(day.dayStartEpochMillis).isEqualTo(epoch("2026-09-01", 0, 0))
    }

    private fun day(
        date: String?,
        dayOfWeek: Int,
        dayType: String,
        lesson: ScheduledLesson,
    ) = ScheduledDay(
        id = date ?: "dow-$dayOfWeek",
        date = date,
        dayOfWeek = dayOfWeek,
        dayDescription = "",
        dayType = dayType,
        lessons = listOf(lesson),
        isToday = false,
    )

    private fun week(weekStart: String) = TimetableWeek(
        weekStart = weekStart,
        days = emptyList(),
        hours = emptyList(),
    )

    private fun lesson(changeKind: LessonChangeKind = LessonChangeKind.NONE) = ScheduledLesson(
        id = "lesson",
        hour = TimetableHour("1", "1", "23:30", "00:15"),
        subjectName = "Mathematics",
        subjectAbbrev = "M",
        teacherName = null,
        teacherAbbrev = "AB",
        roomAbbrev = "203",
        roomName = null,
        groups = emptyList(),
        theme = null,
        hasHomework = false,
        changeKind = changeKind,
    )

    private fun epoch(date: String, hour: Int, minute: Int): Long = LocalDate.parse(date)
        .atTime(hour, minute)
        .atZone(TimetableDates.SchoolZone)
        .toInstant()
        .toEpochMilli()
}
