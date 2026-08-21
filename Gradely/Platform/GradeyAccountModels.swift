import Foundation

struct GradeyAccount: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var email: String?
    var fullName: String?
    var avatarURL: URL?
    var createdAt: Date

    var displayName: String {
        if let fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return fullName
        }
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return AppL10n.string("gradey.auth.title")
    }
}

struct GradeyAuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expiresAt: Date?
    var account: GradeyAccount

    var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }
}

enum LinkedAccountProvider: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case bakalari
    case eduPage
    case stravaCZ

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bakalari: "Bakaláři"
        case .eduPage: "EduPage"
        case .stravaCZ: "StravaCZ"
        }
    }

    var isSchoolProvider: Bool {
        switch self {
        case .bakalari, .eduPage: true
        case .stravaCZ: false
        }
    }

    init(schoolProvider: SchoolProvider) {
        switch schoolProvider {
        case .bakalari: self = .bakalari
        case .eduPage: self = .eduPage
        }
    }
}

enum LinkedAccountStatus: String, Codable, Equatable, Sendable {
    case active
    case actionRequired = "action_required"
    case paused
    case linking
    case failed

    var displayName: String {
        switch self {
        case .active: AppL10n.string("gradey.account.status.active")
        case .actionRequired: AppL10n.string("gradey.account.status.actionRequired")
        case .paused: AppL10n.string("gradey.account.status.paused")
        case .linking: AppL10n.string("gradey.account.status.linking")
        case .failed: AppL10n.string("gradey.account.status.failed")
        }
    }
}

struct LinkedAccount: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var provider: LinkedAccountProvider
    var providerUserID: String?
    var displayName: String
    var schoolName: String?
    var canteenName: String?
    var status: LinkedAccountStatus
    var notificationsEnabled: Bool
    var lastPolledAt: Date?
    var lastSyncedAt: Date?
    var actionRequiredReason: String?

    var subtitle: String {
        if let schoolName, !schoolName.isEmpty {
            return schoolName
        }
        if let canteenName, !canteenName.isEmpty {
            return canteenName
        }
        return provider.displayName
    }
}

struct DevicePushToken: Codable, Equatable, Identifiable, Sendable {
    var id: String { tokenHash }
    let platform: String
    let environment: String
    let tokenHash: String
    let registeredAt: Date
    let lastSeenAt: Date
}

enum NotificationLockScreenDetail: String, Codable, CaseIterable, Equatable, Sendable {
    case privateSummary = "private_summary"
    case markAndSubject = "mark_and_subject"
    case fullDetails = "full_details"
}

struct NotificationPreferences: Codable, Equatable, Sendable {
    static let legacyTimeZoneIdentifier = "Europe/Prague"

    var newMarksEnabled: Bool
    var lockScreenDetail: NotificationLockScreenDetail
    var quietHoursEnabled: Bool
    var quietHoursStartMinute: Int
    var quietHoursEndMinute: Int
    var quietHoursTimeZoneIdentifier: String

    init(
        newMarksEnabled: Bool,
        lockScreenDetail: NotificationLockScreenDetail,
        quietHoursEnabled: Bool,
        quietHoursStartMinute: Int,
        quietHoursEndMinute: Int,
        quietHoursTimeZoneIdentifier: String = NotificationPreferences.legacyTimeZoneIdentifier
    ) {
        self.newMarksEnabled = newMarksEnabled
        self.lockScreenDetail = lockScreenDetail
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinute = Self.validMinuteOrDefault(quietHoursStartMinute, fallback: 22 * 60)
        self.quietHoursEndMinute = Self.validMinuteOrDefault(quietHoursEndMinute, fallback: 6 * 60)
        self.quietHoursTimeZoneIdentifier = Self.validTimeZoneIdentifierOrDefault(quietHoursTimeZoneIdentifier)
    }

    static let `default` = NotificationPreferences(
        newMarksEnabled: true,
        lockScreenDetail: .markAndSubject,
        quietHoursEnabled: false,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 6 * 60,
        quietHoursTimeZoneIdentifier: legacyTimeZoneIdentifier
    )

    var quietHoursTimeZone: TimeZone {
        TimeZone(identifier: quietHoursTimeZoneIdentifier)
            ?? TimeZone(identifier: Self.legacyTimeZoneIdentifier)
            ?? .current
    }

