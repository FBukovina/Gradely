import Foundation

// MARK: - Raw API DTOs
//
// Mirrors the Bakalari `GET api/3/timetable/actual` response, which is *normalized*:
// each Atom references Subjects/Teachers/Rooms/Groups by `Id`. Entity ids can contain
// leading/inner spaces (e.g. " 6", "U  12"), so resolution must match the raw id and only
// trim for display — see `TimetableMapper`.

struct TimetableResponse: Codable, Equatable {
    let hours: [TimetableHour]
    let days: [TimetableDayDTO]
    let classes: [TimetableEntity]
    let groups: [TimetableGroup]
    let subjects: [TimetableEntity]
    let teachers: [TimetableEntity]
    let rooms: [TimetableEntity]
    let cycles: [TimetableEntity]

    enum CodingKeys: String, CodingKey {
        case hours = "Hours"
        case days = "Days"
        case classes = "Classes"
        case groups = "Groups"
        case subjects = "Subjects"
        case teachers = "Teachers"
        case rooms = "Rooms"
        case cycles = "Cycles"
    }

    init(
        hours: [TimetableHour] = [],
        days: [TimetableDayDTO] = [],
        classes: [TimetableEntity] = [],
        groups: [TimetableGroup] = [],
        subjects: [TimetableEntity] = [],
        teachers: [TimetableEntity] = [],
        rooms: [TimetableEntity] = [],
        cycles: [TimetableEntity] = []
    ) {
        self.hours = hours
        self.days = days
        self.classes = classes
        self.groups = groups
        self.subjects = subjects
        self.teachers = teachers
        self.rooms = rooms
        self.cycles = cycles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = try container.decodeIfPresent([TimetableHour].self, forKey: .hours) ?? []
        days = try container.decodeIfPresent([TimetableDayDTO].self, forKey: .days) ?? []
        classes = try container.decodeIfPresent([TimetableEntity].self, forKey: .classes) ?? []
        groups = try container.decodeIfPresent([TimetableGroup].self, forKey: .groups) ?? []
        subjects = try container.decodeIfPresent([TimetableEntity].self, forKey: .subjects) ?? []
        teachers = try container.decodeIfPresent([TimetableEntity].self, forKey: .teachers) ?? []
        rooms = try container.decodeIfPresent([TimetableEntity].self, forKey: .rooms) ?? []
        cycles = try container.decodeIfPresent([TimetableEntity].self, forKey: .cycles) ?? []
    }
}

struct TimetableHour: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let caption: String
    let beginTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case caption = "Caption"
        case beginTime = "BeginTime"
        case endTime = "EndTime"
    }

    init(id: Int, caption: String, beginTime: String, endTime: String) {
        self.id = id
        self.caption = caption
        self.beginTime = beginTime
        self.endTime = endTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        beginTime = try container.decodeIfPresent(String.self, forKey: .beginTime) ?? ""
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime) ?? ""
    }
}

struct TimetableDayDTO: Codable, Equatable {
    let atoms: [TimetableAtom]
    let dayOfWeek: Int
    let date: String
    let dayDescription: String
    let dayType: String

    enum CodingKeys: String, CodingKey {
        case atoms = "Atoms"
        case dayOfWeek = "DayOfWeek"
        case date = "Date"
        case dayDescription = "DayDescription"
        case dayType = "DayType"
    }

    init(
        atoms: [TimetableAtom] = [],
        dayOfWeek: Int,
        date: String,
        dayDescription: String = "",
        dayType: String = "WorkDay"
    ) {
        self.atoms = atoms
        self.dayOfWeek = dayOfWeek
        self.date = date
        self.dayDescription = dayDescription
        self.dayType = dayType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atoms = try container.decodeIfPresent([TimetableAtom].self, forKey: .atoms) ?? []
        dayOfWeek = try container.decodeIfPresent(Int.self, forKey: .dayOfWeek) ?? 0
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        dayDescription = try container.decodeIfPresent(String.self, forKey: .dayDescription) ?? ""
        dayType = try container.decodeIfPresent(String.self, forKey: .dayType) ?? "WorkDay"
    }
}

struct TimetableAtom: Codable, Equatable {
    let hourID: Int
    let groupIDs: [String]
    let subjectID: String?
    let teacherID: String?
    let roomID: String?
    let cycleIDs: [String]
    let change: TimetableChange?
    let homeworkIDs: [String]
    let theme: String?

    enum CodingKeys: String, CodingKey {
        case hourID = "HourId"
        case groupIDs = "GroupIds"
        case subjectID = "SubjectId"
        case teacherID = "TeacherId"
        case roomID = "RoomId"
        case cycleIDs = "CycleIds"
        case change = "Change"
        case homeworkIDs = "HomeworkIds"
        case theme = "Theme"
    }

    init(
        hourID: Int,
        groupIDs: [String] = [],
        subjectID: String? = nil,
        teacherID: String? = nil,
        roomID: String? = nil,
        cycleIDs: [String] = [],
        change: TimetableChange? = nil,
        homeworkIDs: [String] = [],
        theme: String? = nil
    ) {
        self.hourID = hourID
        self.groupIDs = groupIDs
        self.subjectID = subjectID
        self.teacherID = teacherID
        self.roomID = roomID
        self.cycleIDs = cycleIDs
        self.change = change
        self.homeworkIDs = homeworkIDs
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hourID = try container.decodeIfPresent(Int.self, forKey: .hourID) ?? 0
        groupIDs = try container.decodeIfPresent([String].self, forKey: .groupIDs) ?? []
        subjectID = try container.decodeIfPresent(String.self, forKey: .subjectID)
        teacherID = try container.decodeIfPresent(String.self, forKey: .teacherID)
        roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        cycleIDs = try container.decodeIfPresent([String].self, forKey: .cycleIDs) ?? []
        change = try container.decodeIfPresent(TimetableChange.self, forKey: .change)
        homeworkIDs = try container.decodeIfPresent([String].self, forKey: .homeworkIDs) ?? []
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
    }
}

