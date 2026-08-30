package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeHistoryEvent
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max

data class SubjectGradeTrend(
    val subjectID: String,
    val subjectAbbrev: String?,
    val subjectName: String?,
    val firstAverage: Double?,
    val latestAverage: Double?,
    val averageDelta: Double?,
    val firstMarkCount: Int,
    val latestMarkCount: Int,
    val events: List<GradeHistoryEvent>,
) {
    val displayName: String
        get() = subjectAbbrev?.trim()?.takeIf(String::isNotEmpty)
            ?: subjectName?.trim()?.takeIf(String::isNotEmpty)
            ?: subjectID
}

enum class GradeTrendRange(val days: Long?) {
    THIRTY_DAYS(30),
    NINETY_DAYS(90),
    SCHOOL_YEAR(null),
}

object GradeHistoryTrends {
    fun make(events: List<GradeHistoryEvent>): List<SubjectGradeTrend> = events
        .groupBy(GradeHistoryEvent::subjectID)
        .map { (subjectID, subjectEvents) ->
            val sorted = subjectEvents.sortedWith(
                compareBy<GradeHistoryEvent> { it.capturedInstant() ?: Instant.MAX }
                    .thenBy(GradeHistoryEvent::id),
            )
            val first = sorted.firstOrNull()
            val latest = sorted.lastOrNull()
            val firstAverage = first?.averageValue
            val latestAverage = latest?.averageValue
            SubjectGradeTrend(
                subjectID = subjectID,
                subjectAbbrev = latest?.subjectAbbrev ?: first?.subjectAbbrev,
                subjectName = latest?.subjectName ?: first?.subjectName,
                firstAverage = firstAverage,
                latestAverage = latestAverage,
                averageDelta = if (firstAverage != null && latestAverage != null) {
                    latestAverage - firstAverage
                } else {
                    latest?.averageDelta
                },
                firstMarkCount = first?.markCount ?: 0,
                latestMarkCount = latest?.markCount ?: 0,
                events = sorted,
            )
        }
        .sortedWith(
            compareByDescending<SubjectGradeTrend> { abs(it.averageDelta ?: 0.0) }
                .thenBy(SubjectGradeTrend::subjectID),
        )

    fun since(trends: List<SubjectGradeTrend>, cutoff: Instant): List<SubjectGradeTrend> = make(
        trends.flatMap(SubjectGradeTrend::events).filter { event ->
            event.capturedInstant()?.let { it >= cutoff } == true
        },
    )

    fun inRange(
        trends: List<SubjectGradeTrend>,
        range: GradeTrendRange,
        now: Instant = Instant.now(),
    ): List<SubjectGradeTrend> = range.days?.let { days ->
        since(trends, now.minus(days, ChronoUnit.DAYS))
    } ?: trends

    fun matching(subject: Subject, trends: List<SubjectGradeTrend>): SubjectGradeTrend? {
        trends.firstOrNull { it.subjectID == subject.id }?.let { return it }
        val subjectName = subject.subjectInfo.name.trim()
        val subjectAbbrev = subject.subjectInfo.abbrev.trim()
        return trends.firstOrNull { trend ->
            trend.subjectName.matchesNonBlank(subjectName) || trend.subjectAbbrev.matchesNonBlank(subjectAbbrev)
        }
    }

    private fun String?.matchesNonBlank(other: String): Boolean =
        !isNullOrBlank() && other.isNotBlank() && trim().equals(other, ignoreCase = true)
}

enum class AverageHistorySource {
    CLOUD,
    LOCAL,
    NONE,
}

data class AverageHistoryPoint(
    val id: String,
    val date: LocalDate?,
    val average: Double,
)

data class AverageHistoryChart(
    val source: AverageHistorySource,
    val points: List<AverageHistoryPoint>,
    val averageDelta: Double?,
)

object AverageHistoryPolicy {
    private val GradableRange = 0.9..5.7

    fun resolve(
        subject: Subject,
        trend: SubjectGradeTrend?,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): AverageHistoryChart {
        val cloudPoints = trend?.events.orEmpty()
            .mapNotNull { event ->
                event.averageValue?.let { average ->
                    AverageHistoryPoint(
                        id = event.id,
                        date = event.capturedInstant()?.atZone(zoneId)?.toLocalDate(),
                        average = average,
                    )
                }
            }
        if (cloudPoints.size >= 2) {
            return AverageHistoryChart(AverageHistorySource.CLOUD, cloudPoints, trend?.averageDelta)
        }

        val localPoints = localPoints(subject, zoneId)
        if (localPoints.isEmpty()) return AverageHistoryChart(AverageHistorySource.NONE, emptyList(), null)
        val delta = localPoints.takeIf { it.size > 1 }?.let { it.last().average - it.first().average }
        return AverageHistoryChart(AverageHistorySource.LOCAL, localPoints, delta)
    }

    private fun localPoints(subject: Subject, zoneId: ZoneId): List<AverageHistoryPoint> {
        val weights = GradeMath.resolvedWeights(subject)
        val samples = subject.marks
            .mapNotNull { mark -> mark.localSample(zoneId) }
            .sortedWith(compareBy<LocalSample>(LocalSample::instant).thenBy { it.mark.id })
        var totalWeight = 0.0
        var weightedSum = 0.0
        return samples.map { sample ->
            val weight = weights[sample.mark.id]?.value ?: 1.0
            totalWeight += weight
            weightedSum += sample.value * weight
            AverageHistoryPoint(
                id = sample.mark.id,
                date = sample.instant.atZone(zoneId).toLocalDate(),
                average = weightedSum / totalWeight,
            )
        }
    }

    private fun Mark.localSample(zoneId: ZoneId): LocalSample? {
        if (isPoints || type == "unsupported") return null
        val instant = MarkDateParser.instant(markDate, zoneId) ?: return null
        val value = GradeMath.parseMarkValue(markText)?.takeIf(GradableRange::contains) ?: return null
        return LocalSample(this, instant, value)
    }

    private data class LocalSample(val mark: Mark, val instant: Instant, val value: Double)
}

object SubjectAttentionScore {
    fun value(
        subject: Subject,
        absencePercentage: Double?,
        trend: SubjectGradeTrend?,
    ): Double = (GradeMath.subjectAverage(subject) ?: 0.0) +
        max(trend?.averageDelta ?: 0.0, 0.0) * 2.0 +
        (absencePercentage ?: 0.0) / 25.0 -
        if (subject.marks.isEmpty()) 2.0 else 0.0
}

private fun GradeHistoryEvent.capturedInstant(): Instant? = runCatching { Instant.parse(capturedAt) }.getOrNull()