    func preparedForServerUpdate(timeZone: TimeZone = .current) -> NotificationPreferences {
        var prepared = self
        prepared.quietHoursStartMinute = Self.validMinuteOrDefault(
            quietHoursStartMinute,
            fallback: Self.default.quietHoursStartMinute
        )
        prepared.quietHoursEndMinute = Self.validMinuteOrDefault(
            quietHoursEndMinute,
            fallback: Self.default.quietHoursEndMinute
        )
        prepared.quietHoursTimeZoneIdentifier = Self.validTimeZoneIdentifierOrDefault(timeZone.identifier)
        return prepared
    }

    func containsQuietMinute(_ minute: Int) -> Bool {
        guard quietHoursEnabled, (0..<Self.minutesPerDay).contains(minute) else { return false }
        if quietHoursStartMinute == quietHoursEndMinute {
            return true
        }
        if quietHoursStartMinute < quietHoursEndMinute {
            return minute >= quietHoursStartMinute && minute < quietHoursEndMinute
        }
        return minute >= quietHoursStartMinute || minute < quietHoursEndMinute
    }

    func isWithinQuietHours(at date: Date) -> Bool {
        containsQuietMinute(Self.minuteOfDay(from: date, in: quietHoursTimeZone))
    }

    func nextQuietHoursEnd(after date: Date) -> Date? {
        guard isWithinQuietHours(at: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = quietHoursTimeZone
        let components = DateComponents(
            hour: quietHoursEndMinute / 60,
            minute: quietHoursEndMinute % 60
        )
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .last,
            direction: .forward
        )
    }

    static func minuteOfDay(from date: Date, in timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(
        forMinuteOfDay minute: Int,
        on day: Date = Date(),
        in timeZone: TimeZone = .current
    ) -> Date {
        let validMinute = validMinuteOrDefault(minute, fallback: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            bySettingHour: validMinute / 60,
            minute: validMinute % 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? day
    }

    private static let minutesPerDay = 24 * 60

    private enum CodingKeys: String, CodingKey {
        case newMarksEnabled = "new_marks_enabled"
        case lockScreenDetail = "lock_screen_detail"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStartMinute = "quiet_hours_start_minute"
        case quietHoursEndMinute = "quiet_hours_end_minute"
        case quietHoursTimeZoneIdentifier = "quiet_hours_time_zone"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case newMarksEnabled
        case lockScreenDetail
        case quietHoursEnabled
        case quietHoursStartMinute
        case quietHoursEndMinute
        case quietHoursTimeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let defaults = Self.default

        newMarksEnabled = try values.decodeIfPresent(Bool.self, forKey: .newMarksEnabled)
            ?? legacyValues.decodeIfPresent(Bool.self, forKey: .newMarksEnabled)
            ?? defaults.newMarksEnabled
        lockScreenDetail = try values.decodeIfPresent(NotificationLockScreenDetail.self, forKey: .lockScreenDetail)
            ?? legacyValues.decodeIfPresent(NotificationLockScreenDetail.self, forKey: .lockScreenDetail)
            ?? defaults.lockScreenDetail
        quietHoursEnabled = try values.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled)
            ?? legacyValues.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled)
            ?? defaults.quietHoursEnabled
        quietHoursStartMinute = Self.validMinuteOrDefault(
            try values.decodeIfPresent(Int.self, forKey: .quietHoursStartMinute)
                ?? legacyValues.decodeIfPresent(Int.self, forKey: .quietHoursStartMinute),
            fallback: defaults.quietHoursStartMinute
        )
        quietHoursEndMinute = Self.validMinuteOrDefault(
            try values.decodeIfPresent(Int.self, forKey: .quietHoursEndMinute)
                ?? legacyValues.decodeIfPresent(Int.self, forKey: .quietHoursEndMinute),
            fallback: defaults.quietHoursEndMinute
        )
        quietHoursTimeZoneIdentifier = Self.validTimeZoneIdentifierOrDefault(
            try values.decodeIfPresent(String.self, forKey: .quietHoursTimeZoneIdentifier)
                ?? legacyValues.decodeIfPresent(String.self, forKey: .quietHoursTimeZoneIdentifier)
                ?? Self.legacyTimeZoneIdentifier
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(newMarksEnabled, forKey: .newMarksEnabled)
        try values.encode(lockScreenDetail, forKey: .lockScreenDetail)
        try values.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try values.encode(quietHoursStartMinute, forKey: .quietHoursStartMinute)
        try values.encode(quietHoursEndMinute, forKey: .quietHoursEndMinute)
        try values.encode(quietHoursTimeZoneIdentifier, forKey: .quietHoursTimeZoneIdentifier)
    }

    private static func validMinuteOrDefault(_ minute: Int?, fallback: Int) -> Int {
        guard let minute, (0..<minutesPerDay).contains(minute) else { return fallback }
        return minute
    }

    private static func validTimeZoneIdentifierOrDefault(_ identifier: String) -> String {
        TimeZone(identifier: identifier) == nil ? legacyTimeZoneIdentifier : identifier
    }
}

struct GradeyAccountSettingsSnapshot: Decodable, Equatable, Sendable {
    let activeSchoolAccountID: String?
    let linkedAccounts: [LinkedAccount]
    let notificationPreferences: NotificationPreferences

