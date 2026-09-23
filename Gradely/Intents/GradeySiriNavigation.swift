import Foundation

/// Resolved against current stores, never against an entity's potentially stale display payload.
struct GradeySiriDestination {
    let requestID = UUID()
    let id: String
    let subjectID: String?
    let lesson: ScheduledLesson?
    let day: ScheduledDay?
    let plannerItemID: UUID?
    let scope: SchoolDataScope
    let generation: UUID
}

extension GradeyIntentService {
    func resolveDestination(_ value: String) async throws -> GradeySiriDestination {
        let expected = try access()
        guard let identifier = GradeySiriID(value), identifier.scope == expected.token else { throw GradeySiriError.missingItem }
        snapshot.activateCurrentScope()
        switch identifier.kind {
        case .subject, .grade:
            _ = try await subjects()
            try validate(expected)
            let subject = snapshot.subjects.first { subject in
                if identifier.kind == .subject { return id(.subject, source: subject.id, access: expected) == value }
                return subject.marks.contains { id(.grade, source: subject.id + "\u{1f}" + $0.id, access: expected) == value }
            }
            guard let subject else { throw GradeySiriError.missingItem }
            return GradeySiriDestination(id: value, subjectID: subject.id, lesson: nil, day: nil, plannerItemID: nil, scope: expected.scope, generation: expected.generation)
        case .lesson:
            guard let date = lessonDate(identifier) else { throw GradeySiriError.missingItem }
            _ = try await schedule(on: date)
            try validate(expected)
            for day in cachedWeek(containing: date)?.days ?? [] {
                if let lesson = day.lessons.first(where: { id(.lesson, source: lessonKey($0, day: day), access: expected) == value }) {
                    return GradeySiriDestination(id: value, subjectID: nil, lesson: lesson, day: day, plannerItemID: nil, scope: expected.scope, generation: expected.generation)
                }
            }
            throw GradeySiriError.missingItem
        case .planner:
            _ = try plannerItems()
            guard let item = planner.items.first(where: { Self.isVisible($0, scope: expected.scope) && id(.planner, source: $0.id.uuidString, access: expected) == value }) else { throw GradeySiriError.missingItem }
            return GradeySiriDestination(id: value, subjectID: nil, lesson: nil, day: nil, plannerItemID: item.id, scope: expected.scope, generation: expected.generation)
        }
    }

    func open(_ value: String) async throws {
        let destination = try await resolveDestination(value)
        try validateDestination(destination)
        guard let identifier = GradeySiriID(value) else { throw GradeySiriError.missingItem }
        SchoolNotificationRouter.shared.pendingURL = identifier.url
    }

    func validateDestination(_ destination: GradeySiriDestination) throws {
        guard let identifier = GradeySiriID(destination.id) else { throw GradeySiriError.missingItem }
        try validate(Access(scope: destination.scope, token: identifier.scope, generation: destination.generation))
    }

    func lessonDate(_ id: GradeySiriID) -> Date? {
        guard id.kind == .lesson else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd"; formatter.isLenient = false
        let key = String(id.key.prefix(8))
        guard let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }
}
