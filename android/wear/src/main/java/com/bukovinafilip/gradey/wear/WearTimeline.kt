package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeyWearTimetable
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

internal sealed interface WearNowPage {
    data object NoTimetable : WearNowPage
    data object Stale : WearNowPage
    data object DoneForToday : WearNowPage
    data class InLesson(
        val lesson: GradeyWearTimetableLesson,
        val progress: Float,
    ) : WearNowPage

    data class BetweenLessons(
        val next: GradeyWearTimetableLesson,
        val progress: Float,
        val previous: GradeyWearTimetableLesson?,
    ) : WearNowPage
}

internal data class WearNowNext(
    val current: GradeyWearTimetableLesson?,
    val next: GradeyWearTimetableLesson?,
)

/** Pure watch presentation rules, kept here so UI and complications always agree. */
internal object WearTimeline {
    const val StaleIntervalMillis = 7L * 24 * 60 * 60 * 1_000

    fun nowPage(
        timetable: GradeyWearTimetable?,
        nowEpochMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        staleIntervalMillis: Long = StaleIntervalMillis,
    ): WearNowPage {
        if (timetable == null) return WearNowPage.NoTimetable
        if (isStale(timetable, nowEpochMillis, staleIntervalMillis)) return WearNowPage.Stale

        val lessons = todaysLessons(timetable, nowEpochMillis, zoneId)
        if (lessons.isEmpty()) return WearNowPage.DoneForToday

        val current = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            val end = lesson.endEpochMillis
            start != null && end != null && start <= nowEpochMillis && nowEpochMillis <= end
        }
        if (current != null) {
            return WearNowPage.InLesson(
                lesson = current,
                progress = progress(current.startEpochMillis!!, current.endEpochMillis!!, nowEpochMillis),
            )
        }

        val upcoming = lessons.firstOrNull { lesson ->
            lesson.startEpochMillis?.let { it > nowEpochMillis } ?: (lesson.sortEpochMillis > nowEpochMillis)
        } ?: return WearNowPage.DoneForToday

        val previous = lessons.lastOrNull { lesson ->
            lesson.endEpochMillis?.let { it <= nowEpochMillis } ?: (lesson.sortEpochMillis <= nowEpochMillis)
        }
        val gapStart = previous?.endEpochMillis ?: upcoming.dayStartEpochMillis
        return WearNowPage.BetweenLessons(
            next = upcoming,
            progress = progress(gapStart, upcoming.startEpochMillis ?: gapStart, nowEpochMillis),
            previous = previous,
        )
    }

    fun remainingLessonsToday(
        timetable: GradeyWearTimetable?,
        nowEpochMillis: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        staleIntervalMillis: Long = StaleIntervalMillis,
    ): List<GradeyWearTimetableLesson> {
        if (timetable == null || isStale(timetable, nowEpochMillis, staleIntervalMillis)) return emptyList()
        return todaysLessons(timetable, nowEpochMillis, zoneId).filter { lesson ->
            lesson.changeKind != NextLessonWidgetChangeKind.CANCELED &&
                (lesson.startEpochMillis?.let { it > nowEpochMillis } ?: (lesson.sortEpochMillis > nowEpochMillis))
        }
    }

    fun nowAndNext(
        payload: GradeyWearSyncPayload?,
        nowEpochMillis: Long = System.currentTimeMillis(),
        staleIntervalMillis: Long = StaleIntervalMillis,
    ): WearNowNext {
        val timetable = payload?.takeIf { it.isSignedIn }?.timetable
        if (timetable == null || isStale(timetable, nowEpochMillis, staleIntervalMillis)) {
            return WearNowNext(current = null, next = null)
        }
        val lessons = timetable.days
            .flatMap { it.lessons }
            .sortedWith(compareBy({ it.sortEpochMillis }, { it.id }))
        val current = lessons.firstOrNull { lesson ->
            val start = lesson.startEpochMillis
            val end = lesson.endEpochMillis
            start != null && end != null && start <= nowEpochMillis && nowEpochMillis <= end
        }
        val next = lessons.firstOrNull { lesson ->
            lesson.id != current?.id &&
                (lesson.startEpochMillis?.let { it > nowEpochMillis } ?: (lesson.sortEpochMillis >= nowEpochMillis))
        }
        return WearNowNext(current = current, next = next)
    }

    fun progress(startEpochMillis: Long, endEpochMillis: Long, nowEpochMillis: Long): Float {
        val duration = endEpochMillis - startEpochMillis
        if (duration <= 0) return if (nowEpochMillis >= endEpochMillis) 1f else 0f
        return min(1f, max(0f, (nowEpochMillis - startEpochMillis).toFloat() / duration.toFloat()))
    }

    private fun todaysLessons(
        timetable: GradeyWearTimetable,
        nowEpochMillis: Long,
        zoneId: ZoneId,
    ): List<GradeyWearTimetableLesson> {
        val today = Instant.ofEpochMilli(nowEpochMillis).atZone(zoneId).toLocalDate()
        val day = timetable.days.firstOrNull { candidate ->
            val explicitDate = candidate.date?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            val resolvedDate = explicitDate ?: Instant.ofEpochMilli(candidate.dayStartEpochMillis)
                .atZone(zoneId)
                .toLocalDate()
            resolvedDate == today
        }
        return day?.lessons
            ?.sortedWith(compareBy({ it.sortEpochMillis }, { it.id }))
            .orEmpty()
    }

    private fun isStale(
        timetable: GradeyWearTimetable,
        nowEpochMillis: Long,
        staleIntervalMillis: Long,
    ): Boolean = nowEpochMillis - timetable.cachedAtEpochMillis > staleIntervalMillis
}

/**
 * Wear AI is intentionally not offered on Android yet.
 *
 * The Android Data Layer contract currently carries timetable, identity and support entitlement in one
 * direction only. A watch chat without authenticated bidirectional streaming, cancellation, consent and
 * school-context parity would be a misleading placeholder. AI therefore remains phone-only until that
 * complete transport exists; supporter tier is still shown from the real phone payload.
 */
internal object WearProductDecisions {
    const val AI_AVAILABILITY = "N/A — phone-only until the authenticated streaming Data Layer contract exists"
}