    enum CodingKeys: String, CodingKey {
        case activeSchoolAccountID = "active_school_account_id"
        case linkedAccounts = "linked_accounts"
        case notificationPreferences = "notification_preferences"
    }
}

extension JSONDecoder {
    static var gradeyAPIDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }
}

struct MarkFingerprint: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case providerID = "provider_id"
        case contentHash = "content_hash"
    }

    var id: String { value }
    let provider: LinkedAccountProvider
    let linkedAccountID: String
    let subjectID: String
    let providerMarkID: String?
    let value: String
    let source: Source
}

struct NewMarkEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let linkedAccountID: String
    let provider: LinkedAccountProvider
    let subjectID: String
    let subjectAbbrev: String?
    let subjectName: String?
    let markText: String
    let fingerprint: MarkFingerprint
    let createdAt: Date
    let deliveredAt: Date?

    init(
        id: String,
        linkedAccountID: String,
        provider: LinkedAccountProvider,
        subjectID: String,
        subjectAbbrev: String?,
        subjectName: String?,
        markText: String,
        fingerprint: MarkFingerprint,
        createdAt: Date,
        deliveredAt: Date?
    ) {
        self.id = id
        self.linkedAccountID = linkedAccountID
        self.provider = provider
        self.subjectID = subjectID
        self.subjectAbbrev = subjectAbbrev
        self.subjectName = subjectName
        self.markText = markText
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case linkedAccountID = "linked_account_id"
        case provider
        case subjectID = "subject_id"
        case subjectAbbrev = "subject_abbrev"
        case subjectName = "subject_name"
        case markText = "mark_text"
        case fingerprint
        case createdAt = "created_at"
        case deliveredAt = "delivered_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        linkedAccountID = try container.decode(String.self, forKey: .linkedAccountID)
        provider = try container.decode(LinkedAccountProvider.self, forKey: .provider)
        subjectID = try container.decode(String.self, forKey: .subjectID)
        subjectAbbrev = try container.decodeIfPresent(String.self, forKey: .subjectAbbrev)
        subjectName = try container.decodeIfPresent(String.self, forKey: .subjectName)
        markText = try container.decode(String.self, forKey: .markText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        deliveredAt = try container.decodeIfPresent(Date.self, forKey: .deliveredAt)
        fingerprint = (try? container.decode(MarkFingerprint.self, forKey: .fingerprint)) ?? MarkFingerprint(
            provider: provider,
            linkedAccountID: linkedAccountID,
            subjectID: subjectID,
            providerMarkID: nil,
            value: id,
            source: .contentHash
        )
    }
}

struct LinkedSchoolAccountActivation: Codable, Equatable, Sendable {
    let account: LinkedAccount
    let tokenPayload: ProviderSecretSanitizer.SchoolPayload

    enum CodingKeys: String, CodingKey {
        case account
        case tokenPayload = "token_payload"
    }

    func makeStoredSession() -> StoredSession {
        let provider: SchoolProvider = tokenPayload.provider == .eduPage ? .eduPage : .bakalari
        let eduPage = tokenPayload.eduPage.map { payload in
            EduPageSessionData(
                sessionID: payload.sessionID,
                username: payload.username,
                password: "",
                gsecHash: payload.gsecHash,
                userID: payload.userID,
                schoolName: account.schoolName,
                activeStudent: payload.activeStudent,
                linkedStudents: payload.linkedStudents,
                subjects: payload.subjects
            )
        }

        return StoredSession(
            accessToken: tokenPayload.accessToken,
            refreshToken: tokenPayload.refreshToken ?? "",
            tokenType: tokenPayload.tokenType,
            expiresAt: tokenPayload.expiresAt ?? .distantFuture,
            baseURL: tokenPayload.baseURL,
            provider: provider,
            eduPage: eduPage,
            bakalari: tokenPayload.bakalari,
            linkedAccountID: account.id,
            linkedAccountDisplayName: account.displayName,
            linkedAccountSchoolName: account.schoolName
        )
    }
}

