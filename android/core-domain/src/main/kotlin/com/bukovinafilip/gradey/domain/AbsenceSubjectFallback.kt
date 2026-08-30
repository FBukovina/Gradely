package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Absence
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableResponse
import java.text.Normalizer
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters
import java.util.Locale

enum class AbsenceSubjectResolutionSource {
    OFFICIAL,
    SYNTHESIZED,
    PARTIAL_SYNTHESIZED,
    UNAVAILABLE,
}

enum class AbsenceSubjectResolutionFailure {
    NO_USABLE_TIMETABLE,
}

data class AbsenceSubjectResolutionProgress(
    val loadedWeeks: Int,
    val completedWeeks: Int,
    val totalWeeks: Int,
)

data class AbsenceSubjectResolution(
    val subjects: List<AbsencePerSubject>,
    val source: AbsenceSubjectResolutionSource,
    val loadedWeeks: Int = 0,
    val totalWeeks: Int = 0,
    val failure: AbsenceSubjectResolutionFailure? = null,
) {
    val isPartial: Boolean get() = source == AbsenceSubjectResolutionSource.PARTIAL_SYNTHESIZED
}

data class AbsenceTerm(
    val start: LocalDate,
    val endInclusive: LocalDate,
    val weekStarts: List<LocalDate>,
)

object AbsenceTerms {
    fun resolve(response: AbsenceResponse, now: LocalDate): AbsenceTerm {
        val latestAbsenceDate = response.absences
            .mapNotNull { parseDate(it.date) }
            .maxOrNull()
            ?: now
        val selectedBounds = bounds(latestAbsenceDate)
        val currentBounds = bounds(now)
        val end = if (selectedBounds == currentBounds) {
            minOf(now, selectedBounds.second)
        } else {
            selectedBounds.second
        }
        val firstMonday = selectedBounds.first.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val lastMonday = end.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val weeks = generateSequence(firstMonday) { it.plusWeeks(1) }
            .takeWhile { !it.isAfter(lastMonday) }
            .toList()
        return AbsenceTerm(selectedBounds.first, end, weeks)
    }

    private fun bounds(date: LocalDate): Pair<LocalDate, LocalDate> = when (date.monthValue) {
        1 -> LocalDate.of(date.year - 1, 9, 1) to LocalDate.of(date.year, 1, 31)
        in 2..6 -> LocalDate.of(date.year, 2, 1) to LocalDate.of(date.year, 6, 30)
        in 7..8 -> LocalDate.of(date.year, 2, 1) to LocalDate.of(date.year, 6, 30)
        else -> LocalDate.of(date.year, 9, 1) to LocalDate.of(date.year + 1, 1, 31)
    }

    internal fun parseDate(value: String): LocalDate? =
        runCatching { LocalDate.parse(value.take(10)) }.getOrNull()
}

object AbsenceSubjectFallback {
    fun makeSubjects(
        response: AbsenceResponse,
        timetables: List<TimetableResponse>,
        markSubjects: List<Subject>,
        validDateRange: ClosedRange<LocalDate>,
    ): List<AbsencePerSubject> {
        if (response.absencesPerSubject.isNotEmpty()) return response.absencesPerSubject
        if (response.absences.isEmpty() || timetables.isEmpty()) return emptyList()

        val absencesByDate = response.absences
            .mapNotNull { absence -> AbsenceTerms.parseDate(absence.date)?.let { it to absence } }
            .groupBy(keySelector = { it.first }, valueTransform = { it.second })
            .mapValues { (_, rows: List<Absence>) -> rows.sumOf { it.unsolved + it.ok + it.missed } }
        val catalog = SubjectCatalog(markSubjects)
        val totals = linkedMapOf<String, MutableSubjectTotal>()
        var assignedAnyFullDay = false

        timetables.forEach { timetable ->
            timetable.days.forEach { day ->
                val date = AbsenceTerms.parseDate(day.date) ?: return@forEach
                if (date !in validDateRange) return@forEach
                val lessons = countableLessons(day.atoms, timetable.subjects, catalog)
                if (lessons.isEmpty()) return@forEach

                lessons.forEach { lesson ->
                    totals.getOrPut(lesson.key) { MutableSubjectTotal(lesson.displayName) }.lessonsCount += 1
                }

                val absentHours = absencesByDate[date] ?: 0
                if (absentHours >= lessons.size) {
                    lessons.forEach { lesson -> totals.getValue(lesson.key).base += 1 }
                    assignedAnyFullDay = true
                }
            }
        }

        if (!assignedAnyFullDay) return emptyList()
        return totals.values
            .filter { it.lessonsCount > 0 }
            .map { total ->
                AbsencePerSubject(
                    subjectName = total.displayName,
                    lessonsCount = total.lessonsCount,
                    base = total.base,
                )
            }
    }

