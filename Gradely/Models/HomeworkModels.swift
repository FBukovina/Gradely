import CryptoKit
import Foundation

// MARK: - Bakaláři payload

/// `GET api/3/homeworks`: every homework assigned or due inside `from`…`to`.
struct HomeworkResponse: Codable, Equatable {
    var homeworks: [HomeworkDTO]

    enum CodingKeys: String, CodingKey {
        case homeworks = "Homeworks"
    }

    init(homeworks: [HomeworkDTO]) {
        self.homeworks = homeworks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeworks = try container.decodeIfPresent([HomeworkDTO].self, forKey: .homeworks) ?? []
    }
}

struct HomeworkDTO: Codable, Equatable {
    let id: String
    let dateStart: String?
    let dateEnd: String?
    let content: String
    let notice: String?
    /// Ticked off by the student. `Closed` is the teacher's side.
    var done: Bool
    let closed: Bool
    let electronic: Bool
    let hour: Int?
    let subject: HomeworkEntity?
    let teacher: HomeworkEntity?
    let attachments: [HomeworkAttachmentDTO]

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case dateStart = "DateStart"
        case dateEnd = "DateEnd"
        case content = "Content"
        case notice = "Notice"
        case done = "Done"
        case closed = "Closed"
        case electronic = "Electronic"
        case hour = "Hour"
        case subject = "Subject"
        case teacher = "Teacher"
        case attachments = "Attachments"
    }

    init(
        id: String,
        dateStart: String?,
        dateEnd: String?,
        content: String,
        notice: String? = nil,
        done: Bool = false,
        closed: Bool = false,
        electronic: Bool = false,
        hour: Int? = nil,
        subject: HomeworkEntity? = nil,
        teacher: HomeworkEntity? = nil,
        attachments: [HomeworkAttachmentDTO] = []
    ) {
        self.id = id
        self.dateStart = dateStart
        self.dateEnd = dateEnd
        self.content = content
        self.notice = notice
        self.done = done
        self.closed = closed
        self.electronic = electronic
        self.hour = hour
        self.subject = subject
        self.teacher = teacher
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dateStart = try container.decodeIfPresent(String.self, forKey: .dateStart)
        dateEnd = try container.decodeIfPresent(String.self, forKey: .dateEnd)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        notice = try container.decodeIfPresent(String.self, forKey: .notice)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        closed = try container.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        electronic = try container.decodeIfPresent(Bool.self, forKey: .electronic) ?? false
        hour = try container.decodeIfPresent(Int.self, forKey: .hour)
        subject = try container.decodeIfPresent(HomeworkEntity.self, forKey: .subject)
        teacher = try container.decodeIfPresent(HomeworkEntity.self, forKey: .teacher)
        attachments = try container.decodeIfPresent([HomeworkAttachmentDTO].self, forKey: .attachments) ?? []
    }
}

struct HomeworkEntity: Codable, Equatable {
    let id: String?
    let abbrev: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct HomeworkAttachmentDTO: Codable, Equatable {
    let id: String
    let name: String?
    let type: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case size = "Size"
    }
}

struct CachedHomework: Equatable {
    let response: HomeworkResponse
    let cachedAt: Date
}

// MARK: - App model

/// A homework from the school, read-only apart from the student's done tick.
struct Homework: Identifiable, Equatable, Sendable {
    let id: String
    let subjectID: String?
    let subjectName: String?
    let subjectAbbrev: String?
    let teacherName: String?
    let content: String
    let notice: String?
    /// Civil days in the school's time zone; Bakaláři sends them as midnight.
    let assignedOn: Date?
    let dueOn: Date?
    var isDone: Bool
    let isClosed: Bool
    let isElectronic: Bool
    let attachments: [HomeworkAttachment]

    /// Bakaláři dates are school days, so they are read and shown in Prague time.
    static let timeZone = TimeZone(identifier: "Europe/Prague") ?? .current

    static var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    init(_ dto: HomeworkDTO) {
        id = dto.id
        subjectID = Self.trimmed(dto.subject?.id)
        subjectName = Self.trimmed(dto.subject?.name)
        subjectAbbrev = Self.trimmed(dto.subject?.abbrev)
        teacherName = Self.trimmed(dto.teacher?.name)
        content = dto.content.trimmingCharacters(in: .whitespacesAndNewlines)
        notice = Self.trimmed(dto.notice)
        assignedOn = Self.schoolDate(dto.dateStart)
        dueOn = Self.schoolDate(dto.dateEnd)
        isDone = dto.done
        isClosed = dto.closed
        isElectronic = dto.electronic
        attachments = dto.attachments.map {
            HomeworkAttachment(id: $0.id, name: Self.trimmed($0.name) ?? $0.id, size: $0.size.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    /// The first line, for rows and reminders; the detail shows all of it.
    var title: String {
        let firstLine = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? (subjectName ?? AppL10n.string("homework.school")) : firstLine
    }

    var subjectLabel: String? { subjectName ?? subjectAbbrev }

    /// Still to do: not ticked off and not closed by the teacher.
    var isOpen: Bool { !isDone && !isClosed }

    /// The due day at local midnight, so it groups with Planner days.
    func dueDay(in calendar: Calendar = .current) -> Date? {
        dueOn.flatMap { Self.localDay($0, in: calendar) }
    }

    func assignedDay(in calendar: Calendar = .current) -> Date? {
        assignedOn.flatMap { Self.localDay($0, in: calendar) }
    }

    /// Planner and reminder identity: stable per account, never a provider payload.
    func eventID(scope: SchoolDataScope) -> UUID {
        let digest = Array(SHA256.hash(data: Data("homework\u{1F}\(scope.rawValue)\u{1F}\(id)".utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func event(scope: SchoolDataScope) -> SchoolEvent? {
        guard let dueOn else { return nil }
        return SchoolEvent(
            id: eventID(scope: scope), scope: scope, subjectID: subjectID, subjectName: subjectLabel,
            title: title, kind: .homework, date: dueOn, hasTime: false,
            timeZoneIdentifier: Self.timeZone.identifier, updatedAt: assignedOn ?? dueOn
        )
    }

    /// "2020-11-10T00:00:00+01:00", with or without fractions, or a bare day.
    private static func schoolDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = timeZone
        return formatter.date(from: String(value.prefix(10)))
    }

    private static func localDay(_ date: Date, in calendar: Calendar) -> Date? {
        let parts = schoolCalendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

struct HomeworkAttachment: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let size: Int?
}
