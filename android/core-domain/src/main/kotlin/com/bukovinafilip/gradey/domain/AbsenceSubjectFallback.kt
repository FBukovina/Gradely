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
import kotlinx.serialization.Serializable

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
    val unresolvedPartialDays: List<AbsencePartialDayCandidate> = emptyList(),
    val appliedManualSelectionCount: Int = 0,
) {
    val isPartial: Boolean get() = source == AbsenceSubjectResolutionSource.PARTIAL_SYNTHESIZED
}

@Serializable
data class AbsenceLessonSelections(
    val selectedLessonIDsByDate: Map<String, List<String>> = emptyMap(),
) {
    fun selectedLessonIDs(dateKey: String): Set<String> =
        selectedLessonIDsByDate[dateKey].orEmpty().toSet()
}

data class AbsencePartialDayCandidate(
    val dateKey: String,
    val requiredSelectionCount: Int,
    val selectedLessonIDs: List<String>,
    val lessons: List<AbsenceLessonCandidate>,
)

data class AbsenceSubjectFallbackResult(
    val subjects: List<AbsencePerSubject>,
    val unresolvedPartialDays: List<AbsencePartialDayCandidate>,
    val appliedManualSelectionCount: Int,
)

object AbsenceManualSelectionPolicy {
    fun toggle(current: Set<String>, lessonID: String, requiredSelectionCount: Int): Set<String> {
        val selected = current.toMutableSet()
        if (!selected.remove(lessonID) && selected.size < requiredSelectionCount) selected += lessonID
        return selected
    }

    fun canSave(
        days: List<AbsencePartialDayCandidate>,
        drafts: Map<String, Set<String>>,
    ): Boolean = days.isNotEmpty() && days.all { day ->
        drafts[day.dateKey].orEmpty().size == day.requiredSelectionCount
    }
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
    fun lessonCandidates(
        date: LocalDate,
        timetable: TimetableResponse,
        markSubjects: List<Subject>,
    ): List<AbsenceLessonCandidate> {
        val dateKey = TimetableDates.apiDateString(date)
        val day = timetable.days.firstOrNull { AbsenceTerms.parseDate(it.date) == date }
            ?: return emptyList()
        return countableLessons(
            dateKey = dateKey,
            atoms = day.atoms,
            timetable = timetable,
            catalog = SubjectCatalog(markSubjects),
        ).map(CountableLesson::candidate)
    }

    fun makeSubjects(
        response: AbsenceResponse,
        timetables: List<TimetableResponse>,
        markSubjects: List<Subject>,
        validDateRange: ClosedRange<LocalDate>,
        manualSelections: AbsenceLessonSelections = AbsenceLessonSelections(),
    ): List<AbsencePerSubject> = makeResult(
        response = response,
        timetables = timetables,
        markSubjects = markSubjects,
        validDateRange = validDateRange,
        manualSelections = manualSelections,
    ).subjects

    fun makeResult(
        response: AbsenceResponse,
        timetables: List<TimetableResponse>,
        markSubjects: List<Subject>,
        validDateRange: ClosedRange<LocalDate>,
        manualSelections: AbsenceLessonSelections = AbsenceLessonSelections(),
    ): AbsenceSubjectFallbackResult {
        if (response.absencesPerSubject.isNotEmpty()) {
            return AbsenceSubjectFallbackResult(response.absencesPerSubject, emptyList(), 0)
        }
        if (response.absences.isEmpty() || timetables.isEmpty()) {
            return AbsenceSubjectFallbackResult(emptyList(), emptyList(), 0)
        }

        val absencesByDate = response.absences
            .mapNotNull { absence -> AbsenceTerms.parseDate(absence.date)?.let { it to absence } }
            .groupBy(keySelector = { it.first }, valueTransform = { it.second })
            .mapValues { (_, rows: List<Absence>) -> rows.sumOf { it.unsolved + it.ok + it.missed } }
        val catalog = SubjectCatalog(markSubjects)
        val totals = linkedMapOf<String, MutableSubjectTotal>()
        var assignedAnyFullDay = false
        var appliedManualSelectionCount = 0
        val unresolvedPartialDays = linkedMapOf<String, AbsencePartialDayCandidate>()

        timetables.forEach { timetable ->
            timetable.days.forEach { day ->
                val date = AbsenceTerms.parseDate(day.date) ?: return@forEach
                if (date !in validDateRange) return@forEach
                val dateKey = TimetableDates.apiDateString(date)
                val lessons = countableLessons(dateKey, day.atoms, timetable, catalog)
                if (lessons.isEmpty()) return@forEach

                lessons.forEach { lesson ->
                    totals.getOrPut(lesson.key) { MutableSubjectTotal(lesson.displayName) }.lessonsCount += 1
                }

                val absentHours = absencesByDate[date] ?: 0
                if (absentHours >= lessons.size) {
                    lessons.forEach { lesson -> totals.getValue(lesson.key).base += 1 }
                    assignedAnyFullDay = true
                } else if (absentHours > 0) {
                    val validLessonIDs = lessons.mapTo(mutableSetOf()) { it.id }
                    val selectedLessonIDs = manualSelections.selectedLessonIDs(dateKey).intersect(validLessonIDs)
                    if (selectedLessonIDs.size == absentHours) {
                        lessons.filter { it.id in selectedLessonIDs }.forEach { lesson ->
                            totals.getValue(lesson.key).base += 1
                            appliedManualSelectionCount += 1
                        }
                        assignedAnyFullDay = true
                    } else {
                        unresolvedPartialDays[dateKey] = AbsencePartialDayCandidate(
                            dateKey = dateKey,
                            requiredSelectionCount = minOf(absentHours, lessons.size),
                            selectedLessonIDs = selectedLessonIDs.sorted(),
                            lessons = lessons.map(CountableLesson::candidate),
                        )
                    }
                }
            }
        }

        val unresolved = unresolvedPartialDays.values.sortedBy(AbsencePartialDayCandidate::dateKey)
        if (!assignedAnyFullDay && unresolved.isEmpty()) {
            return AbsenceSubjectFallbackResult(emptyList(), emptyList(), 0)
        }
        val subjects = totals.values
            .filter { it.lessonsCount > 0 }
            .map { total ->
                AbsencePerSubject(
                    subjectName = total.displayName,
                    lessonsCount = total.lessonsCount,
                    base = total.base,
                )
            }
        return AbsenceSubjectFallbackResult(subjects, unresolved, appliedManualSelectionCount)
    }

