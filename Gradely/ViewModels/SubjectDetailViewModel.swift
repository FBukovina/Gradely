import Foundation
import Observation

@MainActor
@Observable
final class SubjectDetailViewModel {
    let subject: Subject
    let absence: AbsencePerSubject?

    var theoreticalMark = ""
    var theoreticalWeight = 1
    var isPredictingExactAverage = false

    private let repository: BakalariRepository
    private var localTheoreticalAverage: Double?
    private var exactTheoreticalAverage: Double?
    @ObservationIgnored private var predictionTask: Task<Void, Never>?

    init(subject: Subject, absence: AbsencePerSubject?, repository: BakalariRepository) {
        self.subject = subject
        self.absence = absence
        self.repository = repository
    }

    var currentAverage: Double? {
        GradeMath.subjectAverage(subject)
    }

    var averageFormatted: String {
        GradeMath.formattedAverage(currentAverage)
    }

    var sortedMarks: [Mark] {
        subject.marks.sorted { lhs, rhs in
            (MarkDateFormatter.date(from: lhs.markDate) ?? .distantPast) > (MarkDateFormatter.date(from: rhs.markDate) ?? .distantPast)
        }
    }

    var theoreticalAverage: Double? {
        exactTheoreticalAverage ?? localTheoreticalAverage
    }

    var theoreticalDifference: Double? {
        guard let theoreticalAverage, let currentAverage else { return nil }
        return theoreticalAverage - currentAverage
    }

    func updateTheoreticalMark(_ newValue: String) {
        guard newValue.count <= 3 else { return }
        theoreticalMark = newValue
        refreshTheoreticalAverage()
    }

    func decrementWeight() {
        theoreticalWeight = max(1, theoreticalWeight - 1)
        refreshTheoreticalAverage()
    }

    func incrementWeight() {
        theoreticalWeight = min(10, theoreticalWeight + 1)
        refreshTheoreticalAverage()
    }

    func resolvedWeight(for mark: Mark) -> ResolvedMarkWeight {
        GradeMath.resolvedWeight(for: mark, in: subject)
    }

    private func refreshTheoreticalAverage() {
        predictionTask?.cancel()
        exactTheoreticalAverage = nil
        isPredictingExactAverage = false

        guard let value = GradeMath.parseMarkValue(theoreticalMark), !theoreticalMark.isEmpty else {
            localTheoreticalAverage = nil
            return
        }

        localTheoreticalAverage = GradeMath.theoreticalAverage(
            existingMarks: subject.marks,
            subjectAverageText: subject.averageText,
            markValue: value,
            weight: theoreticalWeight
        )

        guard subject.markPredictionEnabled else { return }

        let markText = theoreticalMark
        let selectedWeight = theoreticalWeight
        let subjectSnapshot = subject
        let repositorySnapshot = repository

        isPredictingExactAverage = true
        predictionTask = Task { [weak self, repositorySnapshot, subjectSnapshot] in
            do {
                let exactAverage = try await repositorySnapshot.predictSubjectAverage(
                    subject: subjectSnapshot,
                    markText: markText,
                    weight: selectedWeight
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.theoreticalMark == markText,
                          self.theoreticalWeight == selectedWeight
                    else {
                        return
                    }
                    if let exactAverage {
                        self.exactTheoreticalAverage = exactAverage
                    }
                    self.isPredictingExactAverage = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.theoreticalMark == markText,
                          self.theoreticalWeight == selectedWeight
                    else {
                        return
                    }
                    self.isPredictingExactAverage = false
                }
            }
        }
    }
}
