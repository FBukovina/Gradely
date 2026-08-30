package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Absence
import com.google.common.truth.Truth.assertThat
import java.time.YearMonth
import org.junit.Test

class AbsenceToolsTest {
    @Test
    fun emptyTimelineHasZeroTotalsAndNoGroups() {
        val timeline = AbsenceTimeline.make(AbsenceResponse())

        assertThat(timeline.total.total).isEqualTo(0)
        assertThat(timeline.days).isEmpty()
        assertThat(timeline.months).isEmpty()
    }

    @Test
    fun exactThresholdIsOverLimit() {
        val response = AbsenceResponse(
            percentageThreshold = 25.0,
            absencesPerSubject = listOf(AbsencePerSubject("Math", lessonsCount = 20, base = 5)),
        )

        val subject = AbsenceRiskSummary.make(response, response.absencesPerSubject).subjects.single()

        assertThat(subject.level).isEqualTo(AbsenceRiskLevel.OVER_LIMIT)
        assertThat(subject.missesUntilLimit).isEqualTo(0)
    }

    @Test
    fun missingThresholdDoesNotGuessRisk() {
        val response = AbsenceResponse(
            percentageThreshold = null,
            absencesPerSubject = listOf(
                AbsencePerSubject("Biology", lessonsCount = 10, base = 3),
                AbsencePerSubject("Math", lessonsCount = 10, base = 1),
                AbsencePerSubject("English", lessonsCount = 10, base = 2),
            ),
        )

        val summary = AbsenceRiskSummary.make(response, response.absencesPerSubject)

        assertThat(summary.isThresholdUnavailable).isTrue()
        assertThat(summary.subjects.map { it.level }.distinct()).containsExactly(AbsenceRiskLevel.UNAVAILABLE)
        assertThat(summary.subjects.map { it.subjectName })
            .containsExactly("Biology", "English", "Math")
            .inOrder()
    }

    @Test
    fun riskBandsAndOrderingMatchIOS() {
        val response = AbsenceResponse(
            percentageThreshold = 25.0,
            absencesPerSubject = listOf(
                AbsencePerSubject("Safe", lessonsCount = 20, base = 3),
                AbsencePerSubject("Watch", lessonsCount = 80, base = 14),
                AbsencePerSubject("High", lessonsCount = 80, base = 18),
                AbsencePerSubject("Over", lessonsCount = 20, base = 5),
            ),
        )

        val rows = AbsenceRiskSummary.make(response, response.absencesPerSubject).subjects

        assertThat(rows.map { it.subjectName }).containsExactly("Over", "High", "Watch", "Safe").inOrder()
        assertThat(rows.map { it.level }).containsExactly(
            AbsenceRiskLevel.OVER_LIMIT,
            AbsenceRiskLevel.HIGH,
            AbsenceRiskLevel.WATCH,
            AbsenceRiskLevel.SAFE,
        ).inOrder()
    }

    @Test
    fun timelineAggregatesDailyRowsAndMonths() {
        val response = AbsenceResponse(
            absences = listOf(
                Absence(
                    date = "2026-04-07T08:00:00+02:00",
                    ok = 2,
                    late = 1,
                    soon = 3,
                    school = 4,
                    distanceTeaching = 5,
                    unsolved = 6,
                    missed = 7,
                ),
                Absence(date = "2026-04-07T09:00:00+02:00", ok = 1),
                Absence(date = "2026-05-04", unsolved = 2),
                Absence(date = "not-a-date", ok = 99),
            ),
        )

        val timeline = AbsenceTimeline.make(response)

        assertThat(timeline.total.total).isEqualTo(31)
        assertThat(timeline.total.ok).isEqualTo(3)
        assertThat(timeline.total.late).isEqualTo(1)
        assertThat(timeline.total.soon).isEqualTo(3)
        assertThat(timeline.total.school).isEqualTo(4)
        assertThat(timeline.total.distanceTeaching).isEqualTo(5)
        assertThat(timeline.total.unsolved).isEqualTo(8)
        assertThat(timeline.total.missed).isEqualTo(7)
        assertThat(timeline.days).hasSize(2)
        assertThat(timeline.months.map { it.month }).containsExactly(
            YearMonth.of(2026, 4),
            YearMonth.of(2026, 5),
        ).inOrder()
        assertThat(timeline.months.first().counts.total).isEqualTo(29)
    }

    @Test
    fun predictionDeduplicatesLessonsAndProjectsSubjectAcrossThreshold() {
        val response = AbsenceResponse(
            percentageThreshold = 25.0,
            absencesPerSubject = listOf(AbsencePerSubject("Mathematics", lessonsCount = 20, base = 4)),
        )
        val subjects = AbsenceRiskSummary.make(response, response.absencesPerSubject).subjects
        val lesson = AbsenceLessonCandidate(
            id = "lesson-2026-06-15-1-raw-math",
            dateKey = "2026-06-15",
            hourID = "1",
            subjectKey = subjects.single().stableID,
            subjectName = "Mathematics",
        )
        val second = lesson.copy(id = "lesson-2026-06-15-2-raw-math", hourID = "2")

        val result = AbsencePrediction.project(
            currentTotalCounts = com.bukovinafilip.gradey.model.AbsenceCounts(ok = 3, missed = 1),
            subjectRows = subjects,
            selectedLessons = listOf(lesson, second, second),
            threshold = 25.0,
        )

        assertThat(result.addedHours).isEqualTo(2)
        assertThat(result.projectedTotal.ok).isEqualTo(5)
        assertThat(result.projectedTotal.total).isEqualTo(6)
        assertThat(result.subjectRows.single().projectedBase).isEqualTo(6)
        assertThat(result.subjectRows.single().projectedLessonsCount).isEqualTo(22)
        assertThat(result.subjectRows.single().crossesThreshold).isTrue()
    }

    @Test
    fun predictionDoesNotInventPercentageForUnknownSubject() {
        val result = AbsencePrediction.project(
            currentTotalCounts = com.bukovinafilip.gradey.model.AbsenceCounts(),
            subjectRows = emptyList(),
            selectedLessons = listOf(
                AbsenceLessonCandidate("lesson-bio", "2026-06-15", "1", subjectKey = "raw-bio", subjectName = "Biology"),
            ),
            threshold = 25.0,
        )

        assertThat(result.addedHours).isEqualTo(1)
        assertThat(result.projectedTotal.ok).isEqualTo(1)
        assertThat(result.subjectRows.single().currentPercentage).isNull()
        assertThat(result.subjectRows.single().projectedPercentage).isNull()
    }
}
