import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsenceViewModelTests {
    @Test func cachedRawAbsenceShowsDayRowsBeforeRefreshCompletes() async throws {
        let cachedAbsence = PreviewData.absenceResponseWithoutSubjectRows
        let client = DelayedAbsenceClient(
            absenceResult: cachedAbsence,
            absenceDelay: 300_000_000,
            timetableDelay: 100_000_000
        )
        let viewModel = AbsenceViewModel(
            repository: repository(
                client: client,
                absenceCache: InMemoryAbsenceCache(
                    cachedAbsence: CachedAbsence(response: cachedAbsence, cachedAt: Date())
                )
            )
        )

        let loadTask = Task { await viewModel.loadIfNeeded() }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.dayRows.count == cachedAbsence.absences.count)
        #expect(viewModel.dayCountRows.count == cachedAbsence.absences.count)
        #expect(!viewModel.monthCountRows.isEmpty)
        #expect(viewModel.totalCounts.total == AbsenceSummary.totalCounts(for: cachedAbsence.absences).total)

        _ = await loadTask.result
    }

    @Test func missingOfficialSubjectsEnterLoadingThenLoadedState() async throws {
        let client = DelayedAbsenceClient(
            absenceResult: PreviewData.absenceResponseWithoutSubjectRows,
            timetableDelay: 150_000_000
        )
        let viewModel = AbsenceViewModel(repository: repository(client: client))

        await viewModel.refresh(forceRefresh: false)

        #expect(!viewModel.dayRows.isEmpty)
        #expect(!viewModel.dayCountRows.isEmpty)
        #expect(!viewModel.monthCountRows.isEmpty)
        if case .loading = viewModel.subjectAbsenceState {
            #expect(true)
        } else {
            Issue.record("Expected subject absence to start in loading state.")
        }

        let didLoad = await waitForSubjectState(viewModel) { state in
            if case .loaded(let rows, .synthesized, nil, _) = state {
                return !rows.isEmpty
            }
            return false
        }

        #expect(didLoad)
    }

    @Test func fallbackFailureDoesNotClearDayAndMonthData() async throws {
        let client = DelayedAbsenceClient(
            absenceResult: PreviewData.absenceResponseWithoutSubjectRows,
            timetableError: BakalariAPIError.httpStatus(500, nil)
        )
        let viewModel = AbsenceViewModel(repository: repository(client: client))

        await viewModel.refresh(forceRefresh: false)

        let didFail = await waitForSubjectState(viewModel) { state in
            if case .failed = state {
                return true
            }
            return false
        }

        #expect(didFail)
        #expect(!viewModel.dayRows.isEmpty)
        #expect(!viewModel.monthRows.isEmpty)
        #expect(!viewModel.dayCountRows.isEmpty)
        #expect(!viewModel.monthCountRows.isEmpty)
    }

    @Test func partialFallbackWarningDoesNotClearDayAndMonthData() async throws {
        let absence = PreviewData.absenceResponseWithoutSubjectRows
        let cachedWeekStart = TimetableDates.monday(
            of: MarkDateFormatter.date(from: "2026-05-04T00:00:00+02:00")!
        )
        let timetableCache = InMemoryTimetableCache()
        try timetableCache.save(MockBakalariClient.rebased(PreviewData.timetableResponse, toWeekContaining: cachedWeekStart), weekStart: cachedWeekStart)
        let client = DelayedAbsenceClient(
            absenceResult: absence,
            timetableDelay: 500_000_000
        )
        let viewModel = AbsenceViewModel(
            repository: repository(
                client: client,
                timetableCache: timetableCache,
                timetableFetchTimeoutNanoseconds: 10_000_000
            )
        )

        await viewModel.refresh(forceRefresh: false)

        let didLoadPartial = await waitForSubjectState(viewModel) { state in
            if case .loaded(let rows, .partialSynthesized, let warning, _) = state {
                return !rows.isEmpty && warning != nil
            }
            return false
        }

        #expect(didLoadPartial)
        #expect(!viewModel.dayRows.isEmpty)
        #expect(!viewModel.monthRows.isEmpty)
    }

    @Test func manualPartialDaySelectionUpdatesSubjectRows() async throws {
        let absence = AbsenceResponse(
            percentageThreshold: 25,
            absences: [
                AbsenceDay(
                    date: "2026-02-02T00:00:00+01:00",
                    unsolved: 0,
                    ok: 1,
                    missed: 0,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ],
            absencesPerSubject: []
        )
        let timetable = TimetableResponse(
            hours: [
                TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
                TimetableHour(id: 2, caption: "2", beginTime: "8:55", endTime: "9:40")
            ],
            days: [
                TimetableDayDTO(
                    atoms: [
                        TimetableAtom(hourID: 1, subjectID: "math"),
                        TimetableAtom(hourID: 2, subjectID: "tev")
                    ],
                    dayOfWeek: 1,
                    date: "2026-02-02T00:00:00+01:00"
                )
            ],
            subjects: [
                TimetableEntity(id: "math", abbrev: "M", name: "Matematika"),
                TimetableEntity(id: "tev", abbrev: "TV", name: "Tělesná výchova")
            ]
        )
        let viewModel = AbsenceViewModel(
            repository: repository(
                client: DelayedAbsenceClient(absenceResult: absence, timetableResult: timetable)
            )
        )

        await viewModel.refresh(forceRefresh: false)

        let didNeedManualSelection = await waitForSubjectState(viewModel) { state in
            if case .loaded(_, .synthesized, _, let unresolvedDays) = state {
                return unresolvedDays.count == 1
            }
            return false
        }
        #expect(didNeedManualSelection)

        viewModel.openManualSelectionSheet()
        viewModel.toggleManualLesson("lesson-2026-02-02-2-raw-tev", dateKey: "2026-02-02")
        #expect(viewModel.canSaveManualSelectionDrafts)
        await viewModel.saveManualSelections()

        let didApplyManualSelection = await waitForSubjectState(viewModel) { state in
            if case .loaded(let rows, .synthesized, _, let unresolvedDays) = state {
                return unresolvedDays.isEmpty
                    && rows.first { $0.subjectName == "Tělesná výchova" }?.base == 1
            }
            return false
        }

        #expect(didApplyManualSelection)
    }

    private func waitForSubjectState(
        _ viewModel: AbsenceViewModel,
        timeout: TimeInterval = 3,
        matches: (AbsenceViewModel.SubjectAbsenceState) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if matches(viewModel.subjectAbsenceState) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return matches(viewModel.subjectAbsenceState)
    }

    private func repository(
        client: any BakalariClient,
        absenceCache: any AbsenceCaching = InMemoryAbsenceCache(),
        timetableCache: any TimetableCaching = InMemoryTimetableCache(),
        timetableFetchTimeoutNanoseconds: UInt64 = 12_000_000_000
    ) -> BakalariRepository {
        BakalariRepository(
            client: client,
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache(),
            absenceCache: absenceCache,
            timetableCache: timetableCache,
            dateProvider: {
                TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 6, day: 6)) ?? Date()
            },
            timetableFetchTimeoutNanoseconds: timetableFetchTimeoutNanoseconds
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

private struct DelayedAbsenceClient: BakalariClient {
    var marksResult: MarksResponse = PreviewData.marksResponse
    var absenceResult: AbsenceResponse
    var timetableResult: TimetableResponse = PreviewData.timetableResponse
    var absenceDelay: UInt64 = 0
    var timetableDelay: UInt64 = 0
    var timetableError: Error?

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
        if absenceDelay > 0 {
            try await Task.sleep(nanoseconds: absenceDelay)
        }
        return absenceResult
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        PreviewData.userResponse
    }

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        if timetableDelay > 0 {
            try await Task.sleep(nanoseconds: timetableDelay)
        }
        if let timetableError {
            throw timetableError
        }
        return MockBakalariClient.rebased(timetableResult, toWeekContaining: date)
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        subject
    }
}
