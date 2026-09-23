import AppIntents
import SwiftUI

private struct GradeySiriServiceKey: EnvironmentKey {
    static let defaultValue: GradeyIntentService? = nil
}
extension EnvironmentValues {
    var gradeySiriService: GradeyIntentService? {
        get { self[GradeySiriServiceKey.self] }
        set { self[GradeySiriServiceKey.self] = newValue }
    }
}

enum GradeySiriViewContext {
    case subject(String, SchoolDataScope?)
    case lesson(ScheduledLesson, ScheduledDay, SchoolDataScope?)
    case planner(PlannerItem)

    func identifier(service: GradeyIntentService) -> EntityIdentifier? {
        guard let access = try? service.access() else { return nil }
        switch self {
        case .subject(let source, let scope):
            guard scope == access.scope else { return nil }
            let id = service.id(.subject, source: source, access: access)
            if #available(iOS 27, macOS 27, *) { return EntityIdentifier(for: GradeyIntelligenceSubjectEntity.self, identifier: id) }
            return EntityIdentifier(for: GradeySubjectEntity.self, identifier: id)
        case .lesson(let lesson, let day, let scope):
            guard scope == access.scope, day.date != nil else { return nil }
            let id = service.id(.lesson, source: service.lessonKey(lesson, day: day), access: access)
            if #available(iOS 27, macOS 27, *) { return EntityIdentifier(for: GradeyCalendarLessonEntity.self, identifier: id) }
            return EntityIdentifier(for: GradeyLessonEntity.self, identifier: id)
        case .planner(let item):
            guard GradeyIntentService.isVisible(item, scope: access.scope), !item.isCompleted else { return nil }
            let id = service.id(.planner, source: item.id.uuidString, access: access)
            if #available(iOS 27, macOS 27, *), item.type != .note { return EntityIdentifier(for: GradeyReminderEntity.self, identifier: id) }
            return EntityIdentifier(for: GradeyPlannerEntity.self, identifier: id)
        }
    }
}

private struct GradeySiriContextModifier: ViewModifier {
    let context: GradeySiriViewContext
    @Environment(\.gradeySiriService) private var service
    @State private var settings = GradeySiriDiscoverySettings.shared
    func body(content: Content) -> some View {
        content.appEntityIdentifier(settings.isEnabled ? service.flatMap { context.identifier(service: $0) } : nil)
    }
}
extension View {
    func gradeySiriContext(_ context: GradeySiriViewContext) -> some View { modifier(GradeySiriContextModifier(context: context)) }
}
