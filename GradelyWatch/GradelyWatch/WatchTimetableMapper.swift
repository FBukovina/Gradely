import Foundation
import GradelyWatchShared

struct WatchTimetableResponse: Decodable, Equatable {
    let hours: [WatchTimetableHour]
    let days: [WatchTimetableDayDTO]
    let subjects: [WatchTimetableEntity]
    let teachers: [WatchTimetableEntity]
    let rooms: [WatchTimetableEntity]
    let groups: [WatchTimetableGroup]

    enum CodingKeys: String, CodingKey {
        case hours = "Hours"
        case days = "Days"
        case subjects = "Subjects"
        case teachers = "Teachers"
        case rooms = "Rooms"
        case groups = "Groups"
    }

    init(
        hours: [WatchTimetableHour] = [],
        days: [WatchTimetableDayDTO] = [],
        subjects: [WatchTimetableEntity] = [],
        teachers: [WatchTimetableEntity] = [],
        rooms: [WatchTimetableEntity] = [],
        groups: [WatchTimetableGroup] = []
    ) {
        self.hours = hours
        self.days = days
        self.subjects = subjects
        self.teachers = teachers
        self.rooms = rooms
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = try container.decodeIfPresent([WatchTimetableHour].self, forKey: .hours) ?? []
        days = try container.decodeIfPresent([WatchTimetableDayDTO].self, forKey: .days) ?? []
        subjects = try container.decodeIfPresent([WatchTimetableEntity].self, forKey: .subjects) ?? []
        teachers = try container.decodeIfPresent([WatchTimetableEntity].self, forKey: .teachers) ?? []
        rooms = try container.decodeIfPresent([WatchTimetableEntity].self, forKey: .rooms) ?? []
        groups = try container.decodeIfPresent([WatchTimetableGroup].self, forKey: .groups) ?? []
    }
}

struct WatchTimetableHour: Decodable, Equatable, Hashable {
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
}

struct WatchTimetableDayDTO: Decodable, Equatable {
    let atoms: [WatchTimetableAtom]
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
        atoms: [WatchTimetableAtom] = [],
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
        atoms = try container.decodeIfPresent([WatchTimetableAtom].self, forKey: .atoms) ?? []
        dayOfWeek = try container.decodeIfPresent(Int.self, forKey: .dayOfWeek) ?? 0
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        dayDescription = try container.decodeIfPresent(String.self, forKey: .dayDescription) ?? ""
        dayType = try container.decodeIfPresent(String.self, forKey: .dayType) ?? "WorkDay"
    }
}

struct WatchTimetableAtom: Decodable, Equatable {
    let hourID: Int
    let subjectID: String?
    let teacherID: String?
    let roomID: String?
    let groupIDs: [String]
    let change: WatchTimetableChange?

    enum CodingKeys: String, CodingKey {
        case hourID = "HourId"
        case subjectID = "SubjectId"
        case teacherID = "TeacherId"
        case roomID = "RoomId"
        case groupIDs = "GroupIds"
        case change = "Change"
    }

    init(
        hourID: Int,
        subjectID: String? = nil,
        teacherID: String? = nil,
        roomID: String? = nil,
        groupIDs: [String] = [],
        change: WatchTimetableChange? = nil
    ) {
        self.hourID = hourID
        self.subjectID = subjectID
        self.teacherID = teacherID
        self.roomID = roomID
        self.groupIDs = groupIDs
        self.change = change
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hourID = try container.decodeIfPresent(Int.self, forKey: .hourID) ?? 0
        subjectID = try container.decodeIfPresent(String.self, forKey: .subjectID)
        teacherID = try container.decodeIfPresent(String.self, forKey: .teacherID)
        roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        groupIDs = try container.decodeIfPresent([String].self, forKey: .groupIDs) ?? []
        change = try container.decodeIfPresent(WatchTimetableChange.self, forKey: .change)
    }
}

struct WatchTimetableChange: Decodable, Equatable, Hashable {
    let changeType: String?

    enum CodingKeys: String, CodingKey {
        case changeType = "ChangeType"
    }

    init(changeType: String? = nil) {
        self.changeType = changeType
    }
}

struct WatchTimetableEntity: Decodable, Equatable, Hashable {
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
}

struct WatchTimetableGroup: Decodable, Equatable, Hashable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

