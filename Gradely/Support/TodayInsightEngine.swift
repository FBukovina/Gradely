import Foundation

enum TodayInsightEngine {
    static let maximumVisibleInsights = 3
    static let gradeChangeLifetime: TimeInterval = 7 * 24 * 60 * 60

    static func make(subjectInsights: [SubjectInsightSummary], events: [SchoolEvent],
                     marksFetchedAt: Date?, now: Date = Date(), calendar: Calendar = .current,
                     schoolDataIsStale: Bool = false) -> [TodayInsight] {
        var candidates: [TodayInsight] = []
        let activeEvents = events.filter { $0.expiresAt > now && $0.kind != .note }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        for event in activeEvents where event.date <= tomorrow {
            // Date-only deadlines remain relevant until the end of their saved local day.
            let kind: TodayInsight.Kind = event.isAssessment ? .assessment : .deadline
            candidates.append(TodayInsight(
                id: "planner-\(event.id.uuidString)", kind: kind, priority: event.isAssessment ? 100 : 90,
                subjectID: event.subjectID, eventIDs: [event.id], observationIDs: [],
                relevantAt: event.date, observedAt: event.updatedAt, expiresAt: event.expiresAt,
                titleKey: event.isAssessment ? "insight.assessment.due" : "insight.deadline.due",
                arguments: [event.title], destination: .plannerItem(event.id)
            ))
        }
        let windowEnd = calendar.date(byAdding: .day, value: 4, to: now) ?? now.addingTimeInterval(4 * 24 * 60 * 60)
        let tests = activeEvents.filter { $0.kind == .test && $0.date <= windowEnd }
        if tests.count >= 3, let first = tests.first {
            candidates.append(TodayInsight(
                id: "busy-tests-" + tests.map { $0.id.uuidString }.sorted().joined(separator: "-"),
                kind: .busyTests, priority: 70, subjectID: nil, eventIDs: tests.map(\.id), observationIDs: [],
                relevantAt: first.date, observedAt: tests.map(\.updatedAt).max() ?? now,
                expiresAt: tests.map(\.expiresAt).min() ?? windowEnd,
                titleKey: "insight.busy.tests", arguments: [String(tests.count)], destination: .planner
            ))
        }

        if let marksFetchedAt, marksFetchedAt <= now, !schoolDataIsStale {
            for summary in subjectInsights {
                let unseen = summary.observations.filter {
                    $0.seenAt == nil && $0.observedAt <= now && now.timeIntervalSince($0.observedAt) < gradeChangeLifetime
                }
                for observation in unseen {
                    let meaningful = isMeaningfulAverageChange(from: observation.previousAverage, to: observation.average)
                    guard meaningful || observation.isNewMark || !observation.editedMarkIDs.isEmpty else { continue }
                    candidates.append(TodayInsight(
                        id: "grade-\(observation.id)", kind: meaningful ? .averageChange : .recentGrade,
                        priority: meaningful ? 80 : 50, subjectID: summary.subjectID, eventIDs: [],
                        observationIDs: [observation.id], relevantAt: observation.observedAt,
                        observedAt: observation.observedAt, expiresAt: observation.observedAt.addingTimeInterval(gradeChangeLifetime),
                        titleKey: meaningful ? "insight.average.changed" : (observation.isNewMark ? "insight.grade.new" : "insight.grade.edited"),
                        arguments: meaningful ? [summary.subjectName, GradeMath.formattedAverage(observation.previousAverage), GradeMath.formattedAverage(observation.average)] : [summary.subjectName],
                        destination: .subject(summary.subjectID)
                    ))
                }
                if summary.isWorsening, let last = summary.observations.max(by: {
                    $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt < $1.observedAt
                }),
                   last.observedAt <= now, now.timeIntervalSince(last.observedAt) < gradeChangeLifetime {
                    candidates.append(TodayInsight(
                        id: "trend-\(summary.subjectID)-\(last.digest)", kind: .worseningTrend, priority: 60,
                        subjectID: summary.subjectID, eventIDs: [], observationIDs: [],
                        relevantAt: last.observedAt, observedAt: last.observedAt,
                        expiresAt: last.observedAt.addingTimeInterval(gradeChangeLifetime),
                        titleKey: "insight.trend.worsening", arguments: [summary.subjectName],
                        destination: .subject(summary.subjectID)
                    ))
                }
            }
        }
        return rank(candidates, now: now)
    }

    static func rank(_ candidates: [TodayInsight], now: Date) -> [TodayInsight] {
        let sorted = candidates.filter { $0.expiresAt > now }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            let firstUrgency = $0.eventIDs.isEmpty ? Date.distantFuture : $0.relevantAt
            let secondUrgency = $1.eventIDs.isEmpty ? Date.distantFuture : $1.relevantAt
            if firstUrgency != secondUrgency { return firstUrgency < secondUrgency }
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.id < $1.id
        }
        var seenIDs: Set<String> = []
        var gradeSubjects: Set<String> = []
        var eventIDs: Set<UUID> = []
        var output: [TodayInsight] = []
        for candidate in sorted {
            guard seenIDs.insert(candidate.id).inserted else { continue }
            if !eventIDs.isDisjoint(with: candidate.eventIDs) { continue }
            if candidate.eventIDs.isEmpty, let subjectID = candidate.subjectID {
                guard gradeSubjects.insert(subjectID).inserted else { continue }
            }
            output.append(candidate)
            eventIDs.formUnion(candidate.eventIDs)
            if output.count == maximumVisibleInsights { break }
        }
        return output
    }

    static func isMeaningfulAverageChange(from previous: Double?, to current: Double?) -> Bool {
        guard let previous, let current, previous.isFinite, current.isFinite else { return false }
        let delta = abs(current - previous)
        if delta >= 0.20 - 0.000001 { return true }
        guard delta >= 0.10 - 0.000001 else { return false }
        return [1.5, 2.5, 3.5, 4.5].contains { boundary in
            (previous < boundary && current >= boundary) || (previous > boundary && current <= boundary)
        }
    }
}
