package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeHistoryEvent
import com.bukovinafilip.gradey.model.GradeHistoryEventType
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class GradeHistoryTest {
    private val zone = ZoneId.of("Europe/Prague")

    @Test
    fun `trends group events chronologically and calculate the whole-window delta`() {
        val trends = GradeHistoryTrends.make(
            listOf(
                event(id = "latest", subjectID = "math", average = 2.25, markCount = 5, capturedAt = "2026-08-30T10:00:00Z"),
                event(id = "first", subjectID = "math", average = 1.75, markCount = 2, capturedAt = "2026-08-01T10:00:00Z"),
                event(id = "english", subjectID = "eng", average = 1.1, markCount = 3, capturedAt = "2026-08-20T10:00:00Z"),
            ),
        )

        assertThat(trends.map { it.subjectID }).containsExactly("math", "eng").inOrder()
        assertThat(trends.first().events.map { it.id }).containsExactly("first", "latest").inOrder()
        assertThat(trends.first().firstAverage).isEqualTo(1.75)
        assertThat(trends.first().latestAverage).isEqualTo(2.25)
        assertThat(trends.first().averageDelta).isEqualTo(0.5)
        assertThat(trends.first().firstMarkCount).isEqualTo(2)
        assertThat(trends.first().latestMarkCount).isEqualTo(5)
    }

    @Test
    fun `trend matching prefers stable subject id then falls back to name or abbreviation`() {
        val subject = subject(id = "local-id", name = "Mathematics", abbrev = "M")
        val byName = GradeHistoryTrends.make(listOf(event(subjectID = "remote", subjectName = "mathematics")))
        val byAbbrev = GradeHistoryTrends.make(listOf(event(subjectID = "remote", subjectName = null, subjectAbbrev = "m")))
        val byID = GradeHistoryTrends.make(listOf(event(subjectID = "local-id", subjectName = "Other")))

        assertThat(GradeHistoryTrends.matching(subject, byName)?.subjectID).isEqualTo("remote")
        assertThat(GradeHistoryTrends.matching(subject, byAbbrev)?.subjectID).isEqualTo("remote")
        assertThat(GradeHistoryTrends.matching(subject, byID)?.subjectID).isEqualTo("local-id")
    }

    @Test
    fun `recent trends rebuild the window and drop subjects without recent events`() {
        val trends = GradeHistoryTrends.make(
            listOf(
                event(id = "old-math", subjectID = "math", average = 3.0, capturedAt = "2026-04-01T10:00:00Z"),
                event(id = "new-math", subjectID = "math", average = 2.0, capturedAt = "2026-08-20T10:00:00Z"),
                event(id = "old-english", subjectID = "eng", average = 1.5, capturedAt = "2026-03-01T10:00:00Z"),
            ),
        )

        val recent = GradeHistoryTrends.since(trends, Instant.parse("2026-06-01T00:00:00Z"))

        assertThat(recent.map { it.subjectID }).containsExactly("math")
        assertThat(recent.single().events.map { it.id }).containsExactly("new-math")
        assertThat(recent.single().displayName).isEqualTo("M")
    }

    @Test
    fun `two cloud averages take priority and expose the cloud delta`() {
        val trend = GradeHistoryTrends.make(
            listOf(
                event(id = "one", average = 2.0, capturedAt = "2026-08-01T23:30:00Z"),
                event(id = "two", average = 1.5, capturedAt = "2026-08-20T10:00:00Z"),
            ),
        ).single()

        val chart = AverageHistoryPolicy.resolve(subject(marks = listOf(mark("local", "3", "2026-08-10"))), trend, zone)

        assertThat(chart.source).isEqualTo(AverageHistorySource.CLOUD)
        assertThat(chart.points.map { it.id }).containsExactly("one", "two").inOrder()
        assertThat(chart.points.first().date.toString()).isEqualTo("2026-08-02")
        assertThat(chart.averageDelta).isEqualTo(-0.5)
    }

    @Test
    fun `local timeline is weighted chronological and ignores non-grade artifacts`() {
        val subject = subject(
            marks = listOf(
                mark("later", "3", "2026-08-03", weight = 3.0),
                mark("first", "1", "2026-08-01", weight = 1.0),
                mark("points", "20", "2026-08-02", isPoints = true),
                mark("unsupported", "2", "2026-08-02", type = "unsupported"),
                mark("undated", "2", "not-a-date"),
                mark("out-of-range", "8", "2026-08-02"),
            ),
        )

        val chart = AverageHistoryPolicy.resolve(subject, trend = null, zone)

        assertThat(chart.source).isEqualTo(AverageHistorySource.LOCAL)
        assertThat(chart.points.map { it.id }).containsExactly("first", "later").inOrder()
        assertThat(chart.points.map { it.average }).containsExactly(1.0, 2.5).inOrder()
        assertThat(chart.averageDelta).isEqualTo(1.5)
    }

    @Test
    fun `one cloud point falls back locally and points-only data has an honest empty state`() {
        val oneCloudPoint = GradeHistoryTrends.make(listOf(event(average = 1.4))).single()
        val local = AverageHistoryPolicy.resolve(
            subject(marks = listOf(mark("local", "2", "2026-08-01"))),
            oneCloudPoint,
            zone,
        )
        val empty = AverageHistoryPolicy.resolve(
            subject(marks = listOf(mark("points", "25", "2026-08-01", isPoints = true))),
            trend = null,
            zone,
        )

        assertThat(local.source).isEqualTo(AverageHistorySource.LOCAL)
        assertThat(local.points.single().id).isEqualTo("local")
        assertThat(empty.source).isEqualTo(AverageHistorySource.NONE)
        assertThat(empty.points).isEmpty()
    }

    @Test
    fun `focus score matches iOS inputs and only penalizes worsening movement`() {
        val markedSubject = subject(marks = listOf(mark("one", "3", "2026-08-01"))).copy(averageText = "3.0")
        val worsening = GradeHistoryTrends.make(
            listOf(
                event(id = "first", average = 2.0, capturedAt = "2026-08-01T10:00:00Z"),
                event(id = "latest", average = 2.5, capturedAt = "2026-08-20T10:00:00Z"),
            ),
        ).single()
        val improving = worsening.copy(averageDelta = -0.5)

        assertThat(SubjectAttentionScore.value(markedSubject, 25.0, worsening)).isEqualTo(5.0)
        assertThat(SubjectAttentionScore.value(markedSubject, 25.0, improving)).isEqualTo(4.0)
        assertThat(SubjectAttentionScore.value(subject(), null, null)).isEqualTo(-2.0)
    }

    private fun event(
        id: String = "event",
        subjectID: String = "math",
        subjectName: String? = "Mathematics",
        subjectAbbrev: String? = "M",
        average: Double? = 2.0,
        markCount: Int = 1,
        capturedAt: String = "2026-08-01T10:00:00Z",
    ) = GradeHistoryEvent(
        id = id,
        linkedAccountID = "school",
        provider = LinkedAccountProvider.BAKALARI,
        subjectID = subjectID,
        subjectAbbrev = subjectAbbrev,
        subjectName = subjectName,
        averageValue = average,
        markCount = markCount,
        averageDelta = null,
        markCountDelta = 0,
        eventType = GradeHistoryEventType.CHANGED,
        capturedAt = capturedAt,
    )

    private fun subject(
        id: String = "math",
        name: String = "Mathematics",
        abbrev: String = "M",
        marks: List<Mark> = emptyList(),
    ) = Subject(
        marks = marks,
        subjectInfo = SubjectInfo(id = id, name = name, abbrev = abbrev),
    )

    private fun mark(
        id: String,
        text: String,
        date: String,
        weight: Double? = null,
        isPoints: Boolean = false,
        type: String? = "exam",
    ) = Mark(
        id = id,
        markText = text,
        markDate = date,
        weight = weight,
        isPoints = isPoints,
        type = type,
    )
}
