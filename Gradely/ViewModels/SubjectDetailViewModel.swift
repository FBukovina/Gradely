import Foundation
import Observation

@MainActor
@Observable
final class SubjectDetailViewModel {
    let subject: Subject
    let absence: AbsencePerSubject?
    let trend: SubjectGradeTrend?

    var theoreticalMark = ""
    var theoreticalWeight = 1
    var isPredictingExactAverage = false

    private let repository: SchoolRepository
    private var localTheoreticalAverage: Double?
    private var exactTheoreticalAverage: Double?
    @ObservationIgnored private var predictionTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAverageTimeline: [AverageTimelineEntry]?

    init(subject: Subject, absence: AbsencePerSubject?, repository: SchoolRepository, trend: SubjectGradeTrend? = nil) {
        self.subject = subject
        self.absence = absence
        self.repository = repository
        self.trend = trend
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

    // MARK: - Average chart

    enum ChartSource {
        case cloud
        case local
        case none
    }

    /// Running-average series derived from the subject's own marks; empty for
    /// points-only subjects. Cached — the subject never changes per detail push.
    var averageTimeline: [AverageTimelineEntry] {
        if let cachedAverageTimeline {
            return cachedAverageTimeline
        }
        let timeline = AverageTimeline.entries(for: subject)
        cachedAverageTimeline = timeline
        return timeline
    }

    var chartSource: ChartSource {
        if let trend, trend.events.filter({ $0.averageValue != nil }).count >= 2 {
            return .cloud
        }
        return averageTimeline.isEmpty ? .none : .local
    }

    var chartPoints: [AveragePoint] {
        switch chartSource {
        case .cloud:
            return (trend?.events ?? [])
                .compactMap { event in
                    event.averageValue.map {
                        AveragePoint(id: event.id, date: event.capturedAt, value: $0)
                    }
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
