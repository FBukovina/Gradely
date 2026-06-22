import Foundation
import Observation

@MainActor
@Observable
final class AbsenceViewModel {
    enum Segment: String, CaseIterable, Identifiable {
        case subjects
        case days
        case months

        var id: String { rawValue }
    }

    enum SubjectAbsenceState: Equatable {
        case idle
        case loading(progress: AbsenceSubjectResolutionProgress?)
        case loaded(
            rows: [AbsenceSubjectSummary],
            source: AbsenceSubjectResolutionSource,
            warning: String?,
            unresolvedPartialDays: [AbsencePartialDayCandidate]
        )
        case empty
        case failed(message: String)

        var rows: [AbsenceSubjectSummary] {
            if case .loaded(let rows, _, _, _) = self {
                return rows
            }
            return []
        }

        var unresolvedPartialDays: [AbsencePartialDayCandidate] {
            if case .loaded(_, _, _, let unresolvedPartialDays) = self {
                return unresolvedPartialDays
            }
            return []
        }
    }

    var isLoading = false
    var isRefreshing = false
    var response: AbsenceResponse?
    var subjectAbsenceState: SubjectAbsenceState = .idle
    var user: UserResponse?
    var errorMessage: String?
    var selectedSegment: Segment = .days
    var lastCacheDate: Date?
    var dayRows: [AbsenceDaySummary] = []
    var monthRows: [AbsenceMonthSummary] = []
    var dayCountRows: [AbsenceCountRow] = []
    var monthCountRows: [AbsenceCountRow] = []
    var totalCounts: AbsenceCounts = .zero
    var isManualSelectionSheetPresented = false
    var manualSelectionDrafts: [String: Set<String>] = [:]
    var manualSelectionErrorMessage: String?
    var isSavingManualSelections = false
    var isPredictionSheetPresented = false
    var predictionSelectedDate: Date
    var predictionLessons: [AbsenceLessonCandidate] = []
    var predictionDraftLessonIDs: Set<String> = []
    var predictionSelectedLessons: [AbsenceLessonCandidate] = []
    var predictionErrorMessage: String?
    var isLoadingPredictionLessons = false

    private let repository: SchoolRepository
    private let predictionMinimumDay: Date
    private var hasLoaded = false
    @ObservationIgnored private var predictionLessonsByDate: [String: [AbsenceLessonCandidate]] = [:]
    @ObservationIgnored private var predictionLessonCacheByID: [String: AbsenceLessonCandidate] = [:]
    @ObservationIgnored private var subjectResolutionTask: Task<Void, Never>?
    @ObservationIgnored private var subjectResolutionToken = UUID()

    init(repository: SchoolRepository, today: Date = Date()) {
        self.repository = repository
        predictionMinimumDay = TimetableDates.weekCalendar.startOfDay(for: today)
        predictionSelectedDate = predictionMinimumDay
    }

    deinit {
        subjectResolutionTask?.cancel()
    }

    var hasAnyAbsenceData: Bool {
        !dayRows.isEmpty || !subjectAbsenceState.rows.isEmpty || !subjectAbsenceState.unresolvedPartialDays.isEmpty
    }

    var manualResolutionCandidates: [AbsencePartialDayCandidate] {
        subjectAbsenceState.unresolvedPartialDays
    }

    var canSaveManualSelectionDrafts: Bool {
        !manualResolutionCandidates.isEmpty && manualResolutionCandidates.allSatisfy { day in
            (manualSelectionDrafts[day.dateKey] ?? []).count == day.requiredSelectionCount
        }
    }

    var predictionMinimumDate: Date {
        predictionMinimumDay
    }

    var predictionDraftSelectedCount: Int {
        predictionDraftLessonIDs.count
    }

    var predictionResult: AbsencePredictionResult {
        AbsencePrediction.project(
            currentTotalCounts: totalCounts,
            subjectRows: subjectAbsenceState.rows,
            selectedLessons: predictionSelectedLessons,
            threshold: response?.percentageThreshold ?? 0
        )
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = try? repository.loadCachedAbsence() {
            applyCached(cached)
        }

        await refresh(forceRefresh: false)
    }

