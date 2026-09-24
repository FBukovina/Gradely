package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Test

class MarkDateParserTest {
    private val prague = ZoneId.of("Europe/Prague")

    @Test
    fun `parses Bakalari ISO timestamps with and without fractional seconds`() {
        assertThat(MarkDateParser.instant("2026-05-31T09:30:00.125+02:00", prague))
            .isEqualTo(Instant.parse("2026-05-31T07:30:00.125Z"))
        assertThat(MarkDateParser.instant("2026-05-31T09:30:00+02:00", prague))
            .isEqualTo(Instant.parse("2026-05-31T07:30:00Z"))
        assertThat(MarkDateParser.instant("2026-05-31T07:30:00Z", prague))
            .isEqualTo(Instant.parse("2026-05-31T07:30:00Z"))
    }

    @Test
    fun `falls back to the ISO calendar date like iOS`() {
        assertThat(MarkDateParser.localDate("2026-05-31", prague)).isEqualTo(LocalDate.of(2026, 5, 31))
        assertThat(MarkDateParser.localDate("2026-05-31Tnot-a-time", prague)).isEqualTo(LocalDate.of(2026, 5, 31))
        assertThat(MarkDateParser.localDate("not-a-date", prague)).isNull()
        assertThat(MarkDateParser.localDate("   ", prague)).isNull()
    }

    @Test
    fun `converts parsed instants into the display timezone`() {
        assertThat(MarkDateParser.localDate("2026-05-31T23:30:00Z", prague))
            .isEqualTo(LocalDate.of(2026, 6, 1))
    }

    @Test
    fun `newest-first ordering uses full instants and leaves invalid values last`() {
        val values = listOf(
            "invalid-first",
            "2026-05-31T09:30:00+02:00",
            "2026-05-31T08:00:00Z",
            "2026-05-30",
            "invalid-second",
        )

        assertThat(MarkDateParser.newestFirst(values, prague) { it }).containsExactly(
            "2026-05-31T08:00:00Z",
            "2026-05-31T09:30:00+02:00",
            "2026-05-30",
            "invalid-first",
            "invalid-second",
        ).inOrder()
    }
}