    private fun countableLessons(
        atoms: List<TimetableAtom>,
        timetableSubjects: List<TimetableEntity>,
        catalog: SubjectCatalog,
    ): List<ResolvedLesson> {
        val subjectsByID = timetableSubjects.associateBy { it.id }
        val seen = mutableSetOf<String>()
        return atoms.mapNotNull { atom ->
            if (LessonChangeKind.fromApi(atom.change?.changeType) == LessonChangeKind.CANCELED) return@mapNotNull null
            val rawReference = atom.subjectID?.trim().orEmpty()
            if (rawReference.isEmpty()) return@mapNotNull null
            val entity = subjectsByID[rawReference] ?: timetableSubjects.firstOrNull { candidate ->
                listOf(candidate.id, candidate.abbrev, candidate.name)
                    .filterNotNull()
                    .any { normalize(it) == normalize(rawReference) }
            }
            val resolved = catalog.resolve(entity?.id ?: rawReference, entity)
            if (!seen.add("${atom.hourID}#${resolved.key}")) return@mapNotNull null
            resolved
        }
    }

    private data class ResolvedLesson(val key: String, val displayName: String)

    private data class MutableSubjectTotal(
        val displayName: String,
        var lessonsCount: Int = 0,
        var base: Int = 0,
    )

    private class SubjectCatalog(markSubjects: List<Subject>) {
        private val marksByID = markSubjects
            .mapNotNull { subject -> subject.id.trim().takeIf(String::isNotEmpty)?.let { it to subject } }
            .toMap()
        private val marksByText = buildMap {
            markSubjects.forEach { subject ->
                listOf(subject.subjectInfo.name, subject.subjectInfo.abbrev).forEach { value ->
                    normalize(value).takeIf(String::isNotEmpty)?.let { putIfAbsent(it, subject) }
                }
            }
        }
        private val resolvedByKey = linkedMapOf<String, ResolvedLesson>()

        fun resolve(rawID: String, entity: TimetableEntity?): ResolvedLesson {
            val normalizedRawID = normalize(rawID)
            val key = if (normalizedRawID.isNotEmpty()) "raw-$normalizedRawID" else {
                "text-${normalize(entity?.name ?: entity?.abbrev.orEmpty()).ifEmpty { "unknown" }}"
            }
            return resolvedByKey.getOrPut(key) {
                val mark = marksByID[rawID.trim()]
                    ?: listOfNotNull(entity?.name, entity?.abbrev, rawID)
                        .firstNotNullOfOrNull { marksByText[normalize(it)] }
                val displayName = mark?.displayName?.trim()?.takeIf(String::isNotEmpty)
                    ?: entity?.name?.trim()?.takeIf(String::isNotEmpty)
                    ?: entity?.abbrev?.trim()?.takeIf(String::isNotEmpty)
                    ?: rawID.trim().ifEmpty { "Subject" }
                ResolvedLesson(key, displayName)
            }
        }
    }

    internal fun normalize(value: String): String = Normalizer.normalize(value.trim(), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ")
}
