import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox

// OS 27 schema adapters share identifiers and the exact same service as the OS 26 shortcuts.
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .calendar.calendar)
nonisolated struct GradeySchoolCalendarEntity {
    static let defaultQuery = GradeySchoolCalendarQuery()
    let id: String
    var title: String
    init(id: String, title: String) { self.id = id; self.title = title }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeySchoolCalendarQuery: EntityQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeySchoolCalendarEntity] {
        let token = try service.access().token
        return identifiers.contains(token) ? [.init(id: token, title: AppL10n.string("siri.schoolCalendar"))] : []
    }
}
@available(iOS 27, macOS 27, *)
@AppEnum(schema: .calendar.eventStatus)
nonisolated enum GradeyCalendarEventStatus: String {
    case confirmed, tentative, cancelled
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.confirmed: "Confirmed", .tentative: "Tentative", .cancelled: "Cancelled"]
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .calendar.event)
nonisolated struct GradeyCalendarLessonEntity: IndexedEntity {
    static let defaultQuery = GradeyCalendarLessonQuery()
    let id: String
    var calendar: GradeySchoolCalendarEntity
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var note: AttributedString?
    var status: GradeyCalendarEventStatus?
    var travelTime: Duration?
    var location: GradeyCalendarLocation?
    var virtualLocation: URL?
    var alarms: [GradeyCalendarAlarm]
    var organizers: [IntentPerson]
    var attendees: [GradeyCalendarAttendeeEntity]
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let value = CSSearchableItemAttributeSet(contentType: .text)
        value.title = title; value.startDate = startDate; value.endDate = endDate
        value.contentDescription = note.map(String.init)
        return value
    }
    init(_ record: GradeySiriLesson) {
        id = record.id
        calendar = .init(id: GradeySiriID(record.id)!.scope, title: "Gradey")
        title = record.title; startDate = record.start; endDate = record.end; isAllDay = false
        recurrence = nil; note = AttributedString([record.room, record.change].filter { !$0.isEmpty }.joined(separator: ", "))
        status = record.isCanceled ? .cancelled : .confirmed
        // A classroom number is not a street address; keep it in the event summary.
        travelTime = nil; location = nil
        virtualLocation = nil; alarms = []; organizers = []; attendees = []
    }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyCalendarLessonQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyCalendarLessonEntity] {
        try await service.resolveLessons(identifiers: identifiers).map(GradeyCalendarLessonEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyCalendarLessonEntity] {
        try await service.discoverySnapshot().lessons.filter { GradeyIntentService.matches(string, in: [$0.title, $0.room]) }.map(GradeyCalendarLessonEntity.init)
    }
}
@available(iOS 27, macOS 27, *)
@AppEnum(schema: .reminders.listType)
nonisolated enum GradeyReminderListType: String {
    case standard
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.standard: "Standard"]
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .reminders.list)
nonisolated struct GradeyReminderListEntity {
    static let defaultQuery = GradeyReminderListQuery()
    let id: String
    var name: String
    var type: GradeyReminderListType
    init(id: String, name: String, type: GradeyReminderListType) { self.id = id; self.name = name; self.type = type }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyReminderListQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyReminderListEntity] {
        let list = try current()
        return identifiers.contains(list.id) ? [list] : []
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyReminderListEntity] {
        let list = try current()
        return GradeyIntentService.matches(string, in: [list.name, "Gradey"]) ? [list] : []
    }
    @MainActor func suggestedEntities() async throws -> [GradeyReminderListEntity] { [try current()] }
    @MainActor private func current() throws -> GradeyReminderListEntity {
        .init(id: try service.access().token, name: AppL10n.string("planner.title"), type: .standard)
    }
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .reminders.reminder)
nonisolated struct GradeyReminderEntity: IndexedEntity {
    static let defaultQuery = GradeyReminderQuery()
    let id: String
    var title: String
    var note: AttributedString?
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool
    var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var list: GradeyReminderListEntity
    var locationTrigger: GradeyReminderLocationEntity?
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let value = CSSearchableItemAttributeSet(contentType: .text)
        value.title = title; value.dueDate = dueDate?.date
        return value
    }
    init(_ record: GradeySiriPlannerItem) {
        id = record.id; title = record.title; note = nil; tags = []; urls = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
        dueDate = record.date.map { date in
            var components = calendar.dateComponents(record.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: date)
            components.calendar = calendar; components.timeZone = calendar.timeZone
            return components
        }
        recurrence = nil; isCompleted = false; isFlagged = nil
        creationDate = record.createdAt; completionDate = nil
        list = .init(id: GradeySiriID(record.id)!.scope, name: "Planner", type: .standard)
        locationTrigger = nil
    }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyReminderQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyReminderEntity] {
        let records = try service.plannerItems().filter { $0.type != "note" }
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeyReminderEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyReminderEntity] {
        try service.plannerItems(matching: string).filter { $0.type != "note" }.map(GradeyReminderEntity.init)
    }
}

