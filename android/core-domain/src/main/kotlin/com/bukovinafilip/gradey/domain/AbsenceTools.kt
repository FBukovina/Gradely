package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsenceCounts
import com.bukovinafilip.gradey.model.Absence
import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.ceil

enum class AbsenceRiskLevel {
    SAFE,
    WATCH,
    HIGH,
    OVER_LIMIT,
    UNAVAILABLE,
}

data class AbsenceSubjectSummary(
    val stableID: String,
    val subjectName: String,
    val lessonsCount: Int,
    val base: Int,
    val absencePercentage: Double,
    val threshold: Double?,
    val missesUntilLimit: Int?,
    val level: AbsenceRiskLevel,
)

data class AbsenceRiskSummary(
    val subjects: List<AbsenceSubjectSummary>,
    val isThresholdUnavailable: Boolean,
) {
    companion object {
        fun make(response: AbsenceResponse, subjects: List<AbsencePerSubject>): AbsenceRiskSummary {
            val threshold = normalizedThreshold(response.percentageThreshold)
            val rows = subjects.mapIndexed { index, row ->
                val percentage = if (row.lessonsCount > 0) row.base.toDouble() / row.lessonsCount.toDouble() * 100.0 else 0.0
                val missesUntilLimit = threshold?.let { missesUntilLimit(row.base, row.lessonsCount, it) }
                val level = riskLevel(percentage, threshold)
                AbsenceSubjectSummary(
                    stableID = stableID(row.subjectName, index),
                    subjectName = row.subjectName,
                    lessonsCount = row.lessonsCount,
                    base = row.base,
                    absencePercentage = percentage,
                    threshold = threshold,
                    missesUntilLimit = missesUntilLimit,
                    level = level,
                )
            }.sortedWith(compareByDescending<AbsenceSubjectSummary> { it.level.ordinal }.thenBy { it.subjectName.lowercase() })
            return AbsenceRiskSummary(rows, threshold == null)
        }

        private fun normalizedThreshold(threshold: Double?): Double? =
            threshold?.let { if (it > 0 && it <= 1) it * 100.0 else it }?.takeIf { it > 0.0 }

        private fun riskLevel(percentage: Double, threshold: Double?): AbsenceRiskLevel {
            if (threshold == null) return AbsenceRiskLevel.UNAVAILABLE
            return when {
                percentage >= threshold -> AbsenceRiskLevel.OVER_LIMIT
                percentage >= threshold * 0.8 -> AbsenceRiskLevel.HIGH
                percentage >= threshold * 0.6 -> AbsenceRiskLevel.WATCH
                else -> AbsenceRiskLevel.SAFE
            }
        }

        private fun missesUntilLimit(base: Int, lessonsCount: Int, threshold: Double): Int {
            if (lessonsCount <= 0) return 0
            val target = threshold / 100.0
            val current = base.toDouble() / lessonsCount.toDouble()
            if (current >= target) return 0
            val needed = ceil(((target * lessonsCount) - base) / (1.0 - target)).toInt()
            return needed.coerceAtLeast(0)
        }

        private fun stableID(subjectName: String, index: Int): String =
            subjectName.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifBlank { "subject-$index" }
    }
}

data class AbsenceDaySummary(
    val date: LocalDate,
    val counts: AbsenceCounts,
)

data class AbsenceMonthSummary(
    val month: YearMonth,
    val counts: AbsenceCounts,
)

data class AbsenceTimelineSummary(
    val total: AbsenceCounts,
    val days: List<AbsenceDaySummary>,
    val months: List<AbsenceMonthSummary>,
)

object AbsenceTimeline {
    fun make(response: AbsenceResponse): AbsenceTimelineSummary {
        val days = response.absences
            .mapNotNull { absence -> parseDate(absence.date)?.let { it to absence.toCounts() } }
            .groupBy(keySelector = Pair<LocalDate, AbsenceCounts>::first, valueTransform = Pair<LocalDate, AbsenceCounts>::second)
            .map { (date, counts) -> AbsenceDaySummary(date, counts.sumCounts()) }
            .sortedBy(AbsenceDaySummary::date)
        val months = days
            .groupBy { YearMonth.from(it.date) }
            .map { (month, rows) -> AbsenceMonthSummary(month, rows.map(AbsenceDaySummary::counts).sumCounts()) }
            .sortedBy(AbsenceMonthSummary::month)
        return AbsenceTimelineSummary(
            total = days.map(AbsenceDaySummary::counts).sumCounts(),
            days = days,
            months = months,
        )
    }

    private fun parseDate(value: String): LocalDate? =
        runCatching { LocalDate.parse(value.take(10)) }.getOrNull()
}

fun Absence.toCounts(): AbsenceCounts = AbsenceCounts(
    ok = ok,
    late = late,
    soon = soon,
    school = school,
    distanceTeaching = distanceTeaching,
    unsolved = unsolved,
    missed = missed,
)

