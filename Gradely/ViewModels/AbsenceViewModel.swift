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

    var isLoading = false
    var isRefreshing = false
    var isResolvingSubjects = false
    var response: AbsenceResponse?
    var absencesPerSubject: [AbsencePerSubject] = []
    var user: UserResponse?
    var errorMessage: String?
    var subjectResolutionError: String?
    var subjectResolutionSource: AbsenceSubjectResolutionSource = .unavailable
    var selectedSegment: Segment = .days
    var lastCacheDate: Date?

    private let repository: BakalariRepository
    private var hasLoaded = false
    @ObservationIgnored private var subjectResolutionTask: Task<Void, Never>?

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

    var subjectRows: [AbsenceSubjectSummary] {
        AbsenceSummary.subjectSummaries(
            for: absencesPerSubject,
            threshold: response?.percentageThreshold ?? 0
        )
    }

    var totalCounts: AbsenceCounts {
        AbsenceSummary.totalCounts(for: response?.absences ?? [])
    }

    var hasAnyAbsenceData: Bool {
        !(response?.absences ?? []).isEmpty || !absencesPerSubject.isEmpty
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
        subjectResolutionError = nil
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
        absencesPerSubject = cached.response.absencesPerSubject
        subjectResolutionSource = cached.response.absencesPerSubject.isEmpty ? .unavailable : .official
        lastCacheDate = cached.cachedAt
    }

    private func applyLoaded(_ data: AbsenceData) {
        response = data.response
        absencesPerSubject = data.absencesPerSubject
        subjectResolutionSource = data.subjectResolutionSource
        user = data.user
    }

    private func startSubjectResolutionIfNeeded(for response: AbsenceResponse) {
        subjectResolutionTask?.cancel()
        subjectResolutionTask = nil
        subjectResolutionError = nil

        guard response.absencesPerSubject.isEmpty else {
            isResolvingSubjects = false
            absencesPerSubject = response.absencesPerSubject
            subjectResolutionSource = .official
            return
        }

        guard !response.absences.isEmpty else {
            isResolvingSubjects = false
            absencesPerSubject = []
            subjectResolutionSource = .unavailable
            return
        }

        isResolvingSubjects = true
        subjectResolutionTask = Task { @MainActor in
            do {
                let data = try await repository.resolveAbsencesPerSubject(from: response)
                guard !Task.isCancelled else { return }
                applySubjectResolution(data, expectedResponse: response)
            } catch {
                guard !Task.isCancelled else { return }
                isResolvingSubjects = false
                subjectResolutionSource = .unavailable
                subjectResolutionError = userFacingMessage(for: error)
            }
        }
    }

    private func applySubjectResolution(_ data: AbsenceData, expectedResponse: AbsenceResponse) {
        guard response == expectedResponse else { return }
        absencesPerSubject = data.absencesPerSubject
        subjectResolutionSource = data.subjectResolutionSource
        subjectResolutionError = nil
        isResolvingSubjects = false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
