import Foundation

enum SubjectInsightEngine {
    static func make(subjects: [Subject], preparedCalculations: [String: PreparedGradeCalculation],
                     observations: [SchoolGradeObservation], events: [SchoolEvent],
                     scope: SchoolDataScope, now: Date = Date()) -> [SubjectInsightSummary] {
        subjects.map { subject in
            let history = observations.filter { $0.scope == scope && $0.subjectID == subject.id }
                .sorted {
                    if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
                    return $0.id < $1.id
                }
            return SubjectInsightSummary(
                subjectID: subject.id, subjectName: subject.trimmedName,
                currentAverage: preparedCalculations[subject.id]?.displayAverage,
                observations: history, trendDelta: trendDelta(observations: history, now: now),
                upcomingEvents: events.filter {
                    $0.scope == scope && $0.subjectID == subject.id && $0.expiresAt > now
                },
                recentContribution: contribution(subject: subject, prepared: preparedCalculations[subject.id], now: now)
            )
        }
    }

    /// Reconstructs the effect of one of the five most recent recorded grades using the
    /// current calculation basis. This is deliberately separate from observed history.
    static func contribution(subject: Subject, prepared: PreparedGradeCalculation?, now: Date) -> SubjectGradeContribution? {
        guard let prepared else { return nil }
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let recent = prepared.marks.filter { $0.date.map { $0 >= cutoff && $0 <= now } ?? false }
            .sorted { $0.date == $1.date ? $0.id < $1.id : ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(5)
        return recent.compactMap { mark -> SubjectGradeContribution? in
            guard let date = mark.date, let delta = prepared.impact(of: mark.id), delta.isFinite,
                  let original = subject.marks.first(where: { $0.id == mark.id }) else { return nil }
            return SubjectGradeContribution(markID: mark.id, markText: original.displayText,
                                            recordedAt: date, reconstructedDelta: delta)
        }.sorted {
            if abs($0.reconstructedDelta) != abs($1.reconstructedDelta) { return abs($0.reconstructedDelta) > abs($1.reconstructedDelta) }
            return $0.markID < $1.markID
        }.first
    }

    /// A trend uses comparable successful observations, never grade dates or cloud polling gaps.
    static func trendDelta(observations: [SchoolGradeObservation], now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        var points: [Date: Double] = [:]
        for observation in observations {
            if observation.previousObservedAt >= cutoff, observation.previousObservedAt <= now,
               let average = observation.previousAverage, average.isFinite {
                points[observation.previousObservedAt] = average
            }
            if observation.observedAt >= cutoff, observation.observedAt <= now,
               let average = observation.average, average.isFinite {
                points[observation.observedAt] = average
            }
        }
        let dates = points.keys.sorted()
        guard dates.count >= 3, let first = dates.first, let last = dates.last,
              last.timeIntervalSince(first) >= 7 * 24 * 60 * 60,
              let start = points[first], let end = points[last], abs(end - start) >= 0.20 - 0.000001 else { return nil }
        return end - start
    }
}
