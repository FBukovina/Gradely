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

    @Test func timetableSubjectsAreUsedWhenMarksSubjectsAreMissing() {
        let timetable = timetableResponse(
            atoms: [
                TimetableAtom(hourID: 1, subjectID: "tt-math"),
                TimetableAtom(hourID: 2, subjectID: "tt-czech")
            ],
            timetableSubjects: [
                TimetableEntity(id: "tt-math", abbrev: "M", name: "Matematika"),
                TimetableEntity(id: "tt-czech", abbrev: "ČJ", name: "Český jazyk")
            ]
        )
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 2)],
            absencesPerSubject: []
        )

        let result = AbsenceSubjectFallback.makeAbsenceResult(
            from: response,
            timetableResponses: [timetable],
            subjects: [],
            validDateRange: referenceDate...referenceDate
        )

        #expect(result.absences.count == 2)
        #expect(result.absences.first { $0.subjectName == "Matematika" }?.base == 1)
        #expect(result.absences.first { $0.subjectName == "Český jazyk" }?.base == 1)
        #expect(result.stableIDHints == ["raw-tt-math", "raw-tt-czech"])
    }

    @Test func duplicateAndBlankSubjectIDsDoNotCrashFallback() {
        let duplicateSubjects = [
            subject(id: "", abbrev: "M", name: "Matematika"),
            subject(id: "", abbrev: "MAT", name: "Matematika"),
            subject(id: "czech", abbrev: "ČJ", name: "Český jazyk")
        ]
        let timetable = timetableResponse(
            atoms: [
                TimetableAtom(hourID: 1, subjectID: "tt-math"),
                TimetableAtom(hourID: 2, subjectID: "czech")
            ],
            timetableSubjects: [
                TimetableEntity(id: "tt-math", abbrev: "M", name: "Matematika"),
                TimetableEntity(id: "czech", abbrev: "ČJ", name: "Český jazyk")
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
            subjects: duplicateSubjects,
            validDateRange: referenceDate...referenceDate
        )

        #expect(resolved.count == 2)
        #expect(resolved.first { $0.subjectName == "Matematika" }?.base == 1)
        #expect(resolved.first { $0.subjectName == "Český jazyk" }?.base == 1)
    }

    @Test func termDerivedFromPastReturnedAbsenceScansFullSemester() {
        let now = TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 6, day: 6))!
        let term = AbsenceSubjectFallback.term(
            for: [
                absenceDay("2025-10-10T00:00:00+02:00", ok: 1)
            ],
            now: now
        )

        #expect(TimetableDates.apiDateString(term.start) == "2025-09-01")
        #expect(TimetableDates.apiDateString(term.end) == "2026-01-31")
    }

    @Test func repositoryAbsenceReturnsRawFirstThenSynthesizesSubjects() async throws {
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

        let data = try await repository.loadAbsence()
        #expect(data.absencesPerSubject.isEmpty)
        #expect(data.subjectResolutionSource == .unavailable)

        let resolved = try await repository.resolveAbsencesPerSubject(from: data.response)

        #expect(resolved.subjectResolutionSource == .synthesized)
        #expect(resolved.absencesPerSubject.count == 2)
        #expect(resolved.absencesPerSubject.first { $0.subjectName == "Matematika" }?.base == 1)
        #expect(resolved.absencesPerSubject.first { $0.subjectName == "Český jazyk" }?.base == 1)
    }

    @Test func repositoryFetchesOnlyMissingTimetableWeeks() async throws {
        let now = TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 2, day: 16))!
        let absence = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay(ok: 2)],
            absencesPerSubject: []
        )
        let term = AbsenceSubjectFallback.term(for: absence.absences, now: now)
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
        let timetableCache = InMemoryTimetableCache()
        try timetableCache.save(timetable, weekStart: term.weekStarts[0])
        let client = CountingBakalariClient(
            marksResult: MarksResponse(subjects: subjects),
            absenceResult: absence,
            timetableResult: timetable
        )
        let repository = BakalariRepository(
            client: client,
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache(),
            timetableCache: timetableCache,
            dateProvider: { now }
        )

        _ = try await repository.resolveAbsencesPerSubject(from: absence)

        #expect(client.timetableFetchDates.count == term.weekStarts.count - 1)
        #expect(!client.timetableFetchDates.contains(term.weekStarts[0]))
    }

    @Test func repositoryReturnsPartialRowsWhenMissingWeeksTimeout() async throws {
        let now = TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 6, day: 6))!
        let fullDayDate = MarkDateFormatter.date(from: "2026-05-04T00:00:00+02:00")!
        let cachedWeekStart = TimetableDates.monday(of: fullDayDate)
        let cachedTimetable = MockBakalariClient.rebased(PreviewData.timetableResponse, toWeekContaining: cachedWeekStart)
        let timetableCache = InMemoryTimetableCache()
        try timetableCache.save(cachedTimetable, weekStart: cachedWeekStart)
        let absence = PreviewData.absenceResponseWithoutSubjectRows
        let client = CountingBakalariClient(
            marksResult: MarksResponse(subjects: []),
            absenceResult: absence,
            timetableResult: PreviewData.timetableResponse,
            timetableDelay: 500_000_000
        )
        let repository = BakalariRepository(
            client: client,
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache(),
            timetableCache: timetableCache,
            dateProvider: { now },
            timetableFetchTimeoutNanoseconds: 10_000_000
        )

        let resolved = try await repository.resolveAbsencesPerSubject(from: absence)

        #expect(resolved.subjectResolutionSource == .partialSynthesized)
        #expect(resolved.subjectResolutionWarning != nil)
        #expect(!resolved.absencesPerSubject.isEmpty)
        #expect(resolved.subjectStableIDHints.contains("raw-math"))
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

    private func absenceDay(_ date: String, ok: Int) -> AbsenceDay {
        AbsenceDay(
            date: date,
            unsolved: 0,
            ok: ok,
            missed: 0,
            late: 0,
            soon: 0,
            school: 0,
            distanceTeaching: 0
        )
    }

    private func absenceDay(ok: Int) -> AbsenceDay {
        absenceDay("2026-02-02T00:00:00+01:00", ok: ok)
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

private final class CountingBakalariClient: BakalariClient {
    let marksResult: MarksResponse
    let absenceResult: AbsenceResponse
    let timetableResult: TimetableResponse
    let timetableDelay: UInt64
    private let lock = NSLock()
    private var recordedTimetableFetchDates: [Date] = []

    var timetableFetchDates: [Date] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTimetableFetchDates
    }

    init(
        marksResult: MarksResponse,
        absenceResult: AbsenceResponse,
        timetableResult: TimetableResponse,
        timetableDelay: UInt64 = 0
    ) {
        self.marksResult = marksResult
        self.absenceResult = absenceResult
        self.timetableResult = timetableResult
        self.timetableDelay = timetableDelay
    }

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        LoginResponse(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresIn: 3600,
            apiVersion: nil,
            appVersion: nil,
            userID: "mock-user"
        )
    }

    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        try await login(baseURL: baseURL, username: "", password: "")
    }

    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        marksResult
    }

    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        absenceResult
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        throw BakalariAPIError.httpStatus(404, nil)
    }

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        lock.lock()
        recordedTimetableFetchDates.append(date)
        lock.unlock()

        if timetableDelay > 0 {
            try await Task.sleep(nanoseconds: timetableDelay)
        }
        return MockBakalariClient.rebased(timetableResult, toWeekContaining: date)
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        subject
    }
}
