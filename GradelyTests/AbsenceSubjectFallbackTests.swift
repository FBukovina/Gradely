import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsenceSubjectFallbackTests {
    @Test func officialSubjectAbsenceRemainsAuthoritative() {
        let official = [
            AbsencePerSubject(
                subjectName: "Matematika",
                lessonsCount: 42,
                base: 4,
                late: 1,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
        ]
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 2)],
            absencesPerSubject: official
        )

        let resolved = AbsenceSubjectFallback.makeAbsences(
            from: response,
            timetableResponses: [],
            subjects: []
        )

        #expect(resolved == official)
    }

    @Test func fullDayAbsenceIsMappedToSubjectsFromTimetable() {
        let timetable = timetableResponse(
            atoms: [
                TimetableAtom(hourID: 1, subjectID: "math"),
                TimetableAtom(hourID: 2, subjectID: "tt-czech"),
                TimetableAtom(
                    hourID: 3,
                    subjectID: "math",
                    change: TimetableChange(changeType: "Removed")
                )
            ],
            timetableSubjects: [
                TimetableEntity(id: "math", abbrev: "X", name: "Different timetable name"),
                TimetableEntity(id: "tt-czech", abbrev: "CJ", name: "Český jazyk")
            ]
        )
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 2)],
            absencesPerSubject: []
        )

        let resolved = AbsenceSubjectFallback.makeAbsences(
            from: response,
            timetableResponses: [timetable],
            subjects: subjects,
            validDateRange: referenceDate...referenceDate
        )

        let math = resolved.first { $0.subjectName == "Matematika" }
        let czech = resolved.first { $0.subjectName == "Český jazyk" }

        #expect(math?.lessonsCount == 1)
        #expect(math?.base == 1)
        #expect(czech?.lessonsCount == 1)
        #expect(czech?.base == 1)
    }

    @Test func partialDayAbsenceDoesNotSynthesizeSubjectAbsence() {
        let timetable = timetableResponse(
            atoms: [
                TimetableAtom(hourID: 1, subjectID: "math"),
                TimetableAtom(hourID: 2, subjectID: "czech")
            ],
            timetableSubjects: [
                TimetableEntity(id: "math", abbrev: "M", name: "Matematika"),
                TimetableEntity(id: "czech", abbrev: "ČJ", name: "Český jazyk")
            ]
        )
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 1)],
            absencesPerSubject: []
        )

        let resolved = AbsenceSubjectFallback.makeAbsences(
            from: response,
            timetableResponses: [timetable],
            subjects: subjects,
            validDateRange: referenceDate...referenceDate
        )

        #expect(resolved.isEmpty)
    }

    @Test func repositorySynthesizesSubjectAbsenceWhenOfficialArrayIsEmpty() async throws {
        let timetable = timetableResponse(
            atoms: [
                TimetableAtom(hourID: 1, subjectID: "math"),
                TimetableAtom(hourID: 2, subjectID: "czech")
            ],
            timetableSubjects: [
                TimetableEntity(id: "math", abbrev: "M", name: "Matematika"),
                TimetableEntity(id: "czech", abbrev: "ČJ", name: "Český jazyk")
            ]
        )
        let absence = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 2)],
            absencesPerSubject: []
        )
        let repository = BakalariRepository(
            client: MockBakalariClient(
                marksResult: MarksResponse(subjects: subjects),
                absenceResult: absence,
                timetableResult: timetable
            ),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache(),
            timetableCache: InMemoryTimetableCache(),
            dateProvider: { referenceDate }
        )

        let dashboard = try await repository.loadDashboard()

        #expect(dashboard.absencesPerSubject.count == 2)
        #expect(dashboard.absencesPerSubject.first { $0.subjectName == "Matematika" }?.base == 1)
        #expect(dashboard.absencesPerSubject.first { $0.subjectName == "Český jazyk" }?.base == 1)
    }

    private var subjects: [Subject] {
        [
            subject(id: "math", abbrev: "M", name: "Matematika"),
            subject(id: "czech", abbrev: "ČJ", name: "Český jazyk")
        ]
    }

    private var referenceDate: Date {
        TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 2, day: 2))!
    }

    private func subject(id: String, abbrev: String, name: String) -> Subject {
        Subject(
            marks: [],
            subjectInfo: SubjectInfo(id: id, abbrev: abbrev, name: name),
            averageText: nil
        )
    }

    private func absenceDay(ok: Int) -> AbsenceDay {
        AbsenceDay(
            date: "2026-02-02T00:00:00+01:00",
            unsolved: 0,
            ok: ok,
            missed: 0,
            late: 0,
            soon: 0,
            school: 0,
            distanceTeaching: 0
        )
    }

    private func timetableResponse(
        atoms: [TimetableAtom],
        timetableSubjects: [TimetableEntity]
    ) -> TimetableResponse {
        TimetableResponse(
            hours: [
                TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
                TimetableHour(id: 2, caption: "2", beginTime: "8:55", endTime: "9:40"),
                TimetableHour(id: 3, caption: "3", beginTime: "9:50", endTime: "10:35")
            ],
            days: [
                TimetableDayDTO(
                    atoms: atoms,
                    dayOfWeek: 1,
                    date: "2026-02-02T00:00:00+01:00"
                )
            ],
            subjects: timetableSubjects
        )
    }

    private func validSession() -> StoredSession {
        StoredSession(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!
        )
    }
}