    private fun countableLessons(
        dateKey: String,
        atoms: List<TimetableAtom>,
        timetable: TimetableResponse,
        catalog: SubjectCatalog,
    ): List<CountableLesson> {
        val subjectsByID = timetable.subjects.associateBy { it.id }
        val hoursByID = timetable.hours.associateBy { it.id }
        val hourOrder = timetable.hours.mapIndexed { index, hour -> hour.id to index }.toMap()
        val seen = mutableSetOf<String>()
        return atoms.mapNotNull { atom ->
            if (LessonChangeKind.fromApi(atom.change?.changeType) == LessonChangeKind.CANCELED) return@mapNotNull null
            val changedReference = atom.change?.changeSubject?.trim().orEmpty()
            val rawReference = changedReference.takeIf(String::isNotEmpty)
                ?: atom.subjectID?.trim()?.takeIf(String::isNotEmpty)
                ?: return@mapNotNull null
            val entity = subjectsByID[rawReference] ?: timetable.subjects.firstOrNull { candidate ->
                listOf(candidate.id, candidate.abbrev, candidate.name)
                    .filterNotNull()
                    .any { normalize(it) == normalize(rawReference) }
            }
            val subject = catalog.resolve(entity?.id ?: rawReference, entity)
            if (!seen.add("${atom.hourID}#${subject.key}")) return@mapNotNull null
            val hour = hoursByID[atom.hourID]
            val caption = hour?.caption?.trim().orEmpty().ifEmpty { atom.hourID }
            val beginTime = hour?.beginTime?.trim().orEmpty()
            val endTime = hour?.endTime?.trim().orEmpty()
            val timeRange = if (beginTime.isNotEmpty() && endTime.isNotEmpty()) "$beginTime-$endTime" else ""
            CountableLesson(
                id = "lesson-$dateKey-${atom.hourID}-${storageSafe(subject.key)}",
                dateKey = dateKey,
                hourID = atom.hourID,
                hourCaption = caption,
                timeRange = timeRange,
                key = subject.key,
                displayName = subject.displayName,
            )
        }.sortedWith(
            compareBy<CountableLesson> { hourOrder[it.hourID] ?: Int.MAX_VALUE }
                .thenBy { it.hourID.toIntOrNull() ?: Int.MAX_VALUE }
                .thenBy(CountableLesson::hourID)
                .thenBy(CountableLesson::displayName),
        )
    }

    private data class ResolvedSubject(val key: String, val displayName: String)

    private data class CountableLesson(
        val id: String,
        val dateKey: String,
        val hourID: String,
        val hourCaption: String,
        val timeRange: String,
        val key: String,
        val displayName: String,
    ) {
        val candidate: AbsenceLessonCandidate get() = AbsenceLessonCandidate(
            id = id,
            dateKey = dateKey,
            hourID = hourID,
            hourCaption = hourCaption,
            timeRange = timeRange,
            subjectKey = key,
            subjectName = displayName,
        )
    }

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
        private val resolvedByKey = linkedMapOf<String, ResolvedSubject>()

        fun resolve(rawID: String, entity: TimetableEntity?): ResolvedSubject {
            val normalizedRawID = normalize(rawID)
            val entityText = listOfNotNull(entity?.name, entity?.abbrev)
                .firstNotNullOfOrNull { normalize(it).takeIf(String::isNotEmpty) }
            val key = when {
                normalizedRawID.isNotEmpty() -> "raw-$normalizedRawID"
                entityText != null -> "text-$entityText"
                else -> "raw-blank"
            }
            return resolvedByKey.getOrPut(key) {
                val mark = marksByID[rawID.trim()]
                    ?: listOfNotNull(entity?.name, entity?.abbrev, rawID)
                        .firstNotNullOfOrNull { marksByText[normalize(it)] }
                val displayName = mark?.displayName?.trim()?.takeIf(String::isNotEmpty)
                    ?: entity?.name?.trim()?.takeIf(String::isNotEmpty)
                    ?: entity?.abbrev?.trim()?.takeIf(String::isNotEmpty)
                    ?: rawID.trim()
                ResolvedSubject(key, displayName)
            }
        }
    }

    private fun storageSafe(value: String): String = normalize(value)
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')
        .ifEmpty { "unknown" }
        .take(80)

    internal fun normalize(value: String): String = Normalizer.normalize(value.trim(), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ")
}
