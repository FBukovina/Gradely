import Foundation
import Observation

@MainActor
@Observable
final class SubjectDetailViewModel {
    private(set) var subject: Subject
    private(set) var absence: AbsencePerSubject?
    private(set) var trend: SubjectGradeTrend?

    var theoreticalMark = ""
    var theoreticalWeight = 1
    var isPredictingExactAverage = false
    private(set) var preparedCalculation: PreparedGradeCalculation

    private let repository: SchoolRepository
    private var localTheoreticalAverage: Double?
    private var exactTheoreticalAverage: Double?
    @ObservationIgnored private var predictionTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAverageTimeline: [AverageTimelineEntry]?
    @ObservationIgnored private var predictionGeneration = UUID()

    init(subject: Subject, absence: AbsencePerSubject?, repository: SchoolRepository, trend: SubjectGradeTrend? = nil, prepared: PreparedGradeCalculation? = nil) {
        self.subject = subject
        self.absence = absence
        self.repository = repository
        self.trend = trend
        preparedCalculation = prepared ?? GradeMath.prepare(subject)
    }

    func updateAbsence(_ absence: AbsencePerSubject?) {
        self.absence = absence
    }

    var currentAverage: Double? {
        preparedCalculation.displayAverage
    }

    var averageFormatted: String {
        GradeMath.formattedAverage(currentAverage)
    }

    var sortedMarks: [Mark] {
        Dictionary(grouping: subject.marks, by: \.id).values.compactMap { marks in
            marks.sorted { ($0.editDate ?? "", $0.markText) > ($1.editDate ?? "", $1.markText) }.first
        }.sorted { lhs, rhs in
            let left = MarkDateFormatter.date(from: lhs.markDate) ?? .distantPast
            let right = MarkDateFormatter.date(from: rhs.markDate) ?? .distantPast
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    // MARK: - Average chart

    enum ChartSource {
        case cloud
        case local
        case none
    }

    /// Reuses the same prepared weights as the calculator and shared insights.
    var averageTimeline: [AverageTimelineEntry] {
        if let cachedAverageTimeline {
            return cachedAverageTimeline
        }
        let timeline = AverageTimeline.entries(for: subject, prepared: preparedCalculation)
        cachedAverageTimeline = timeline
        return timeline
    }

    var chartSource: ChartSource {
        if let trend, trend.events.filter({ $0.averageValue?.isFinite == true }).count >= 2 {
            return .cloud
        }
        return averageTimeline.isEmpty ? .none : .local
    }

    var chartPoints: [AveragePoint] {
        switch chartSource {
        case .cloud:
            return (trend?.events ?? [])
                .compactMap { event -> AveragePoint? in
                    guard let value = event.averageValue, value.isFinite else { return nil }
                    return AveragePoint(id: event.id, date: event.capturedAt, value: value)
                }
                .sorted { $0.date < $1.date }
        case .local:
            return averageTimeline.map {
                AveragePoint(id: $0.markID, date: $0.date, value: $0.runningAverage)
            }
        case .none:
            return []
        }
    }

    /// Movement over the charted window; cloud trends carry their own delta.
    var chartDelta: Double? {
        if chartSource == .cloud, let delta = trend?.averageDelta {
            return delta
        }
        guard let first = chartPoints.first, let last = chartPoints.last, chartPoints.count > 1 else {
            return nil
        }
        return last.value - first.value
    }

    var theoreticalAverage: Double? {
        exactTheoreticalAverage ?? localTheoreticalAverage
    }

    var theoreticalDifference: Double? {
        guard let theoreticalAverage else { return nil }
        // Compare like with like: provider response against provider baseline,
        // local simulation against local arithmetic, never mix the two.
        let baseline = exactTheoreticalAverage != nil ? preparedCalculation.officialAverage : preparedCalculation.calculatedAverage
        return baseline.map { theoreticalAverage - $0 }
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
        preparedCalculation.resolvedWeights[mark.id] ?? ResolvedMarkWeight(value: 1, source: .fallback)
    }

    var calculationWarningKey: String? {
        if preparedCalculation.issues.contains(.inconsistentOfficialAverage) { return "detail.intelligence.averageMismatch" }
        if preparedCalculation.issues.contains(.conflictingDuplicateIDs) || preparedCalculation.issues.contains(.invalidWeights) || preparedCalculation.issues.contains(.excludedMarks) {
            return "detail.intelligence.partialGrades"
        }
        if preparedCalculation.issues.contains(.modifierMapping) { return "detail.intelligence.modifierEstimate" }
        if preparedCalculation.issues.contains(.missingWeights) { return "detail.intelligence.assumedWeights" }
        if preparedCalculation.issues.contains(.inferredWeights) { return "detail.intelligence.inferredWeights" }
        return nil
    }

    /// The shared school store calls this for a new subject revision. User input
    /// survives a refresh of the same subject, while its numeric baseline updates.
    func updateSubject(_ subject: Subject, prepared: PreparedGradeCalculation? = nil, trend: SubjectGradeTrend? = nil) {
        let calculation = prepared ?? GradeMath.prepare(subject)
        let differentSubject = subject.id != self.subject.id
        let changedCalculation = calculation.revision != preparedCalculation.revision
        let predictionAvailabilityChanged = subject.markPredictionEnabled != self.subject.markPredictionEnabled
        self.subject = subject
        self.trend = trend
        preparedCalculation = calculation
        guard differentSubject || changedCalculation || predictionAvailabilityChanged else { return }
        cachedAverageTimeline = nil
        if differentSubject {
            theoreticalMark = ""
            theoreticalWeight = 1
        }
        refreshTheoreticalAverage()
    }

    private func refreshTheoreticalAverage() {
        predictionTask?.cancel()
        predictionGeneration = UUID()
        exactTheoreticalAverage = nil
        isPredictingExactAverage = false

        guard preparedCalculation.canSimulate,
              let value = GradeMath.parseMarkValue(theoreticalMark), !theoreticalMark.isEmpty,
              let simulation = GradeMath.simulate(preparedCalculation, adding: [HypotheticalGrade(value: value, weight: theoreticalWeight)]) else {
            localTheoreticalAverage = nil
            return
        }

        localTheoreticalAverage = simulation.estimatedAverage

        // Retain the existing provider prediction for one ordinary scenario.
        // Invalid/conflicting records and fractional weights cannot be faithfully
        // represented by the existing integer-weight what-if wire payload.
        guard subject.markPredictionEnabled,
              !preparedCalculation.issues.contains(.conflictingDuplicateIDs),
              !preparedCalculation.issues.contains(.invalidWeights),
              subject.marks.allSatisfy({ mark in
                  mark.weight.map { $0.isFinite && $0 >= 1 && $0 <= 10 && $0.rounded() == $0 } ?? true
              }) else { return }
        let generation = predictionGeneration

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
                          self.predictionGeneration == generation,
                          self.theoreticalMark == markText,
                          self.theoreticalWeight == selectedWeight
                    else {
                        return
                    }
                    if let exactAverage, exactAverage.isFinite {
                        self.exactTheoreticalAverage = exactAverage
                    }
                    self.isPredictingExactAverage = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.predictionGeneration == generation,
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
