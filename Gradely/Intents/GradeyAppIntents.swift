import AppIntents
import Foundation

nonisolated enum GradeySiriGradeMode: String, AppEnum {
    case average, recent
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Grade information"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.average: "Average", .recent: "Recent grades"]
}
nonisolated enum GradeySiriPlannerType: String, AppEnum {
    case homework, test, presentation, note, task
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Planner item type"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .homework: "Homework", .test: "Test", .presentation: "Presentation", .note: "Note", .task: "Task"
    ]
}

nonisolated struct GradeyNextLessonIntent: AppIntent {
    static let title: LocalizedStringResource = "Get next lesson"
    static let description = IntentDescription("Find your next scheduled lesson in Gradey.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GradeyLessonEntity]> & ProvidesDialog {
        let records = try await service.nextLessons()
        var text = GradeyIntentService.summary(records.map(GradeySiriSpeech.lesson), emptyKey: "siri.noNextLesson")
        if records.isEmpty { text += " " + (try service.scheduleFreshness(on: Date())) + " " + (try service.scheduleFreshness(on: TimetableDates.addingWeeks(1, to: Date()))) }
        return .result(value: records.map(GradeyLessonEntity.init), dialog: "\(text)")
    }
}
nonisolated struct GradeyScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Get school schedule"
    static let description = IntentDescription("Read lessons and timetable changes for a day.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Date") var date: Date?
    @Dependency var service: GradeyIntentService
    static var parameterSummary: some ParameterSummary { Summary("Get the schedule for \(\.$date)") }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GradeyLessonEntity]> & ProvidesDialog {
        let records = try await service.schedule(on: date ?? Date())
        var text = GradeyIntentService.summary(records.map(GradeySiriSpeech.lesson), emptyKey: "siri.noLessons")
        if records.isEmpty { text += " " + (try service.scheduleFreshness(on: date ?? Date())) }
        return .result(value: records.map(GradeyLessonEntity.init), dialog: "\(text)")
    }
}
nonisolated struct GradeyGradesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get subject grades"
    static let description = IntentDescription("Read a subject’s school average, calculated average, or recent grades.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Subject", requestValueDialog: "Which subject?") var subject: GradeySubjectEntity
    @Parameter(title: "Information", default: .average) var information: GradeySiriGradeMode
    @Dependency var service: GradeyIntentService
    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$information) for \(\.$subject)") }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GradeyGradesResult> & ProvidesDialog {
        let records = try await service.grades(subjectID: subject.id)
        let resolved = try await service.subjects(refresh: false).first { $0.id == subject.id }
        guard let resolved else { throw GradeySiriError.missingItem }
        let text: String
        if information == .average {
            let school = resolved.officialAverage.map { String(format: AppL10n.string("siri.average.school"), $0) }
            let calculated = resolved.calculatedAverage.map { String(format: AppL10n.string("siri.average.calculated"), $0) }
            text = [resolved.name, school, calculated,
                school == nil && calculated == nil ? AppL10n.string("siri.average.unavailable") : nil,
                GradeyIntentService.freshness(resolved.updatedAt, stale: resolved.isStale)].compactMap { $0 }.joined(separator: ". ")
        } else {
            text = GradeyIntentService.summary(records.map { record in
                [record.value, record.date.map { GradeyIntentService.dateText($0, hasTime: false) }].compactMap { $0 }.joined(separator: ", ")
            }) + " " + GradeyIntentService.freshness(resolved.updatedAt, stale: resolved.isStale)
        }
        return .result(value: GradeyGradesResult(subject: GradeySubjectEntity(resolved), grades: records.map(GradeyGradeEntity.init)), dialog: "\(text)")
    }
}
nonisolated struct GradeyFindPlannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Planner items"
    static let description = IntentDescription("Find incomplete personal Planner items, including undated tasks.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Subject") var subject: GradeySubjectEntity?
    @Parameter(title: "Search") var query: String?
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GradeyPlannerEntity]> & ProvidesDialog {
        let records = try service.plannerItems(on: date, subjectID: subject?.id, matching: query)
        let text = GradeyIntentService.summary(records.map(GradeySiriSpeech.planner))
        return .result(value: records.map(GradeyPlannerEntity.init), dialog: "\(text)")
    }
}
nonisolated struct GradeyAddPlannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Planner item"
    static let description = IntentDescription("Add a personal Planner item after confirming its details.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Title", requestValueDialog: "What would you like to add?") var name: String
    @Parameter(title: "Item type", default: .homework) var itemType: GradeySiriPlannerType
    @Parameter(title: "Due date") var dueDate: Date?
    @Parameter(title: "Include time", default: false) var includeTime: Bool
    @Parameter(title: "Subject") var subject: GradeySubjectEntity?
    @Parameter(title: "Notes") var notes: String?
    @Dependency var service: GradeyIntentService
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) to Planner") { \.$itemType; \.$dueDate; \.$includeTime; \.$subject; \.$notes }
    }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GradeyPlannerEntity> & ProvidesDialog {
        let prepared = try service.prepareCreation(title: name, type: PlannerItemType(rawValue: itemType.rawValue)!,
            due: dueDate, hasTime: includeTime, subjectID: subject?.id, notes: notes)
        let result = try await service.create(prepared) {
            let text = String(format: AppL10n.string("siri.confirm"), prepared.summary)
            try await requestConfirmation(result: .result(dialog: "\(text)"))
        }
        let text = AppL10n.string(result.calendarPending ? "siri.created.pending" : "siri.created")
        return .result(value: GradeyPlannerEntity(result.item), dialog: "\(text)")
    }
}