// Required schema types are representable for validation, but Gradey offers no location/section functionality.
@available(iOS 27, macOS 27, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
nonisolated enum GradeyReminderLocationEvent: String {
    case arrive, depart
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.arrive: "Arrive", .depart: "Depart"]
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .reminders.locationTrigger)
nonisolated struct GradeyReminderLocationEntity {
    static let defaultQuery = GradeyReminderLocationQuery()
    let id: String
    var place: PlaceDescriptor
    var event: GradeyReminderLocationEvent
    var displayRepresentation: DisplayRepresentation { .init(title: "Location reminder") }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyReminderLocationQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [GradeyReminderLocationEntity] { [] }
    func entities(for identifiers: [String]) async throws -> [GradeyReminderLocationEntity] { [] }
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .reminders.section)
nonisolated struct GradeyReminderSectionEntity {
    static let defaultQuery = GradeyReminderSectionQuery()
    let id: String
    var name: String
    var list: GradeyReminderListEntity
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyReminderSectionQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [GradeyReminderSectionEntity] { [] }
    func entities(for identifiers: [String]) async throws -> [GradeyReminderSectionEntity] { [] }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .reminders.createReminder)
nonisolated struct GradeyCreateReminderIntent {
    static let title: LocalizedStringResource = "Create Gradey reminder"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isAssistantOnly = true
    var title: String
    var list: GradeyReminderListEntity?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: GradeyReminderLocationEntity?
    var section: GradeyReminderSectionEntity?
    @Dependency var service: GradeyIntentService

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GradeyReminderEntity> & ProvidesDialog {
        guard recurrence == nil, locationTrigger == nil, section == nil, images.isEmpty,
              tags.isEmpty, urls.isEmpty, isFlagged != true else { throw GradeySiriError.unsupported }
        let access = try service.access()
        if let list, list.id != access.token { throw GradeySiriError.missingItem }
        let due = try service.resolveDueDate(dueDate)
        let prepared = try service.prepareCreation(title: title, type: .task, due: due.date, hasTime: due.hasTime,
            subjectID: nil, notes: note.map { String($0.characters) }, timeZone: due.timeZone)
        let result = try await service.create(prepared) {
            let text = String(format: AppL10n.string("siri.confirm"), prepared.summary)
            try await requestConfirmation(result: .result(dialog: "\(text)"))
        }
        let text = AppL10n.string(result.calendarPending ? "siri.created.pending" : "siri.created")
        return .result(value: GradeyReminderEntity(result.item), dialog: "\(text)")
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
nonisolated struct GradeyOpenCalendarLessonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open school lesson"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isAssistantOnly = true
    static let openAppWhenRun = true
    var target: GradeyCalendarLessonEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
nonisolated struct GradeyOpenReminderIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Gradey reminder"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isAssistantOnly = true
    static let openAppWhenRun = true
    var target: GradeyReminderEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
nonisolated struct GradeyOpenSchoolSubjectIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open school subject"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isAssistantOnly = true
    static let openAppWhenRun = true
    var target: GradeyIntelligenceSubjectEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}
@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
nonisolated struct GradeyOpenSchoolGradeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open school grade"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isAssistantOnly = true
    static let openAppWhenRun = true
    var target: GradeyIntelligenceGradeEntity
    @Dependency var service: GradeyIntentService
    @MainActor func perform() async throws -> some IntentResult { try await service.open(target.id); return .result() }
}

