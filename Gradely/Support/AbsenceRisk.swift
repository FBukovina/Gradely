import Foundation

enum AbsenceRiskLevel: String, Codable, Equatable, Sendable {
    case unavailable
    case safe
    case watch
    case high
    case overLimit
}

struct AbsenceRiskSubject: Codable, Equatable, Identifiable, Sendable {
    let subjectName: String
    let missedLessons: Int
    let totalLessons: Int
    let percentage: Double
    let threshold: Double?
    let level: AbsenceRiskLevel
    let missesUntilLimit: Int?

    var id: String { subjectName }
}

struct AbsenceRiskSummary: Codable, Equatable, Sendable {
    let threshold: Double?
    let subjects: [AbsenceRiskSubject]

    var highestRisk: AbsenceRiskSubject? {
        subjects.sorted { first, second in
            Self.levelRank(first.level) > Self.levelRank(second.level)
                || (Self.levelRank(first.level) == Self.levelRank(second.level) && first.percentage > second.percentage)
        }.first
    }

    var isThresholdUnavailable: Bool {
        threshold == nil
    }

    static func make(response: AbsenceResponse, subjects: [AbsencePerSubject]) -> AbsenceRiskSummary {
        let threshold = normalizedThreshold(response.percentageThreshold)
        let risks = subjects.map { subject in
            let percentage = subject.absencePercentage
            let level = level(for: percentage, threshold: threshold)
            return AbsenceRiskSubject(
                subjectName: subject.subjectName,
                missedLessons: subject.base,
                totalLessons: subject.lessonsCount,
                percentage: percentage,
                threshold: threshold,
                level: level,
                missesUntilLimit: missesUntilLimit(
                    missedLessons: subject.base,
                    totalLessons: subject.lessonsCount,
                    threshold: threshold
                )
            )
        }
        .sorted { first, second in
            levelRank(first.level) > levelRank(second.level)
                || (levelRank(first.level) == levelRank(second.level) && first.percentage > second.percentage)
        }

        return AbsenceRiskSummary(threshold: threshold, subjects: risks)
    }

    static func normalizedThreshold(_ threshold: Double?) -> Double? {
        guard let threshold, threshold > 0 else { return nil }
        return threshold <= 1 ? threshold * 100 : threshold
    }

    static func level(for percentage: Double, threshold: Double?) -> AbsenceRiskLevel {
        guard let threshold, threshold > 0 else { return .unavailable }
        let ratio = percentage / threshold
        if ratio >= 1 { return .overLimit }
        if ratio >= 0.9 { return .high }
        if ratio >= 0.7 { return .watch }
        return .safe
    }

    static func missesUntilLimit(missedLessons: Int, totalLessons: Int, threshold: Double?) -> Int? {
        guard let threshold, threshold > 0, totalLessons > 0 else { return nil }
        let thresholdRatio = threshold / 100
        guard thresholdRatio < 1 else { return nil }

        if Double(missedLessons) / Double(totalLessons) >= thresholdRatio {
            return 0
        }

        var futureMisses = 0
        while futureMisses < 10_000 {
            futureMisses += 1
            let futureMissed = missedLessons + futureMisses
            let futureTotal = totalLessons + futureMisses
            if Double(futureMissed) / Double(futureTotal) >= thresholdRatio {
                return futureMisses
            }
        }
        return nil
    }

    private static func levelRank(_ level: AbsenceRiskLevel) -> Int {
        switch level {
        case .overLimit: 4
        case .high: 3
        case .watch: 2
        case .safe: 1
        case .unavailable: 0
        }
    }
}

extension AbsenceRiskSubject {
    /// Risk info for an already-resolved absence row, normalizing fractional
    /// thresholds (0…1) to percentages the same way `AbsenceSubjectSummary` does
    /// so the bar, percentage tint, and `exceedsThreshold` never disagree.
    static func make(summary: AbsenceSubjectSummary, threshold: Double?) -> AbsenceRiskSubject {
        let normalizedThreshold = AbsenceRiskSummary.normalizedThreshold(threshold)
        return AbsenceRiskSubject(
            subjectName: summary.subjectName,
            missedLessons: summary.base,
            totalLessons: summary.lessonsCount,
            percentage: summary.absencePercentage,
            threshold: normalizedThreshold,
            level: AbsenceRiskSummary.level(for: summary.absencePercentage, threshold: normalizedThreshold),
            missesUntilLimit: AbsenceRiskSummary.missesUntilLimit(
                missedLessons: summary.base,
                totalLessons: summary.lessonsCount,
                threshold: normalizedThreshold
            )
        )
    }
}
