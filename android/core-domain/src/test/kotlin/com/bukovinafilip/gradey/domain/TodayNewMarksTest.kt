package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class TodayNewMarksTest {
    private val zone = ZoneId.of("Europe/Prague")

    @Test
    fun `cloud events take priority and preserve the backend order`() {
        val local = subject(
            marks = listOf(mark(id = "local", date = "2026-08-30", isNew = true)),
        )
        val cloud = listOf(
            event(id = "first", abbrev = " M ", name = "Mathematics", createdAt = "2026-08-29T08:00:00Z"),
            event(id = "second", abbrev = null, name = " English ", createdAt = "not-a-date"),
        )

        val rows = TodayNewMarks.resolve(listOf(local), cloud, zone)

        assertThat(rows.map { it.id }).containsExactly("history-first", "history-second").inOrder()
        assertThat(rows.map { it.subjectName }).containsExactly("M", "English").inOrder()
        assertThat(rows.first().detectedAt).isEqualTo(Instant.parse("2026-08-29T08:00:00Z"))
        assertThat(rows.last().detectedAt).isNull()
    }

    @Test
    fun `bakalari fallback keeps only new marks and sorts dated entries newest first`() {
        val rows = TodayNewMarks.resolve(
            subjects = listOf(
                subject(
                    id = "math",
                    name = "Mathematics",
                    abbrev = "M",
                    marks = listOf(
                        mark(id = "old", date = "2026-08-30", isNew = false),
                        mark(id = "undated", date = "unknown", isNew = true),
                        mark(id = "older", date = "2026-08-28", isNew = true),
                    ),
                ),
                subject(
                    id = "physics",
                    name = "Physics",
                    abbrev = "F",
                    marks = listOf(mark(id = "newer", date = "2026-08-29T23:30:00Z", isNew = true)),
                ),
            ),
            cloudEvents = emptyList(),
            zoneId = zone,
        )

        assertThat(rows.map { it.id }).containsExactly("mark-newer", "mark-older", "mark-undated").inOrder()
        assertThat(rows.map { it.subjectName }).containsExactly("F", "M", "M").inOrder()
    }

    @Test
    fun `fallback formats points and uses subject name when abbreviation is blank`() {
        val rows = TodayNewMarks.resolve(
            subjects = listOf(
                subject(
                    name = " Mathematics ",
                    abbrev = " ",
                    marks = listOf(
                        mark(
                            id = "points",
                            text = "17",
                            date = "2026-08-30",
                            isNew = true,
                            isPoints = true,
                            pointsText = "17 points",
                            maxPoints = 20,
                        ),
                    ),
                ),
            ),
            cloudEvents = emptyList(),
            zoneId = zone,
        )

        assertThat(rows.single().markText).isEqualTo("17/20")
        assertThat(rows.single().subjectName).isEqualTo("Mathematics")
    }

    private fun event(
        id: String,
        abbrev: String?,
        name: String?,
        createdAt: String,
    ) = NewMarkEvent(
        id = id,
        linkedAccountID = "school",
        provider = LinkedAccountProvider.BAKALARI,
        subjectID = "math",
        subjectAbbrev = abbrev,
        subjectName = name,
        markText = "1",
        createdAt = createdAt,
    )

    private fun subject(
        id: String = "math",
        name: String = "Mathematics",
        abbrev: String = "M",
        marks: List<Mark>,
    ) = Subject(
        marks = marks,
        subjectInfo = SubjectInfo(id = id, name = name, abbrev = abbrev),
    )

    private fun mark(
        id: String,
        text: String = "1",
        date: String,
        isNew: Boolean,
        isPoints: Boolean = false,
        pointsText: String? = null,
        maxPoints: Int? = null,
    ) = Mark(
        id = id,
        markText = text,
        markDate = date,
        isNew = isNew,
        isPoints = isPoints,
        pointsText = pointsText,
        maxPoints = maxPoints,
    )
}
