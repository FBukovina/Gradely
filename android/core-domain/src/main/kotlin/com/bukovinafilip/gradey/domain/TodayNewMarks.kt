package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.Subject
import java.time.Instant
import java.time.ZoneId

data class TodayNewMark(
    val id: String,
    val markText: String,
    val subjectName: String,
    val detectedAt: Instant?,
)

object TodayNewMarks {
    fun resolve(
        subjects: List<Subject>,
        cloudEvents: List<NewMarkEvent>,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<TodayNewMark> {
        if (cloudEvents.isNotEmpty()) {
            return cloudEvents.map { event ->
                TodayNewMark(
                    id = "history-${event.id}",
                    markText = event.markText,
                    subjectName = event.subjectAbbrev.nonBlank()
                        ?: event.subjectName.nonBlank()
                        ?: "school",
                    detectedAt = event.createdAt.asInstant(),
                )
            }
        }

        return subjects
            .flatMap { subject ->
                subject.marks.filter(Mark::isNew).map { mark ->
                    TodayNewMark(
                        id = "mark-${mark.id}",
                        markText = mark.displayText(),
                        subjectName = subject.subjectInfo.abbrev.nonBlank()
                            ?: subject.subjectInfo.name.nonBlank()
                            ?: "school",
                        detectedAt = MarkDateParser.instant(mark.markDate, zoneId),
                    )
                }
            }
            .withIndex()
            .sortedWith { left, right ->
                val leftInstant = left.value.detectedAt
                val rightInstant = right.value.detectedAt
                when {
                    leftInstant != null && rightInstant != null ->
                        rightInstant.compareTo(leftInstant).takeIf { it != 0 }
                            ?: left.index.compareTo(right.index)
                    leftInstant != null -> -1
                    rightInstant != null -> 1
                    else -> left.index.compareTo(right.index)
                }
            }
            .map(IndexedValue<TodayNewMark>::value)
    }

    private fun Mark.displayText(): String = if (
        isPoints && !pointsText.isNullOrBlank() && maxPoints != null
    ) {
        "$markText/$maxPoints"
    } else {
        markText
    }

    private fun String?.nonBlank(): String? = this?.trim()?.takeIf(String::isNotEmpty)

    private fun String.asInstant(): Instant? = runCatching { Instant.parse(this) }.getOrNull()
}
