import Foundation
import Observation

@MainActor
@Observable
final class SubjectsViewModel {
    var isLoading = false
    var isRefreshing = false
    var subjects: [Subject] = []
    var absencesPerSubject: [AbsencePerSubject] = []
    var user: UserResponse?
    var errorMessage: String?
    var lastCacheDate: Date?

    private let repository: BakalariRepository
    private var hasLoaded = false

    init(repository: BakalariRepository) {
        self.repository = repository
    }

    // MARK: - Overview metrics

    /// Weighted study average across all subjects (mean of subject averages).
    var overallAverage: Double? {
        GradeMath.overallAverage(for: subjects)
    }

    /// Total number of recorded marks across every subject.
    var totalMarks: Int {
        subjects.reduce(0) { $0 + $1.marks.count }
    }

    var schoolName: String? {
        guard let schoolName = user?.schoolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !schoolName.isEmpty
        else {
            return nil
        }
        return schoolName
    }

    /// Subject with the best (lowest) average — `1` is best in the Czech scale.
    var bestSubject: Subject? {
        subjects
            .compactMap { subject in GradeMath.subjectAverage(subject).map { (subject, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Subject with the weakest (highest) average.
    var weakestSubject: Subject? {
        subjects
            .compactMap { subject in GradeMath.subjectAverage(subject).map { (subject, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = try? repository.loadCachedMarks() {
            subjects = cached.marksResponse.subjects
            lastCacheDate = cached.cachedAt
        }

        await refresh(forceRefresh: false)
    }

    func refresh(forceRefresh: Bool = true) async {
        errorMessage = nil
        if subjects.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let dashboard = try await repository.loadDashboard(forceRefresh: forceRefresh)
            subjects = dashboard.marksResponse.subjects
            absencesPerSubject = dashboard.absencesPerSubject
            user = dashboard.user
            lastCacheDate = Date()
        } catch {
            if subjects.isEmpty {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    func absence(for subject: Subject) -> AbsencePerSubject? {
        let subjectName = subject.trimmedName.lowercased()
        let subjectAbbrev = subject.trimmedAbbrev.lowercased()

        return absencesPerSubject.first { absence in
            let absenceName = absence.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return absenceName == subjectName
                || (!subjectAbbrev.isEmpty && absenceName == subjectAbbrev)
                || absenceName.contains(subjectName)
                || subjectName.contains(absenceName)
                || (!subjectAbbrev.isEmpty && absenceName.contains(subjectAbbrev))
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