enum GradeHistoryEventType: String, Codable, Equatable, Sendable {
    case baseline
    case changed
}

struct GradeHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let linkedAccountID: String
    let provider: LinkedAccountProvider
    let subjectID: String
    let subjectAbbrev: String?
    let subjectName: String?
    let averageValue: Double?
    let markCount: Int
    let averageDelta: Double?
    let markCountDelta: Int
    let eventType: GradeHistoryEventType
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case linkedAccountID = "linked_account_id"
        case provider
        case subjectID = "subject_id"
        case subjectAbbrev = "subject_abbrev"
        case subjectName = "subject_name"
        case averageValue = "average_value"
        case markCount = "mark_count"
        case averageDelta = "average_delta"
        case markCountDelta = "mark_count_delta"
        case eventType = "event_type"
        case capturedAt = "captured_at"
    }
}

struct SubjectGradeTrend: Codable, Equatable, Identifiable, Sendable {
    let subjectID: String
    let subjectAbbrev: String?
    let subjectName: String?
    let firstAverage: Double?
    let latestAverage: Double?
    let averageDelta: Double?
    let firstMarkCount: Int
    let latestMarkCount: Int
    let events: [GradeHistoryEvent]

    var id: String { subjectID }

    var displayName: String {
        if let subjectAbbrev, !subjectAbbrev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjectAbbrev
        }
        if let subjectName, !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjectName
        }
        return subjectID
    }

    var isImproving: Bool {
        (averageDelta ?? 0) < 0
    }

    var isWorsening: Bool {
        (averageDelta ?? 0) > 0
    }

    enum CodingKeys: String, CodingKey {
        case subjectID
        case subjectAbbrev
        case subjectName
        case firstAverage
        case latestAverage
        case averageDelta
        case firstMarkCount
        case latestMarkCount
        case events
    }

    static func make(from events: [GradeHistoryEvent]) -> [SubjectGradeTrend] {
        Dictionary(grouping: events, by: \.subjectID)
            .map { subjectID, subjectEvents in
                let sorted = subjectEvents.sorted { $0.capturedAt < $1.capturedAt }
                let first = sorted.first
                let latest = sorted.last
                let delta: Double?
                if let firstAverage = first?.averageValue, let latestAverage = latest?.averageValue {
                    delta = latestAverage - firstAverage
                } else {
                    delta = latest?.averageDelta
                }
                return SubjectGradeTrend(
                    subjectID: subjectID,
                    subjectAbbrev: latest?.subjectAbbrev ?? first?.subjectAbbrev,
                    subjectName: latest?.subjectName ?? first?.subjectName,
                    firstAverage: first?.averageValue,
                    latestAverage: latest?.averageValue,
                    averageDelta: delta,
                    firstMarkCount: first?.markCount ?? 0,
                    latestMarkCount: latest?.markCount ?? 0,
                    events: sorted
                )
            }
            .sorted { first, second in
                abs(first.averageDelta ?? 0) > abs(second.averageDelta ?? 0)
            }
    }
}

struct GradeHistoryResponse: Codable, Equatable, Sendable {
    let events: [GradeHistoryEvent]
    let recentNewMarkEvents: [NewMarkEvent]

    var trends: [SubjectGradeTrend] {
        SubjectGradeTrend.make(from: events)
    }

    init(events: [GradeHistoryEvent], recentNewMarkEvents: [NewMarkEvent]) {
        self.events = events
        self.recentNewMarkEvents = recentNewMarkEvents
    }

    enum CodingKeys: String, CodingKey {
        case events
        case recentNewMarkEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([GradeHistoryEvent].self, forKey: .events) ?? []
        recentNewMarkEvents = (try? container.decodeIfPresent([NewMarkEvent].self, forKey: .recentNewMarkEvents)) ?? []
    }
}
