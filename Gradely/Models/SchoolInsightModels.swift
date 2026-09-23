import Foundation

/// A projection of personal Planner data. It never imports or copies provider payloads.
struct SchoolEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case homework, test, presentation, note, task }
    let id: UUID
    let scope: SchoolDataScope?
    let subjectID: String?
    let subjectName: String?
    let title: String
    let kind: Kind
    let date: Date
    let hasTime: Bool
    let timeZoneIdentifier: String
    let updatedAt: Date

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return value
    }
    var expiresAt: Date {
        hasTime ? date : (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date)
    }
    var isAssessment: Bool { kind == .test || kind == .presentation }
}

struct SchoolGradeObservation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let scope: SchoolDataScope
    let subjectID: String
    let observedAt: Date
    let previousObservedAt: Date
    let previousAverage: Double?
    let average: Double?
    let addedMarkIDs: [String]
    let editedMarkIDs: [String]
    let digest: String
    var seenAt: Date?

    var averageDelta: Double? {
        guard let previousAverage, let average else { return nil }
        return average - previousAverage
    }
    var isNewMark: Bool { !addedMarkIDs.isEmpty }
}

struct SubjectGradeContribution: Equatable, Sendable {
    let markID: String
    let markText: String
    let recordedAt: Date
    let reconstructedDelta: Double
}

struct SubjectInsightSummary: Equatable, Identifiable, Sendable {
    let subjectID: String
    let subjectName: String
    let currentAverage: Double?
    let observations: [SchoolGradeObservation]
    let trendDelta: Double?
    let upcomingEvents: [SchoolEvent]
    var recentContribution: SubjectGradeContribution? = nil
    var id: String { subjectID }
    var isWorsening: Bool { (trendDelta ?? 0) >= 0.20 - 0.000001 }
}

struct TodayInsight: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case assessment, deadline, averageChange, busyTests, worseningTrend, recentGrade
    }
    enum Destination: Codable, Equatable, Hashable, Sendable {
        case subject(String)
        case plannerItem(UUID)
        case planner
    }
    let id: String
    let kind: Kind
    let priority: Int
    let subjectID: String?
    let eventIDs: [UUID]
    let observationIDs: [String]
    let relevantAt: Date
    let observedAt: Date
    let expiresAt: Date
    let titleKey: String
    let arguments: [String]
    let destination: Destination

    var title: String {
        String(format: AppL10n.string(String.LocalizationValue(titleKey)), locale: AppLanguageOverride.locale, arguments: arguments.map { $0 as CVarArg })
    }
}