@available(iOS 27, macOS 27, *)
@UnionValue
enum GradeyCalendarLocation { case place(PlaceDescriptor); case address(String) }
@available(iOS 27, macOS 27, *)
@UnionValue
enum GradeyCalendarAlarm { case duration(Duration); case date(Date) }
@available(iOS 27, macOS 27, *)
@AppEnum(schema: .calendar.attendeeStatus)
nonisolated enum GradeyCalendarAttendeeStatus: String {
    case accepted, declined, tentative
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.accepted: "Accepted", .declined: "Declined", .tentative: "Tentative"]
}
@available(iOS 27, macOS 27, *)
@AppEnum(schema: .calendar.attendeeType)
nonisolated enum GradeyCalendarAttendeeType: String {
    case person
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.person: "Person"]
}
@available(iOS 27, macOS 27, *)
@AppEntity(schema: .calendar.attendee)
nonisolated struct GradeyCalendarAttendeeEntity: TransientAppEntity {
    var person: IntentPerson
    var status: GradeyCalendarAttendeeStatus?
    var isAttendanceOptional: Bool
    var type: GradeyCalendarAttendeeType?
    var displayRepresentation: DisplayRepresentation { .init(title: "Attendee") }
    init() { }
}

// A schema OpenIntent must have a unique entity target. These OS 27 projections preserve
// the original OS 26 Shortcuts OpenIntent contracts without weakening availability checks.
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyIntelligenceSubjectEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "School subject"
    static let defaultQuery = GradeyIntelligenceSubjectQuery()
    private let base: GradeySubjectEntity
    var id: String { base.id }
    @ComputedProperty(title: "Subject") var name: String { base.name }
    @ComputedProperty(title: "Abbreviation") var abbreviation: String { base.abbreviation }
    @ComputedProperty(title: "School average") var officialAverage: String? { base.officialAverage }
    @ComputedProperty(title: "Calculated average") var calculatedAverage: String? { base.calculatedAverage }
    @ComputedProperty(title: "Last updated") var updatedAt: Date { base.updatedAt }
    @ComputedProperty(title: "Cached data") var isStale: Bool { base.isStale }
    var displayRepresentation: DisplayRepresentation { base.displayRepresentation }
    var attributeSet: CSSearchableItemAttributeSet { base.attributeSet }
    init(_ record: GradeySiriSubject) { base = GradeySubjectEntity(record) }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyIntelligenceSubjectQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyIntelligenceSubjectEntity] {
        let records = try await service.subjects(refresh: false)
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeyIntelligenceSubjectEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyIntelligenceSubjectEntity] {
        try await service.subjects(matching: string).map(GradeyIntelligenceSubjectEntity.init)
    }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyIntelligenceGradeEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "School grade"
    static let defaultQuery = GradeyIntelligenceGradeQuery()
    private let base: GradeyGradeEntity
    var id: String { base.id }
    @ComputedProperty(title: "Subject") var subjectName: String { base.subjectName }
    @ComputedProperty(title: "Grade") var value: String { base.value }
    @ComputedProperty(title: "Date") var date: Date? { base.date }
    @ComputedProperty(title: "Last updated") var updatedAt: Date { base.updatedAt }
    @ComputedProperty(title: "Cached data") var isStale: Bool { base.isStale }
    var displayRepresentation: DisplayRepresentation { base.displayRepresentation }
    var attributeSet: CSSearchableItemAttributeSet { base.attributeSet }
    init(_ record: GradeySiriGrade) { base = GradeyGradeEntity(record) }
}
@available(iOS 27, macOS 27, *)
nonisolated struct GradeyIntelligenceGradeQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyIntelligenceGradeEntity] {
        let records = try await service.discoverySnapshot().grades
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeyIntelligenceGradeEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyIntelligenceGradeEntity] {
        try await service.discoverySnapshot().grades.filter { GradeyIntentService.matches(string, in: [$0.subjectName, $0.value]) }.map(GradeyIntelligenceGradeEntity.init)
    }
}