nonisolated struct GradeyOpenSubjectIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open subject in Gradey"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Subject") var target: GradeySubjectEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
nonisolated struct GradeyOpenGradeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open grade in Gradey"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Grade") var target: GradeyGradeEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
nonisolated struct GradeyOpenLessonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open lesson in Gradey"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Lesson") var target: GradeyLessonEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
nonisolated struct GradeyOpenPlannerIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Planner item in Gradey"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Planner item") var target: GradeyPlannerEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}

nonisolated struct GradeyAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GradeyNextLessonIntent(), phrases: ["What's my next lesson in \(.applicationName)", "Next lesson in \(.applicationName)"], shortTitle: "Next lesson", systemImageName: "clock")
        AppShortcut(intent: GradeyScheduleIntent(), phrases: ["My schedule in \(.applicationName)"], shortTitle: "School schedule", systemImageName: "calendar")
        AppShortcut(intent: GradeyGradesIntent(), phrases: ["My grades in \(.applicationName)"], shortTitle: "Subject grades", systemImageName: "graduationcap")
        AppShortcut(intent: GradeyFindPlannerIntent(), phrases: ["My Planner in \(.applicationName)"], shortTitle: "Find Planner items", systemImageName: "checklist")
        AppShortcut(intent: GradeyAddPlannerIntent(), phrases: ["Add a Planner item in \(.applicationName)"], shortTitle: "Add Planner item", systemImageName: "plus")
        AppShortcut(intent: GradeyOpenSubjectIntent(), phrases: ["Open a subject in \(.applicationName)"], shortTitle: "Open subject", systemImageName: "book")
    }
}

@MainActor enum GradeySiriSpeech {
    static func lesson(_ record: GradeySiriLesson) -> String {
        [record.title, GradeyIntentService.dateText(record.start), record.room, record.change,
         GradeyIntentService.freshness(record.updatedAt, stale: record.isStale)].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    static func planner(_ record: GradeySiriPlannerItem) -> String {
        [record.title, record.subjectName, record.date.map {
            GradeyIntentService.dateText($0, hasTime: record.hasTime, timeZone: TimeZone(identifier: record.timeZoneIdentifier) ?? .current)
        } ?? AppL10n.string("siri.undated")].compactMap { $0 }.joined(separator: ", ")
    }
}
