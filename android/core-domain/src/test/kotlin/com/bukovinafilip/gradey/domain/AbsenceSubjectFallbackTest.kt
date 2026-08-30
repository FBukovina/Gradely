package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Absence
import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableDayDTO
import com.bukovinafilip.gradey.model.TimetableEntity
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
}
