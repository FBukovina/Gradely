import Foundation

public enum GradelyWatchMessageType {
    public static let syncPayload = "syncPayload"
    public static let requestSync = "requestSync"
}

public enum GradelyWatchMessageKey {
    public static let messageType = "messageType"
    public static let schemaVersion = "schemaVersion"
    public static let payloadData = "payloadData"
}

public struct GradelyWatchSyncPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let isSignedIn: Bool
    public let auth: GradelyWatchAuth?
    public let user: GradelyWatchUser?
    public let timetable: GradelyWatchTimetable?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date,
        isSignedIn: Bool,
        auth: GradelyWatchAuth?,
        user: GradelyWatchUser?,
        timetable: GradelyWatchTimetable?
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.isSignedIn = isSignedIn
        self.auth = auth
        self.user = user
        self.timetable = timetable
    }

    public static func signedOut(generatedAt: Date = Date()) -> GradelyWatchSyncPayload {
        GradelyWatchSyncPayload(
            generatedAt: generatedAt,
            isSignedIn: false,
            auth: nil,
            user: nil,
            timetable: nil
        )
    }
}

public struct GradelyWatchAuth: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresAt: Date

    public init(
        baseURL: URL,
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        expiresAt: Date
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
    }

    public func expiresSoon(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= now.addingTimeInterval(leeway)
    }
}

public struct GradelyWatchUser: Codable, Equatable, Sendable {
    public let fullName: String
    public let schoolName: String?
    public let classAbbrev: String?

    public init(fullName: String, schoolName: String?, classAbbrev: String?) {
        self.fullName = fullName
        self.schoolName = schoolName
        self.classAbbrev = classAbbrev
    }
}

public struct GradelyWatchTimetable: Codable, Equatable, Sendable {
    public let weekStart: Date
    public let cachedAt: Date
    public let days: [GradelyWatchTimetableDay]

    public init(weekStart: Date, cachedAt: Date, days: [GradelyWatchTimetableDay]) {
        self.weekStart = weekStart
        self.cachedAt = cachedAt
        self.days = days
    }
}

public struct GradelyWatchTimetableDay: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date?
    public let dayStart: Date
    public let weekdayTitle: String
    public let detailTitle: String?
    public let isToday: Bool
    public let isSchoolDay: Bool
    public let lessons: [GradelyWatchTimetableLesson]

    public init(
        id: String,
        date: Date?,
        dayStart: Date,
        weekdayTitle: String,
        detailTitle: String?,
        isToday: Bool,
        isSchoolDay: Bool,
        lessons: [GradelyWatchTimetableLesson]
    ) {
        self.id = id
        self.date = date
        self.dayStart = dayStart
        self.weekdayTitle = weekdayTitle
        self.detailTitle = detailTitle
        self.isToday = isToday
        self.isSchoolDay = isSchoolDay
        self.lessons = lessons
    }
}

public enum GradelyWatchLessonChangeKind: String, Codable, Equatable, Sendable {
    case none
    case canceled
    case substitution
    case roomChanged
    case added

    public var shortTitle: String? {
        switch self {
        case .none: nil
        case .canceled: "Canceled"
        case .substitution: "Changed"
        case .roomChanged: "Room"
        case .added: "Added"
        }
    }
}

public struct GradelyWatchTimetableLesson: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let dayStart: Date
    public let startDate: Date?
    public let endDate: Date?
    public let subjectName: String?
    public let subjectAbbrev: String?
    public let timeRange: String?
    public let room: String?
    public let teacher: String?
    public let changeKind: GradelyWatchLessonChangeKind

    public init(
        id: String,
        dayStart: Date,
        startDate: Date?,
        endDate: Date?,
        subjectName: String?,
        subjectAbbrev: String?,
        timeRange: String?,
        room: String?,
        teacher: String?,
        changeKind: GradelyWatchLessonChangeKind
    ) {
        self.id = id
        self.dayStart = dayStart
        self.startDate = startDate
        self.endDate = endDate
        self.subjectName = subjectName
        self.subjectAbbrev = subjectAbbrev
        self.timeRange = timeRange
        self.room = room
        self.teacher = teacher
        self.changeKind = changeKind
    }

    public var title: String {
        if let subjectAbbrev, !subjectAbbrev.isEmpty {
            return subjectAbbrev
        }
        if let subjectName, !subjectName.isEmpty {
            return subjectName
        }
        return "Lesson"
    }

    public var detailTitle: String {
        subjectName ?? subjectAbbrev ?? "Lesson"
    }

    public var sortDate: Date {
        startDate ?? dayStart
    }

    public var isCanceled: Bool {
        changeKind == .canceled
    }
}

public enum GradelyWatchLessonTiming: String, Codable, Equatable, Sendable {
    case current
    case upcoming
}

public enum GradelyWatchLessonSelection: Equatable, Sendable {
    case lesson(GradelyWatchTimetableLesson, timing: GradelyWatchLessonTiming)
    case noTimetable
    case noLessons
    case stale
}

public enum GradelyWatchSyncCodec {
    public static let staleInterval: TimeInterval = 7 * 24 * 60 * 60

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func envelope(for payload: GradelyWatchSyncPayload) throws -> [String: Any] {
        [
            GradelyWatchMessageKey.messageType: GradelyWatchMessageType.syncPayload,
            GradelyWatchMessageKey.schemaVersion: payload.schemaVersion,
            GradelyWatchMessageKey.payloadData: try encoder.encode(payload)
        ]
    }

    public static func requestSyncEnvelope() -> [String: Any] {
        [
            GradelyWatchMessageKey.messageType: GradelyWatchMessageType.requestSync,
            GradelyWatchMessageKey.schemaVersion: GradelyWatchSyncPayload.currentSchemaVersion
        ]
    }

    public static func payload(from envelope: [String: Any]) throws -> GradelyWatchSyncPayload? {
        guard envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.syncPayload,
              let data = envelope[GradelyWatchMessageKey.payloadData] as? Data
        else {
            return nil
        }

        return try decoder.decode(GradelyWatchSyncPayload.self, from: data)
    }

    public static func isRequestSync(_ envelope: [String: Any]) -> Bool {
        envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.requestSync
    }

    public static func selectLesson(
        from timetable: GradelyWatchTimetable?,
        now: Date = Date(),
        staleInterval: TimeInterval = staleInterval
    ) -> GradelyWatchLessonSelection {
        guard let timetable else {
            return .noTimetable
        }

        if now.timeIntervalSince(timetable.cachedAt) > staleInterval {
            return .stale
        }

        let lessons = timetable.days
            .flatMap(\.lessons)
            .sorted { first, second in
                if first.sortDate == second.sortDate {
                    return first.id < second.id
                }
                return first.sortDate < second.sortDate
            }

        guard !lessons.isEmpty else {
            return .noLessons
        }

        if let current = lessons.first(where: { lesson in
            guard let startDate = lesson.startDate, let endDate = lesson.endDate else {
                return false
            }
            return startDate <= now && now <= endDate
        }) {
            return .lesson(current, timing: .current)
        }

        if let upcoming = lessons.first(where: { lesson in
            guard let startDate = lesson.startDate else {
                return lesson.sortDate >= now
            }
            return startDate > now
        }) {
            return .lesson(upcoming, timing: .upcoming)
        }

        return .noLessons
    }
}

public enum GradelyWatchTimetableDates {
    public static let weekCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func monday(of date: Date) -> Date {
        let components = weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return weekCalendar.date(from: components) ?? date
    }

    public static func apiDateString(_ date: Date) -> String {
        apiFormatter.string(from: date)
    }
}
