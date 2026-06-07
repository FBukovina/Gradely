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
        case loaded(rows: [AbsenceSubjectSummary], source: AbsenceSubjectResolutionSource, warning: String?)
        case empty
        case failed(message: String)

        var rows: [AbsenceSubjectSummary] {
            if case .loaded(let rows, _, _) = self {
                return rows
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

    private let repository: BakalariRepository
    private var hasLoaded = false
    @ObservationIgnored private var subjectResolutionTask: Task<Void, Never>?
    @ObservationIgnored private var subjectResolutionToken = UUID()

    init(repository: BakalariRepository) {
        self.repository = repository
    }

    deinit {
        subjectResolutionTask?.cancel()
    }

    var dayRows: [AbsenceDaySummary] {
        AbsenceSummary.daySummaries(for: response?.absences ?? [])
    }

    var monthRows: [AbsenceMonthSummary] {
        AbsenceSummary.monthSummaries(for: response?.absences ?? [])
    }

    var totalCounts: AbsenceCounts {
        AbsenceSummary.totalCounts(for: response?.absences ?? [])
    }

    var hasAnyAbsenceData: Bool {
        !(response?.absences ?? []).isEmpty || !subjectAbsenceState.rows.isEmpty
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
        subjectAbsenceState = state(
            for: cached.response.absencesPerSubject,
            source: cached.response.absencesPerSubject.isEmpty ? .unavailable : .official,
            threshold: cached.response.percentageThreshold,
            stableIDHints: []
        )
        lastCacheDate = cached.cachedAt
    }

    private func applyLoaded(_ data: AbsenceData) {
        response = data.response
        subjectAbsenceState = state(
            for: data.absencesPerSubject,
            source: data.subjectResolutionSource,
            threshold: data.response.percentageThreshold,
            stableIDHints: data.subjectStableIDHints,
            warning: data.subjectResolutionWarning
        )
        user = data.user
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
                stableIDHints: []
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
                let data = try await repository.resolveAbsencesPerSubject(from: response) { [weak self] progress in
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
                    warning: data.subjectResolutionWarning
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

    private func state(
        for absences: [AbsencePerSubject],
        source: AbsenceSubjectResolutionSource,
        threshold: Double,
        stableIDHints: [String],
        warning: String? = nil
    ) -> SubjectAbsenceState {
        let rows = AbsenceSummary.subjectSummaries(
            for: absences,
            threshold: threshold,
            stableIDHints: stableIDHints
        )
        if !rows.isEmpty {
            return .loaded(rows: rows, source: source, warning: warning)
        }
        return .empty
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
