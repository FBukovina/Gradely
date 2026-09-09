import Foundation

enum PlannerItemType: String, Codable, CaseIterable, Identifiable {
    case homework, test, presentation, note, task

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: AppL10n.string("planner.type.homework")
        case .test: AppL10n.string("planner.type.test")
        case .presentation: AppL10n.string("planner.type.presentation")
        case .note: AppL10n.string("planner.type.note")
        case .task: AppL10n.string("planner.type.task")
        }
    }

    var systemImage: String {
        switch self {
        case .homework: "text.book.closed.fill"
        case .test: "square.and.pencil"
        case .presentation: "person.2.fill"
        case .note: "text.book.closed.fill"
        case .task: "checklist"
        }
    }
}

/// Small, durable references, scoped to the school account. Provider objects stay in the timetable.
struct PlannerSubjectReference: Codable, Equatable {
    let scope: SchoolDataScope
    let id: String
    let name: String
    let abbreviation: String?

    var displayName: String { abbreviation.flatMap { $0.isEmpty ? nil : $0 } ?? name }
}

struct PlannerLessonReference: Codable, Equatable {
    let scope: SchoolDataScope
    let lessonID: String
    let dayKey: String
    let hourID: Int
    let subjectID: String?
    let groupIDs: [String]
    let start: Date?
    let end: Date?
    let hourCaption: String
    let teacher: String?
    let room: String?

    init(lesson: ScheduledLesson, day: ScheduledDay, scope: SchoolDataScope, calendar: Calendar = .current) {
        self.scope = scope
        lessonID = lesson.id
        dayKey = Self.dayKey(day)
        hourID = lesson.hour.id
        subjectID = lesson.subjectID
        groupIDs = lesson.groupIDs.sorted()
        start = day.date.flatMap { TimetableLessonTiming.date(lesson.hour.beginTime, on: $0, calendar: calendar) }
        end = day.date.flatMap { TimetableLessonTiming.date(lesson.hour.endTime, on: $0, calendar: calendar) }
        hourCaption = lesson.hour.caption
        teacher = lesson.teacherName ?? lesson.teacherAbbrev
        room = lesson.roomAbbrev ?? lesson.roomName
    }

    func matches(lesson: ScheduledLesson, day: ScheduledDay, scope: SchoolDataScope) -> Bool {
        // Atom offsets, room changes and teacher substitutions must not move a personal link.
        self.scope == scope && dayKey == Self.dayKey(day) && hourID == lesson.hour.id
            && subjectID == lesson.subjectID && groupIDs == lesson.groupIDs.sorted()
    }

    private static func dayKey(_ day: ScheduledDay) -> String {
        day.date.map(TimetableDates.apiDateString) ?? day.id
    }
}

struct PlannerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var notes: String?
    var type: PlannerItemType = .homework
    var subject: PlannerSubjectReference?
    var lesson: PlannerLessonReference?
    var linkedDate: Date?
    var dueDate: Date?
    var dueHasTime = false
    var isCompleted = false
    var createdAt = Date()
    var updatedAt = Date()
    var timeZoneIdentifier = TimeZone.current.identifier
    /// New items opt into the Gradey calendar. `PlannerStore` clears this again for
    /// items with no day or due date, which have nothing to export.
    var calendarSyncEnabled = true
    var calendarEventIdentifier: String?

    // Durable outbound work. Tombstones retain only what is needed until event removal succeeds.
    var calendarNeedsSync = false
    var calendarLastStart: Date?
    var calendarLastEnd: Date?
    var deletedAt: Date?

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    var orderingDate: Date? { dueDate ?? lesson?.start ?? linkedDate }
    var hasCalendarDate: Bool { orderingDate != nil }
    var calendarURL: URL { URL(string: "gradey://planner/item/\(id.uuidString)")! }

    static func linked(to lesson: ScheduledLesson, on day: ScheduledDay, scope: SchoolDataScope) -> PlannerItem {
        var item = PlannerItem()
        if let subjectID = lesson.subjectID, !subjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.subject = PlannerSubjectReference(
                scope: scope, id: subjectID,
                name: lesson.subjectName ?? lesson.title, abbreviation: lesson.subjectAbbrev
            )
        }
        item.lesson = PlannerLessonReference(lesson: lesson, day: day, scope: scope)
        item.linkedDate = day.date
        return item
    }
}

enum PlannerError: LocalizedError {
    case titleRequired, dateRequired, storageUnavailable, calendarPermission, calendarUnavailable, timetableUnavailable

    var errorDescription: String? {
        switch self {
        case .titleRequired: AppL10n.string("planner.error.titleRequired")
        case .dateRequired: AppL10n.string("planner.error.dateRequired")
        case .storageUnavailable: AppL10n.string("planner.error.storage")
        case .calendarPermission: AppL10n.string("planner.error.calendarPermission")
        case .calendarUnavailable: AppL10n.string("planner.error.calendarUnavailable")
        case .timetableUnavailable: AppL10n.string("planner.error.timetableUnavailable")
        }
    }
}