    func refresh(forceRefresh: Bool = true) async {
        subjectResolutionTask?.cancel()
        subjectResolutionTask = nil
        errorMessage = nil
        if response == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let data = try await repository.loadAbsence(forceRefresh: forceRefresh)
            applyLoaded(data)
            lastCacheDate = Date()
            startSubjectResolutionIfNeeded(for: data.response)
        } catch {
            if response == nil {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    func retrySubjectResolution() {
        guard let response else { return }
        startSubjectResolutionIfNeeded(for: response)
    }

    private func applyCached(_ cached: CachedAbsence) {
        response = cached.response
        applyAbsenceSnapshots(from: cached.response)
        subjectAbsenceState = state(
            for: cached.response.absencesPerSubject,
            source: cached.response.absencesPerSubject.isEmpty ? .unavailable : .official,
            threshold: cached.response.percentageThreshold,
            stableIDHints: [],
            unresolvedPartialDays: []
        )
        lastCacheDate = cached.cachedAt
    }

    private func applyLoaded(_ data: AbsenceData) {
        response = data.response
        applyAbsenceSnapshots(from: data.response)
        subjectAbsenceState = state(
            for: data.absencesPerSubject,
            source: data.subjectResolutionSource,
            threshold: data.response.percentageThreshold,
            stableIDHints: data.subjectStableIDHints,
            warning: data.subjectResolutionWarning,
            unresolvedPartialDays: data.unresolvedPartialDays
        )
        user = data.user
    }

    private func applyAbsenceSnapshots(from response: AbsenceResponse) {
        dayRows = AbsenceSummary.daySummaries(for: response.absences)
        monthRows = AbsenceSummary.monthSummaries(for: response.absences)
        totalCounts = AbsenceSummary.totalCounts(for: response.absences)
        dayCountRows = dayRows.map {
            AbsenceCountRow(id: "day-\($0.id)", title: $0.title, counts: $0.counts)
        }
        monthCountRows = monthRows.map {
            AbsenceCountRow(id: "month-\($0.id)", title: $0.title, counts: $0.counts)
        }
    }

    private func startSubjectResolutionIfNeeded(for response: AbsenceResponse) {
        subjectResolutionTask?.cancel()
        subjectResolutionTask = nil
        subjectResolutionToken = UUID()

        guard response.absencesPerSubject.isEmpty else {
            subjectAbsenceState = state(
                for: response.absencesPerSubject,
                source: .official,
                threshold: response.percentageThreshold,
                stableIDHints: [],
                unresolvedPartialDays: []
            )
            return
        }

        guard !response.absences.isEmpty else {
            subjectAbsenceState = .empty
            return
        }

        let token = UUID()
        subjectResolutionToken = token
        subjectAbsenceState = .loading(progress: nil)
        subjectResolutionTask = Task {
            do {
                let data = try await repository.resolveAbsencesPerSubject(from: response, user: user) { [weak self] progress in
                    await MainActor.run {
                        guard
                            let self,
                            self.response == response,
                            self.subjectResolutionToken == token
                        else {
                            return
                        }
                        self.subjectAbsenceState = .loading(progress: progress)
                    }
                }
                guard !Task.isCancelled else { return }
                let nextState = state(
                    for: data.absencesPerSubject,
                    source: data.subjectResolutionSource,
                    threshold: data.response.percentageThreshold,
                    stableIDHints: data.subjectStableIDHints,
                    warning: data.subjectResolutionWarning,
                    unresolvedPartialDays: data.unresolvedPartialDays
                )
                await MainActor.run {
                    applySubjectResolution(nextState, expectedResponse: response, token: token)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = userFacingMessage(for: error)
                await MainActor.run {
                    applySubjectResolution(.failed(message: message), expectedResponse: response, token: token)
                }
            }
        }
    }

    private func applySubjectResolution(
        _ state: SubjectAbsenceState,
        expectedResponse: AbsenceResponse,
        token: UUID
    ) {
        guard response == expectedResponse, subjectResolutionToken == token else { return }
        subjectAbsenceState = state
        subjectResolutionTask = nil
    }

    func openManualSelectionSheet() {
        manualSelectionErrorMessage = nil
        manualSelectionDrafts = Dictionary(
            uniqueKeysWithValues: manualResolutionCandidates.map { day in
                (day.dateKey, Set(day.selectedLessonIDs))
            }
        )
        isManualSelectionSheetPresented = true
    }

    func cancelManualSelectionSheet() {
        manualSelectionErrorMessage = nil
        manualSelectionDrafts = [:]
        isManualSelectionSheetPresented = false
    }

    func selectedManualLessonCount(for dateKey: String) -> Int {
        (manualSelectionDrafts[dateKey] ?? []).count
    }

    func isManualLessonSelected(_ lessonID: String, dateKey: String) -> Bool {
        (manualSelectionDrafts[dateKey] ?? []).contains(lessonID)
    }

    func toggleManualLesson(_ lessonID: String, dateKey: String) {
        guard let day = manualResolutionCandidates.first(where: { $0.dateKey == dateKey }) else { return }
        var selected = manualSelectionDrafts[dateKey] ?? []
        if selected.contains(lessonID) {
            selected.remove(lessonID)
        } else if selected.count < day.requiredSelectionCount {
            selected.insert(lessonID)
        }
        manualSelectionDrafts[dateKey] = selected
    }

    func saveManualSelections() async {
        guard let response else { return }
        guard canSaveManualSelectionDrafts else { return }

        manualSelectionErrorMessage = nil
        isSavingManualSelections = true
        defer { isSavingManualSelections = false }

        do {
            try await repository.saveManualAbsenceLessonSelections(
                selectedLessonIDsByDate: manualSelectionDrafts,
                user: user
            )
            isManualSelectionSheetPresented = false
            manualSelectionDrafts = [:]
            startSubjectResolutionIfNeeded(for: response)
        } catch {
            manualSelectionErrorMessage = userFacingMessage(for: error)
        }
    }

    func openPredictionSheet() {
        predictionErrorMessage = nil
        predictionSelectedDate = normalizedPredictionDate(predictionSelectedDate)
        predictionDraftLessonIDs = Set(predictionSelectedLessons.map(\.id))
        for lesson in predictionSelectedLessons {
            predictionLessonCacheByID[lesson.id] = lesson
        }
        isPredictionSheetPresented = true
    }

    func cancelPredictionSheet() {
        predictionErrorMessage = nil
        predictionDraftLessonIDs = []
        isPredictionSheetPresented = false
    }

    func clearPredictionSelections() {
        predictionDraftLessonIDs = []
        predictionSelectedLessons = []
    }

    func clearPredictionDraftSelections() {
        predictionDraftLessonIDs = []
    }

    func commitPredictionSelections() {
        let selectedLessons = predictionDraftLessonIDs.compactMap { predictionLessonCacheByID[$0] }
        predictionSelectedLessons = AbsencePrediction.selectedLessonsByID(selectedLessons)
        predictionErrorMessage = nil
        isPredictionSheetPresented = false
    }

    func isPredictionLessonSelected(_ lessonID: String) -> Bool {
        predictionDraftLessonIDs.contains(lessonID)
    }

    func togglePredictionLesson(_ lesson: AbsenceLessonCandidate) {
        predictionLessonCacheByID[lesson.id] = lesson
        if predictionDraftLessonIDs.contains(lesson.id) {
            predictionDraftLessonIDs.remove(lesson.id)
        } else {
            predictionDraftLessonIDs.insert(lesson.id)
        }
    }

    func loadPredictionLessonsForSelectedDate() async {
        let date = normalizedPredictionDate(predictionSelectedDate)
        if date != predictionSelectedDate {
            predictionSelectedDate = date
        }

        let dateKey = TimetableDates.apiDateString(date)
        if let cached = predictionLessonsByDate[dateKey] {
            predictionLessons = cached
            predictionErrorMessage = nil
            return
        }

        predictionErrorMessage = nil
        isLoadingPredictionLessons = true
        defer {
            if currentPredictionDateKey == dateKey {
                isLoadingPredictionLessons = false
            }
        }

        do {
            let lessons = try await repository.loadAbsencePredictionLessons(on: date, user: user)
            guard currentPredictionDateKey == dateKey else { return }
            predictionLessonsByDate[dateKey] = lessons
            predictionLessons = lessons
            for lesson in lessons {
                predictionLessonCacheByID[lesson.id] = lesson
            }
        } catch {
            guard currentPredictionDateKey == dateKey else { return }
            predictionLessons = []
            predictionErrorMessage = userFacingMessage(for: error)
        }
    }

    private func state(
        for absences: [AbsencePerSubject],
        source: AbsenceSubjectResolutionSource,
        threshold: Double?,
        stableIDHints: [String],
        warning: String? = nil,
        unresolvedPartialDays: [AbsencePartialDayCandidate] = []
    ) -> SubjectAbsenceState {
        let rows = AbsenceSummary.subjectSummaries(
            for: absences,
            threshold: threshold,
            stableIDHints: stableIDHints
        )
        if !rows.isEmpty || !unresolvedPartialDays.isEmpty {
            return .loaded(
                rows: rows,
                source: source,
                warning: warning,
                unresolvedPartialDays: unresolvedPartialDays
            )
        }
        return .empty
    }

    private var currentPredictionDateKey: String {
        TimetableDates.apiDateString(normalizedPredictionDate(predictionSelectedDate))
    }

    private func normalizedPredictionDate(_ date: Date) -> Date {
        let day = TimetableDates.weekCalendar.startOfDay(for: date)
        return day < predictionMinimumDay ? predictionMinimumDay : day
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
