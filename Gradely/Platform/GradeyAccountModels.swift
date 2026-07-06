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
        return String(localized: "gradey.auth.title")
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
        case .active: String(localized: "gradey.account.status.active")
        case .actionRequired: String(localized: "gradey.account.status.actionRequired")
        case .paused: String(localized: "gradey.account.status.paused")
        case .linking: String(localized: "gradey.account.status.linking")
        case .failed: String(localized: "gradey.account.status.failed")
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
    var newMarksEnabled: Bool
    var lockScreenDetail: NotificationLockScreenDetail
    var quietHoursEnabled: Bool
    var quietHoursStartMinute: Int
    var quietHoursEndMinute: Int

    static let `default` = NotificationPreferences(
        newMarksEnabled: true,
        lockScreenDetail: .markAndSubject,
        quietHoursEnabled: false,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 6 * 60
    )
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
            bakalari: nil,
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
