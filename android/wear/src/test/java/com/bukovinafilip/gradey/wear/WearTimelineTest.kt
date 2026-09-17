package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeyWearTimetable
import com.bukovinafilip.gradey.model.GradeyWearTimetableDay
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class WearTimelineTest {
    private val zone = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 8, 31)
    private val now = today.atTime(9, 15).atZone(zone).toInstant().toEpochMilli()

    @Test
    fun nowPage_reportsCurrentLessonAndProgress() {
        val current = lesson("current", today, 9, 0, 9, 30)

        val page = WearTimeline.nowPage(timetable(today to listOf(current)), now, zone)

        assertThat(page).isEqualTo(WearNowPage.InLesson(current, 0.5f))
    }

    @Test
    fun nowPage_reportsBreakProgressAndPreviousLesson() {
        val previous = lesson("previous", today, 8, 0, 9, 0)
        val next = lesson("next", today, 9, 30, 10, 15)

        val page = WearTimeline.nowPage(timetable(today to listOf(next, previous)), now, zone)

        assertThat(page).isEqualTo(WearNowPage.BetweenLessons(next, 0.5f, previous))
    }

    @Test
    fun nowPage_isDoneAfterTodayEvenWhenTomorrowHasLessons() {
        val finished = lesson("finished", today, 8, 0, 9, 0)
        val tomorrow = lesson("tomorrow", today.plusDays(1), 8, 0, 9, 0)

        val page = WearTimeline.nowPage(
            timetable(today to listOf(finished), today.plusDays(1) to listOf(tomorrow)),
            now,
            zone,
        )

        assertThat(page).isEqualTo(WearNowPage.DoneForToday)
    }

    @Test
    fun remainingLessonsToday_skipsCurrentPastAndCanceledLessons() {
        val past = lesson("past", today, 8, 0, 8, 45)
        val current = lesson("current", today, 9, 0, 9, 30)
        val upcoming = lesson("upcoming", today, 10, 0, 10, 45)
        val canceled = lesson(
            "canceled",
            today,
            11,
            0,
            11,
            45,
            NextLessonWidgetChangeKind.CANCELED,
        )

        val remaining = WearTimeline.remainingLessonsToday(
            timetable(today to listOf(canceled, current, past, upcoming)),
            now,
            zone,
        )

        assertThat(remaining.map { it.id }).containsExactly("upcoming")
    }

    @Test
    fun staleTimetable_hasExplicitStaleStateAndNoRemainingLessons() {
        val timetable = timetable(today to listOf(lesson("lesson", today, 10, 0, 10, 45))).copy(
            cachedAtEpochMillis = now - WearTimeline.StaleIntervalMillis - 1,
        )

        assertThat(WearTimeline.nowPage(timetable, now, zone)).isEqualTo(WearNowPage.Stale)
        assertThat(WearTimeline.remainingLessonsToday(timetable, now, zone)).isEmpty()
    }

    @Test
    fun priorWeekIsStaleAfterRolloverEvenWhenRepublishedWithFreshTimestamp() {
        val priorWeek = timetable(
            today to listOf(lesson("old", today, 10, 0, 10, 45)),
        )
        val nextMondayNow = today.plusWeeks(1)
            .atTime(9, 15)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()
        val freshlyRepublished = priorWeek.copy(cachedAtEpochMillis = nextMondayNow)
        val payload = GradeyWearSyncPayload(
            generatedAtEpochMillis = nextMondayNow,
            isSignedIn = true,
            timetable = freshlyRepublished,
        )

        assertThat(WearTimeline.nowPage(freshlyRepublished, nextMondayNow, zone))
            .isEqualTo(WearNowPage.Stale)
        assertThat(WearTimeline.remainingLessonsToday(freshlyRepublished, nextMondayNow, zone))
            .isEmpty()
        assertThat(WearTimeline.nowAndNext(payload, nextMondayNow, zone))
            .isEqualTo(WearNowNext(null, null))
    }

    @Test
    fun nowAndNext_usesRealSignedInPayloadAndRejectsSignedOutPayload() {
        val current = lesson("current", today, 9, 0, 9, 30)
        val next = lesson("next", today, 10, 0, 10, 45)
        val timetable = timetable(today to listOf(next, current))
        val payload = GradeyWearSyncPayload(
            generatedAtEpochMillis = now,
            isSignedIn = true,
            supportTier = GradeySupportTier.PLUS,
            timetable = timetable,
        )

        assertThat(WearTimeline.nowAndNext(payload, now)).isEqualTo(WearNowNext(current, next))
        assertThat(WearTimeline.nowAndNext(GradeyWearSyncPayload.signedOut(now), now))
            .isEqualTo(WearNowNext(null, null))
    }

    @Test
    fun invalidDurationProgress_isSafelyClamped() {
        assertThat(WearTimeline.progress(10, 10, 9)).isEqualTo(0f)
        assertThat(WearTimeline.progress(10, 10, 10)).isEqualTo(1f)
        assertThat(WearTimeline.progress(10, 20, 30)).isEqualTo(1f)
    }

    @Test
    fun wearAiDecision_doesNotClaimAnIncompleteWatchFeature() {
        assertThat(WearProductDecisions.AI_AVAILABILITY).startsWith("N/A")
    }

    private fun timetable(vararg days: Pair<LocalDate, List<GradeyWearTimetableLesson>>): GradeyWearTimetable =
        GradeyWearTimetable(
            weekStart = days.first().first.toString(),
            cachedAtEpochMillis = now,
            days = days.map { (date, lessons) ->
                GradeyWearTimetableDay(
                    id = date.toString(),
                    date = date.toString(),
                    dayStartEpochMillis = date.atStartOfDay(zone).toInstant().toEpochMilli(),
                    weekdayTitle = date.dayOfWeek.name,
                    detailTitle = date.toString(),
                    isToday = date == today,
                    isSchoolDay = true,
                    lessons = lessons,
                )
            },
        )

    private fun lesson(
        id: String,
        date: LocalDate,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        changeKind: NextLessonWidgetChangeKind = NextLessonWidgetChangeKind.NONE,
    ): GradeyWearTimetableLesson = GradeyWearTimetableLesson(
        id = id,
        dayStartEpochMillis = date.atStartOfDay(zone).toInstant().toEpochMilli(),
        startEpochMillis = date.atTime(startHour, startMinute).atZone(zone).toInstant().toEpochMilli(),
        endEpochMillis = date.atTime(endHour, endMinute).atZone(zone).toInstant().toEpochMilli(),
        subjectName = id.replaceFirstChar(Char::uppercase),
        subjectAbbrev = id.take(3).uppercase(),
        timeRange = null,
        room = "12",
        teacher = "Teacher",
        changeKind = changeKind,
    )
}
