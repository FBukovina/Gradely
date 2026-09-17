package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class TimetableDatesTest {
    @Test
    fun springDstBoundaryUsesPragueDateRegardlessOfClockZone() {
        val instant = Instant.parse("2026-03-29T22:30:00Z")
        val deviceClock = Clock.fixed(instant, ZoneId.of("America/Los_Angeles"))

        assertThat(TimetableDates.today(deviceClock)).isEqualTo(LocalDate.of(2026, 3, 30))
        assertThat(TimetableDates.todayString(deviceClock)).isEqualTo("2026-03-30")
        assertThat(TimetableDates.monday(TimetableDates.today(deviceClock))).isEqualTo(LocalDate.of(2026, 3, 30))
    }

    @Test
    fun autumnDstBoundaryUsesPragueDateRegardlessOfClockZone() {
        val instant = Instant.parse("2026-10-25T23:30:00Z")
        val deviceClock = Clock.fixed(instant, ZoneId.of("Pacific/Honolulu"))

        assertThat(TimetableDates.today(deviceClock)).isEqualTo(LocalDate.of(2026, 10, 26))
        assertThat(TimetableDates.monday(TimetableDates.today(deviceClock))).isEqualTo(LocalDate.of(2026, 10, 26))
    }

    @Test
    fun weekContainingSundayStartsOnPreviousMonday() {
        assertThat(TimetableDates.monday(LocalDate.of(2026, 8, 30)))
            .isEqualTo(LocalDate.of(2026, 8, 24))
    }
}
