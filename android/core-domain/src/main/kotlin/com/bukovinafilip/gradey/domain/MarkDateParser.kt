package com.bukovinafilip.gradey.domain

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

object MarkDateParser {
    fun instant(raw: String?, zoneId: ZoneId = ZoneId.systemDefault()): Instant? {
        val value = raw?.trim()?.takeIf(String::isNotEmpty) ?: return null
        return runCatching {
            OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        }.getOrNull() ?: runCatching {
            LocalDate.parse(value.substringBefore('T'), DateTimeFormatter.ISO_LOCAL_DATE)
                .atStartOfDay(zoneId)
                .toInstant()
        }.getOrNull()
    }

    fun localDate(raw: String?, zoneId: ZoneId = ZoneId.systemDefault()): LocalDate? =
        instant(raw, zoneId)?.atZone(zoneId)?.toLocalDate()

    fun <T> newestFirst(
        values: List<T>,
        zoneId: ZoneId = ZoneId.systemDefault(),
        rawDate: (T) -> String?,
    ): List<T> = values
        .withIndex()
        .sortedWith { left, right ->
            val leftInstant = instant(rawDate(left.value), zoneId)
            val rightInstant = instant(rawDate(right.value), zoneId)
            when {
                leftInstant != null && rightInstant != null ->
                    rightInstant.compareTo(leftInstant).takeIf { it != 0 }
                        ?: left.index.compareTo(right.index)
                leftInstant != null -> -1
                rightInstant != null -> 1
                else -> left.index.compareTo(right.index)
            }
        }
        .map(IndexedValue<T>::value)
}