struct TimetableChange: Codable, Equatable, Hashable {
    let changeSubject: String?
    let day: String?
    let hours: String?
    let changeType: String?
    let description: String?
    let time: String?
    let typeAbbrev: String?
    let typeName: String?

    enum CodingKeys: String, CodingKey {
        case changeSubject = "ChangeSubject"
        case day = "Day"
        case hours = "Hours"
        case changeType = "ChangeType"
        case description = "Description"
        case time = "Time"
        case typeAbbrev = "TypeAbbrev"
        case typeName = "TypeName"
    }

    init(
        changeSubject: String? = nil,
        day: String? = nil,
        hours: String? = nil,
        changeType: String? = nil,
        description: String? = nil,
        time: String? = nil,
        typeAbbrev: String? = nil,
        typeName: String? = nil
    ) {
        self.changeSubject = changeSubject
        self.day = day
        self.hours = hours
        self.changeType = changeType
        self.description = description
        self.time = time
        self.typeAbbrev = typeAbbrev
        self.typeName = typeName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changeSubject = try container.decodeIfPresent(String.self, forKey: .changeSubject)
        day = try container.decodeIfPresent(String.self, forKey: .day)
        hours = try container.decodeIfPresent(String.self, forKey: .hours)
        changeType = try container.decodeIfPresent(String.self, forKey: .changeType)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        typeAbbrev = try container.decodeIfPresent(String.self, forKey: .typeAbbrev)
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
    }
}

/// Shared shape for Classes / Subjects / Teachers / Rooms / Cycles.
struct TimetableEntity: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }

    init(id: String, abbrev: String, name: String) {
        self.id = id
        self.abbrev = abbrev
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        abbrev = try container.decodeIfPresent(String.self, forKey: .abbrev) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

struct TimetableGroup: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let abbrev: String
    let name: String
    let classID: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
        case classID = "ClassId"
    }

    init(id: String, abbrev: String, name: String, classID: String? = nil) {
        self.id = id
        self.abbrev = abbrev
        self.name = name
        self.classID = classID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        abbrev = try container.decodeIfPresent(String.self, forKey: .abbrev) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        classID = try container.decodeIfPresent(String.self, forKey: .classID)
    }
}

// MARK: - Display models
//
// Denormalized, view-ready representation produced by `TimetableMapper`.

enum DayType: Equatable {
    case workDay
    case weekend
    case celebration
    case holiday
    case directorDay
    case undefined

    init(apiValue: String) {
        switch apiValue {
        case "WorkDay": self = .workDay
        case "Weekend": self = .weekend
        case "Celebration": self = .celebration
        case "Holiday": self = .holiday
        case "DirectorDay": self = .directorDay
        default: self = .undefined
        }
    }

    /// Whether lessons are normally expected (used to pick the right empty-state copy).
    var isSchoolDay: Bool { self == .workDay }
}

enum LessonChangeKind: Equatable {
    case none
    case canceled
    case substitution
    case roomChanged
    case added

    init(changeType: String?) {
        guard
            let raw = changeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !raw.isEmpty
        else {
            self = .none
            return
        }

        switch raw {
        case "canceled", "cancelled", "removed":
            self = .canceled
        case "roomchanged":
            self = .roomChanged
        case "added":
            self = .added
        default:
            // "Substitution" and any unknown change type are surfaced as a generic change.
            self = .substitution
        }
    }

    var isCanceled: Bool { self == .canceled }

    /// Short localized label for the change chip; `nil` when there is no change.
    var localizedLabel: String? {
        switch self {
        case .none: nil
        case .canceled: AppL10n.string("timetable.change.canceled")
        case .substitution: AppL10n.string("timetable.change.substitution")
        case .roomChanged: AppL10n.string("timetable.change.roomChange")
        case .added: AppL10n.string("timetable.change.added")
        }
    }
}

/// A single resolved lesson in a day (one atom with its entities looked up).
struct ScheduledLesson: Identifiable, Equatable {
    let id: String
    let hour: TimetableHour
    let subjectName: String?
    let subjectAbbrev: String?
    let teacherName: String?
    let teacherAbbrev: String?
    let roomAbbrev: String?
    let roomName: String?
    let groups: [String]
    let theme: String?
    let hasHomework: Bool
    let change: TimetableChange?
    let changeKind: LessonChangeKind

    var isCanceled: Bool { changeKind.isCanceled }

    /// Short title for the card — subject abbreviation, falling back to the full name.
    var title: String {
        if let subjectAbbrev, !subjectAbbrev.isEmpty { return subjectAbbrev }
        if let subjectName, !subjectName.isEmpty { return subjectName }
        return ""
    }
}

/// One day in the week strip.
struct ScheduledDay: Identifiable, Equatable {
    let id: String
    let date: Date?
    let dayOfWeek: Int
    let dayType: DayType
    let dayDescription: String
    let lessons: [ScheduledLesson]
    let isToday: Bool

    var hasLessons: Bool { !lessons.isEmpty }
    var hasChanges: Bool { lessons.contains { $0.changeKind != .none } }
}

/// A full week, ready to render.
struct TimetableWeek: Equatable {
    let weekStart: Date
    let days: [ScheduledDay]
    let hours: [TimetableHour]
}