private fun Iterable<AbsenceCounts>.sumCounts(): AbsenceCounts = fold(AbsenceCounts()) { sum, row ->
    AbsenceCounts(
        ok = sum.ok + row.ok,
        late = sum.late + row.late,
        soon = sum.soon + row.soon,
        school = sum.school + row.school,
        distanceTeaching = sum.distanceTeaching + row.distanceTeaching,
        unsolved = sum.unsolved + row.unsolved,
        missed = sum.missed + row.missed,
    )
}

data class AbsenceLessonCandidate(
    val id: String,
    val dateKey: String,
    val hourID: String,
    val subjectKey: String,
    val subjectName: String,
)

data class AbsencePredictionSubjectRow(
    val id: String,
    val subjectName: String,
    val addedHours: Int,
    val currentBase: Int?,
    val projectedBase: Int?,
    val currentLessonsCount: Int?,
    val projectedLessonsCount: Int?,
    val currentPercentage: Double?,
    val projectedPercentage: Double?,
    val exceedsThreshold: Boolean,
    val crossesThreshold: Boolean,
)

data class AbsencePredictionResult(
    val currentTotal: AbsenceCounts,
    val projectedTotal: AbsenceCounts,
    val addedHours: Int,
    val subjectRows: List<AbsencePredictionSubjectRow>,
) {
    val hasSelection: Boolean get() = addedHours > 0
}

object AbsencePrediction {
    fun project(
        currentTotalCounts: AbsenceCounts,
        subjectRows: List<AbsenceSubjectSummary>,
        selectedLessons: List<AbsenceLessonCandidate>,
        threshold: Double?,
    ): AbsencePredictionResult {
        val uniqueLessons = selectedLessonsByID(selectedLessons)
        val normalizedThreshold = if (threshold != null && threshold > 0 && threshold <= 1) threshold * 100 else threshold ?: 0.0
        val projectedTotal = currentTotalCounts.copy(ok = currentTotalCounts.ok + uniqueLessons.size)

        val rows = uniqueLessons.groupBy { it.subjectKey }.map { (subjectKey, lessons) ->
            val sorted = lessons.sortedWith(compareBy({ it.dateKey }, { it.hourID }, { it.subjectName.lowercase() }))
            val sample = sorted.first()
            val baseline = baselineRow(sample, subjectKey, subjectRows)
            val addedHours = sorted.size
            if (baseline == null) {
                AbsencePredictionSubjectRow(
                    id = subjectKey,
                    subjectName = sample.subjectName,
                    addedHours = addedHours,
                    currentBase = null,
                    projectedBase = null,
                    currentLessonsCount = null,
                    projectedLessonsCount = null,
                    currentPercentage = null,
                    projectedPercentage = null,
                    exceedsThreshold = false,
                    crossesThreshold = false,
                )
            } else {
                val projectedBase = baseline.base + addedHours
                val projectedLessonsCount = baseline.lessonsCount + addedHours
                val projectedPercentage = if (projectedLessonsCount > 0) {
                    projectedBase.toDouble() / projectedLessonsCount.toDouble() * 100.0
                } else {
                    0.0
                }
                val exceeds = normalizedThreshold > 0 && projectedPercentage >= normalizedThreshold
                val currentlyExceeds = normalizedThreshold > 0 && baseline.absencePercentage >= normalizedThreshold
                AbsencePredictionSubjectRow(
                    id = baseline.stableID,
                    subjectName = baseline.subjectName,
                    addedHours = addedHours,
                    currentBase = baseline.base,
                    projectedBase = projectedBase,
                    currentLessonsCount = baseline.lessonsCount,
                    projectedLessonsCount = projectedLessonsCount,
                    currentPercentage = baseline.absencePercentage,
                    projectedPercentage = projectedPercentage,
                    exceedsThreshold = exceeds,
                    crossesThreshold = !currentlyExceeds && exceeds,
                )
            }
        }.sortedWith(compareByDescending<AbsencePredictionSubjectRow> { it.exceedsThreshold }.thenByDescending { it.projectedPercentage ?: -1.0 })

        return AbsencePredictionResult(currentTotalCounts, projectedTotal, uniqueLessons.size, rows)
    }

    fun selectedLessonsByID(lessons: List<AbsenceLessonCandidate>): List<AbsenceLessonCandidate> {
        val seen = mutableSetOf<String>()
        return lessons
            .filter { seen.add(it.id) }
            .sortedWith(compareBy({ it.dateKey }, { it.hourID }, { it.subjectName.lowercase() }))
    }

    private fun baselineRow(
        lesson: AbsenceLessonCandidate,
        subjectKey: String,
        rows: List<AbsenceSubjectSummary>,
    ): AbsenceSubjectSummary? {
        val lessonSubject = lesson.subjectName.normalized()
        return rows.firstOrNull { row ->
            row.stableID == subjectKey || row.stableID.endsWith("-$subjectKey") || row.subjectName.normalized() == lessonSubject
        }
    }

    private fun String.normalized(): String = lowercase().replace(Regex("\\s+"), " ").trim()
}
