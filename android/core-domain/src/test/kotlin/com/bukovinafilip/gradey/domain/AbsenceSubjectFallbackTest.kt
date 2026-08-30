package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Absence
import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableDayDTO
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import org.junit.Test

class AbsenceSubjectFallbackTest {
    @Test
    fun currentTermStopsAtTodayAndIncludesBoundaryMondays() {
        val term = AbsenceTerms.resolve(
            response = AbsenceResponse(absences = listOf(Absence("2026-02-03", ok = 1))),
            now = LocalDate.of(2026, 2, 8),
        )

        assertThat(term.start).isEqualTo(LocalDate.of(2026, 2, 1))
        assertThat(term.endInclusive).isEqualTo(LocalDate.of(2026, 2, 8))
        assertThat(term.weekStarts).containsExactly(
            LocalDate.of(2026, 1, 26),
            LocalDate.of(2026, 2, 2),
        ).inOrder()
    }

    @Test
    fun historicalSummerAbsenceUsesCompletedSpringTerm() {
        val term = AbsenceTerms.resolve(
            response = AbsenceResponse(absences = listOf(Absence("2025-07-10", ok = 1))),
            now = LocalDate.of(2026, 2, 8),
        )

        assertThat(term.start).isEqualTo(LocalDate.of(2025, 2, 1))
        assertThat(term.endInclusive).isEqualTo(LocalDate.of(2025, 6, 30))
        assertThat(term.weekStarts.first()).isEqualTo(LocalDate.of(2025, 1, 27))
        assertThat(term.weekStarts.last()).isEqualTo(LocalDate.of(2025, 6, 30))
    }

    @Test
    fun officialSubjectsAlwaysWinWithoutTimetableSynthesis() {
        val official = listOf(AbsencePerSubject("Official Mathematics", lessonsCount = 40, base = 5))

        val subjects = AbsenceSubjectFallback.makeSubjects(
            response = AbsenceResponse(
                absences = listOf(Absence("2026-02-03", ok = 1)),
                absencesPerSubject = official,
            ),
            timetables = emptyList(),
            markSubjects = emptyList(),
            validDateRange = LocalDate.of(2026, 2, 1)..LocalDate.of(2026, 2, 8),
        )

        assertThat(subjects).isEqualTo(official)
    }

    @Test
    fun fullDayAbsenceIsSynthesizedAgainstAllLoadedTermLessons() {
        val timetable = TimetableResponse(
            subjects = listOf(
                TimetableEntity(id = "math", abbrev = "M", name = "Math alias"),
                TimetableEntity(id = "czech", abbrev = "ČJ", name = "Czech"),
            ),
            days = listOf(
                TimetableDayDTO(
                    date = "2026-02-03",
                    atoms = listOf(
                        TimetableAtom(hourID = "1", subjectID = "math"),
                        TimetableAtom(hourID = "2", subjectID = "czech"),
                    ),
                ),
                TimetableDayDTO(
                    date = "2026-02-04",
                    atoms = listOf(
                        TimetableAtom(hourID = "1", subjectID = "math"),
                        TimetableAtom(hourID = "2", subjectID = "czech"),
                    ),
                ),
            ),
        )
        val markSubjects = listOf(
            Subject(subjectInfo = SubjectInfo(id = "math", abbrev = "MAT", name = "Mathematics")),
            Subject(subjectInfo = SubjectInfo(id = "czech", abbrev = "CJ", name = "Czech language")),
        )

        val subjects = AbsenceSubjectFallback.makeSubjects(
            response = AbsenceResponse(absences = listOf(Absence("2026-02-03", ok = 2))),
            timetables = listOf(timetable),
            markSubjects = markSubjects,
            validDateRange = LocalDate.of(2026, 2, 1)..LocalDate.of(2026, 2, 8),
        )

        assertThat(subjects).containsExactly(
            AbsencePerSubject("Mathematics", lessonsCount = 2, base = 1),
            AbsencePerSubject("Czech language", lessonsCount = 2, base = 1),
        ).inOrder()
    }

    @Test
    fun partialDayRequiresExactLessonsThenRecomputesSelectedSubjects() {
        val timetable = TimetableResponse(
            hours = listOf(
                TimetableHour("1", "1", "08:00", "08:45"),
                TimetableHour("2", "2", "08:55", "09:40"),
                TimetableHour("3", "3", "09:50", "10:35"),
            ),
            subjects = listOf(
                TimetableEntity("math", "MAT", "Mathematics"),
                TimetableEntity("czech", "CJ", "Czech"),
                TimetableEntity("english", "AJ", "English"),
            ),
            days = listOf(
                TimetableDayDTO(
                    date = "2026-02-03",
                    atoms = listOf(
                        TimetableAtom(hourID = "1", subjectID = "math"),
                        TimetableAtom(hourID = "2", subjectID = "czech"),
                        TimetableAtom(hourID = "3", subjectID = "english"),
                    ),
                ),
            ),
        )
        val response = AbsenceResponse(absences = listOf(Absence("2026-02-03", ok = 2)))
        val range = LocalDate.of(2026, 2, 1)..LocalDate.of(2026, 2, 8)

        val unresolved = AbsenceSubjectFallback.makeResult(response, listOf(timetable), emptyList(), range)
        val day = unresolved.unresolvedPartialDays.single()

        assertThat(day.requiredSelectionCount).isEqualTo(2)
        assertThat(day.selectedLessonIDs).isEmpty()
        assertThat(day.lessons.map { it.hourCaption }).containsExactly("1", "2", "3").inOrder()
        assertThat(day.lessons.first().timeRange).isEqualTo("08:00-08:45")
        assertThat(unresolved.subjects.map { it.base }).containsExactly(0, 0, 0).inOrder()

        val selectedIDs = setOf(day.lessons[0].id, day.lessons[2].id)
        val resolved = AbsenceSubjectFallback.makeResult(
            response = response,
            timetables = listOf(timetable),
            markSubjects = emptyList(),
            validDateRange = range,
            manualSelections = AbsenceLessonSelections(mapOf(day.dateKey to selectedIDs.sorted())),
        )

        assertThat(resolved.unresolvedPartialDays).isEmpty()
        assertThat(resolved.appliedManualSelectionCount).isEqualTo(2)
        assertThat(resolved.subjects.map { it.base }).containsExactly(1, 0, 1).inOrder()
    }

    @Test
    fun manualSelectionPolicyCapsDraftAndRequiresEveryDayToBeExact() {
        val lessons = (1..3).map { index ->
            AbsenceLessonCandidate("lesson-$index", "2026-02-03", "$index", subjectKey = "s$index", subjectName = "S$index")
        }
        val day = AbsencePartialDayCandidate("2026-02-03", 2, emptyList(), lessons)
        val first = AbsenceManualSelectionPolicy.toggle(emptySet(), lessons[0].id, 2)
        val second = AbsenceManualSelectionPolicy.toggle(first, lessons[1].id, 2)
        val capped = AbsenceManualSelectionPolicy.toggle(second, lessons[2].id, 2)

        assertThat(capped).containsExactly(lessons[0].id, lessons[1].id)
        assertThat(AbsenceManualSelectionPolicy.canSave(listOf(day), mapOf(day.dateKey to first))).isFalse()
        assertThat(AbsenceManualSelectionPolicy.canSave(listOf(day), mapOf(day.dateKey to second))).isTrue()
        assertThat(AbsenceManualSelectionPolicy.toggle(second, lessons[0].id, 2))
            .containsExactly(lessons[1].id)
    }
}
