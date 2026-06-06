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
    var response: AbsenceResponse?
    var absencesPerSubject: [AbsencePerSubject] = []
    var user: UserResponse?
    var errorMessage: String?
    var selectedSegment: Segment = .days
    var lastCacheDate: Date?

    private let repository: BakalariRepository
    private var hasLoaded = false

    init(repository: BakalariRepository) {
        self.repository = repository
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
            response = data.response
            absencesPerSubject = data.absencesPerSubject
            user = data.user
            lastCacheDate = Date()
        } catch {
            if response == nil {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    private func applyCached(_ cached: CachedAbsence) {
        response = cached.response
        absencesPerSubject = cached.response.absencesPerSubject
        lastCacheDate = cached.cachedAt
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