enum WatchTimetableMapper {
    static func makeTimetable(
        from response: WatchTimetableResponse,
        weekStart: Date,
        cachedAt: Date,
        today: Date,
        calendar: Calendar = .current
    ) -> GradelyWatchTimetable {
        let subjects = Dictionary(response.subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let teachers = Dictionary(response.teachers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rooms = Dictionary(response.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hoursByID = Dictionary(response.hours.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hourOrder = Dictionary(uniqueKeysWithValues: response.hours.enumerated().map { ($0.element.id, $0.offset) })
        let weekdayFormatter = weekdayFormatter(calendar: calendar)
        let detailFormatter = detailFormatter(calendar: calendar)

        let days = response.days.map { dto in
            let parsedDate = parseDate(dto.date)
            let dayStart = startOfDay(date: parsedDate, dayOfWeek: dto.dayOfWeek, weekStart: weekStart, calendar: calendar)
            let dayID = dto.date.isEmpty ? "dow-\(dto.dayOfWeek)" : dto.date
            let lessons = dto.atoms.enumerated().map { offset, atom in
                let hour = hoursByID[atom.hourID] ?? WatchTimetableHour(id: atom.hourID, caption: "\(atom.hourID)", beginTime: "", endTime: "")
                let subject = atom.subjectID.flatMap { subjects[$0] }
                let teacher = atom.teacherID.flatMap { teachers[$0] }
                let room = atom.roomID.flatMap { rooms[$0] }

                return lesson(
                    id: "\(dayID)#\(atom.hourID)#\(offset)",
                    hour: hour,
                    dayStart: dayStart,
                    subject: subject,
                    teacher: teacher,
                    room: room,
                    change: atom.change,
                    calendar: calendar
                )
            }
            .sorted { (hourOrder[$0.hourID] ?? .max) < (hourOrder[$1.hourID] ?? .max) }
            .map(\.lesson)

            return GradelyWatchTimetableDay(
                id: dayID,
                date: parsedDate,
                dayStart: dayStart,
                weekdayTitle: parsedDate.map { weekdayFormatter.string(from: $0) } ?? fallbackWeekdayTitle(for: dto.dayOfWeek),
                detailTitle: parsedDate.map { detailFormatter.string(from: $0) } ?? emptyToNil(dto.dayDescription),
                isToday: parsedDate.map { calendar.isDate($0, inSameDayAs: today) } ?? false,
                isSchoolDay: dto.dayType == "WorkDay",
                lessons: lessons
            )
        }

        return GradelyWatchTimetable(weekStart: weekStart, cachedAt: cachedAt, days: days)
    }

    private static func lesson(
        id: String,
        hour: WatchTimetableHour,
        dayStart: Date,
        subject: WatchTimetableEntity?,
        teacher: WatchTimetableEntity?,
        room: WatchTimetableEntity?,
        change: WatchTimetableChange?,
        calendar: Calendar
    ) -> (hourID: Int, lesson: GradelyWatchTimetableLesson) {
        let startDate = date(from: hour.beginTime, on: dayStart, calendar: calendar)
        var endDate = date(from: hour.endTime, on: dayStart, calendar: calendar)

        if let startDate, let currentEndDate = endDate, currentEndDate < startDate {
            endDate = calendar.date(byAdding: .day, value: 1, to: currentEndDate)
        }

        return (
            hour.id,
            GradelyWatchTimetableLesson(
                id: id,
                dayStart: dayStart,
                startDate: startDate,
                endDate: endDate,
                subjectName: trimmed(subject?.name),
                subjectAbbrev: trimmed(subject?.abbrev),
                timeRange: timeRange(for: hour),
                room: trimmed(room?.abbrev) ?? trimmed(room?.name),
                teacher: trimmed(teacher?.abbrev) ?? trimmed(teacher?.name),
                changeKind: changeKind(for: change?.changeType)
            )
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func startOfDay(date: Date?, dayOfWeek: Int, weekStart: Date, calendar: Calendar) -> Date {
        if let date {
            return calendar.startOfDay(for: date)
        }

        let dayOffset = max(dayOfWeek - 1, 0)
        let fallbackDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        return calendar.startOfDay(for: fallbackDate)
    }

    private static func date(from time: String, on dayStart: Date, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
    }

    private static func timeRange(for hour: WatchTimetableHour) -> String? {
        let beginTime = hour.beginTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let endTime = hour.endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !beginTime.isEmpty, !endTime.isEmpty else {
            return nil
        }

        return "\(beginTime)-\(endTime)"
    }

    private static func changeKind(for rawValue: String?) -> GradelyWatchLessonChangeKind {
        guard
            let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !raw.isEmpty
        else {
            return .none
        }

        switch raw {
        case "canceled", "cancelled", "removed":
            return .canceled
        case "roomchanged":
            return .roomChanged
        case "added":
            return .added
        default:
            return .substitution
        }
    }

    private static func weekdayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private static func detailFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }

    private static func fallbackWeekdayTitle(for dayOfWeek: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        let symbols = calendar.shortWeekdaySymbols
        let index = dayOfWeek % 7
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
