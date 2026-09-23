import AppIntents
import CoreSpotlight
import Foundation

nonisolated struct GradeySubjectEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "School subject"
    static let defaultQuery = GradeySubjectQuery()
    let id: String
    @Property(title: "Subject") var name: String
    @Property(title: "Abbreviation") var abbreviation: String
    @Property(title: "School average") var officialAverage: String?
    @Property(title: "Calculated average") var calculatedAverage: String?
    @Property(title: "Last updated") var updatedAt: Date
    @Property(title: "Cached data") var isStale: Bool
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(abbreviation)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name
        attributes.contentDescription = [abbreviation,
            officialAverage.map { String(format: String(localized: "siri.average.school"), $0) },
            calculatedAverage.map { String(format: String(localized: "siri.average.calculated"), $0) }
        ].compactMap { $0 }.joined(separator: " · ")
        attributes.contentModificationDate = updatedAt
        return attributes
    }
    init(_ record: GradeySiriSubject) {
        id = record.id; name = record.name; abbreviation = record.abbreviation
        officialAverage = record.officialAverage; calculatedAverage = record.calculatedAverage
        updatedAt = record.updatedAt; isStale = record.isStale
    }
}
nonisolated struct GradeyGradeEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "School grade"
    static let defaultQuery = GradeyGradeQuery()
    let id: String
    let subjectID: String
    @Property(title: "Subject") var subjectName: String
    @Property(title: "Grade") var value: String
    @Property(title: "Date") var date: Date?
    @Property(title: "Last updated") var updatedAt: Date
    @Property(title: "Cached data") var isStale: Bool
    var displayRepresentation: DisplayRepresentation { .init(title: "\(subjectName): \(value)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = subjectName + ": " + value
        attributes.contentCreationDate = date
        attributes.contentModificationDate = updatedAt
        return attributes
    }
    init(_ record: GradeySiriGrade) {
        id = record.id; subjectID = record.subjectID; subjectName = record.subjectName; value = record.value
        date = record.date; updatedAt = record.updatedAt; isStale = record.isStale
    }
}
nonisolated struct GradeyLessonEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "School lesson"
    static let defaultQuery = GradeyLessonQuery()
    let id: String
    @Property(title: "Lesson") var name: String
    @Property(title: "Start") var start: Date
    @Property(title: "End") var end: Date
    @Property(title: "Room") var room: String
    @Property(title: "Change") var change: String
    @Property(title: "Canceled") var isCanceled: Bool
    @Property(title: "Last updated") var updatedAt: Date
    @Property(title: "Cached data") var isStale: Bool
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(room) \(change)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name; attributes.contentDescription = [room, change].joined(separator: " · ")
        attributes.startDate = start; attributes.endDate = end; attributes.contentModificationDate = updatedAt
        return attributes
    }
    init(_ record: GradeySiriLesson) {
        id = record.id; name = record.title; start = record.start; end = record.end; room = record.room
        change = record.change; isCanceled = record.isCanceled; updatedAt = record.updatedAt; isStale = record.isStale
    }
}
nonisolated struct GradeyPlannerEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Planner item"
    static let defaultQuery = GradeyPlannerQuery()
    let id: String
    @Property(title: "Title") var name: String
    @Property(title: "Item type") var itemType: String
    @Property(title: "Subject") var subjectName: String?
    @Property(title: "Due date") var dueDate: Date?
    @Property(title: "Include time") var hasTime: Bool
    @Property(title: "Time zone") var timeZoneIdentifier: String
    @Property(title: "Last updated") var updatedAt: Date
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(subjectName ?? "")") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name; attributes.contentDescription = subjectName
        attributes.dueDate = dueDate; attributes.contentModificationDate = updatedAt
        return attributes
    }
    init(_ record: GradeySiriPlannerItem) {
        id = record.id; name = record.title; itemType = record.type; subjectName = record.subjectName
        dueDate = record.date; hasTime = record.hasTime; timeZoneIdentifier = record.timeZoneIdentifier; updatedAt = record.updatedAt
    }
}

nonisolated struct GradeySubjectQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeySubjectEntity] {
        let records = try await service.subjects(refresh: false)
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeySubjectEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeySubjectEntity] {
        try await service.subjects(matching: string).map(GradeySubjectEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [GradeySubjectEntity] {
        try await service.subjects(refresh: false).map(GradeySubjectEntity.init)
    }
}
nonisolated struct GradeyGradeQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyGradeEntity] {
        let records = try await service.discoverySnapshot().grades
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeyGradeEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyGradeEntity] {
        try await service.discoverySnapshot().grades.filter { GradeyIntentService.matches(string, in: [$0.subjectName, $0.value]) }.map(GradeyGradeEntity.init)
    }
}
nonisolated struct GradeyLessonQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyLessonEntity] {
        try await service.resolveLessons(identifiers: identifiers).map(GradeyLessonEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyLessonEntity] {
        try await service.discoverySnapshot().lessons.filter { GradeyIntentService.matches(string, in: [$0.title, $0.room]) }.map(GradeyLessonEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [GradeyLessonEntity] {
        try await service.discoverySnapshot().lessons.filter { !$0.isCanceled && $0.end > Date() }.map(GradeyLessonEntity.init)
    }
}
nonisolated struct GradeyPlannerQuery: EntityStringQuery {
    @Dependency var service: GradeyIntentService
    @MainActor func entities(for identifiers: [String]) async throws -> [GradeyPlannerEntity] {
        let records = try service.plannerItems()
        return identifiers.compactMap { id in records.first { $0.id == id }.map(GradeyPlannerEntity.init) }
    }
    @MainActor func entities(matching string: String) async throws -> [GradeyPlannerEntity] {
        try service.plannerItems(matching: string).map(GradeyPlannerEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [GradeyPlannerEntity] {
        try service.plannerItems().map(GradeyPlannerEntity.init)
    }
}

/// A structured Shortcuts output carries both kinds of average even when a subject has no recent grades.
nonisolated struct GradeyGradesResult: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Subject grades"
    @Property(title: "Subject") var subject: GradeySubjectEntity?
    @Property(title: "Recent grades") var recentGrades: [GradeyGradeEntity]
    var displayRepresentation: DisplayRepresentation { .init(title: "\(subject?.name ?? "")") }
    init() { subject = nil; recentGrades = [] }
    init(subject: GradeySubjectEntity, grades: [GradeyGradeEntity]) { self.subject = subject; self.recentGrades = grades }
}
