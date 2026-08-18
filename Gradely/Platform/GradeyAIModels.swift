import Foundation

struct GradeyAIStatus: Codable, Equatable, Sendable {
    var enabled: Bool
    var consentRequired: Bool
    var termsVersion: String
    var dailyLimit: Int
    var dailyUsed: Int
    var remaining: Int
    var resetAt: Date?
    var tier: GradeyAIIdentityTier? = nil

    var canSend: Bool {
        enabled && !consentRequired && remaining > 0
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case consentRequired = "consent_required"
        case termsVersion = "terms_version"
        case dailyLimit = "daily_limit"
        case dailyUsed = "daily_used"
        case remaining
        case resetAt = "reset_at"
        case tier
    }
}

enum GradeyAIIdentityTier: String, Codable, Equatable, Sendable {
    case anonymous
    case linked
}

struct GradeyAIConsent: Codable, Equatable, Sendable {
    let consented: Bool
    let termsVersion: String?

    enum CodingKeys: String, CodingKey {
        case consented
        case termsVersion = "terms_version"
    }
}

struct GradeyAIConversation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let schoolScope: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolScope
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
    }
}

enum GradeyAIMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

enum GradeyAIMessageStatus: String, Codable, Equatable, Sendable {
    case streaming
    case complete
    case cancelled
    case failed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "streaming", "pending": self = .streaming
        case "complete", "completed": self = .complete
        case "cancelled", "canceled": self = .cancelled
        case "failed": self = .failed
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Gradey AI message status: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GradeyAIMessage: Codable, Equatable, Identifiable, Sendable {
    var id: String
    let conversationID: String
    let clientMessageID: String?
    let role: GradeyAIMessageRole
    var content: String
    var status: GradeyAIMessageStatus
    let createdAt: Date
    let contextGeneratedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case clientMessageID = "client_message_id"
        case role
        case content
        case status
        case createdAt = "created_at"
        case contextGeneratedAt = "context_generated_at"
    }
}

enum GradeyAIContextSection: String, Codable, Equatable, Sendable {
    case marks
    case trends
    case timetable
}

struct GradeyAIMarkContext: Codable, Equatable, Sendable {
    let value: String
    let date: String
    let weight: Double?
    let title: String?
    let isPoints: Bool
    let pointsText: String?
    let maxPoints: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case date
        case weight
        case title
        case isPoints = "is_points"
        case pointsText = "points_text"
        case maxPoints = "max_points"
    }
}

struct GradeyAISubjectContext: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let abbreviation: String?
    let average: Double?
    let pointsOnly: Bool
    let totalMarkCount: Int
    let recentMarks: [GradeyAIMarkContext]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case abbreviation
        case average
        case pointsOnly = "points_only"
        case totalMarkCount = "total_mark_count"
        case recentMarks = "recent_marks"
    }
}

struct GradeyAITrendContext: Codable, Equatable, Identifiable, Sendable {
    let subjectID: String
    let subjectName: String
    let subjectAbbreviation: String?
    let firstAverage: Double?
    let latestAverage: Double?
    let averageDelta: Double?
    let firstMarkCount: Int
    let latestMarkCount: Int

    var id: String { subjectID }

    enum CodingKeys: String, CodingKey {
        case subjectID = "subject_id"
        case subjectName = "subject_name"
        case subjectAbbreviation = "subject_abbreviation"
        case firstAverage = "first_average"
        case latestAverage = "latest_average"
        case averageDelta = "average_delta"
        case firstMarkCount = "first_mark_count"
        case latestMarkCount = "latest_mark_count"
    }
}

enum GradeyAILessonChangeKind: String, Codable, Equatable, Sendable {
    case none
    case cancelled
    case substitution
    case roomChanged = "room_changed"
    case added
}

struct GradeyAILessonContext: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: String
    let subject: String
    let subjectAbbreviation: String?
    let beginsAt: String
    let endsAt: String
    let teacher: String?
    let room: String?
    let groups: [String]
    let changeKind: GradeyAILessonChangeKind
    let changeDescription: String?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case subject
        case subjectAbbreviation = "subject_abbreviation"
        case beginsAt = "begins_at"
        case endsAt = "ends_at"
        case teacher
        case room
        case groups
        case changeKind = "change_kind"
        case changeDescription = "change_description"
    }
}

struct GradeyAIContextSnapshot: Codable, Equatable, Sendable {
    let schoolScope: String
    let generatedAt: Date
    let isStale: Bool
    let unavailableSections: [GradeyAIContextSection]
    let subjects: [GradeyAISubjectContext]
    let trends: [GradeyAITrendContext]
    let timetable: [GradeyAILessonContext]

    var isPartial: Bool {
        !unavailableSections.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case schoolScope
        case generatedAt = "generated_at"
        case isStale = "is_stale"
        case unavailableSections = "unavailable_sections"
        case subjects
        case trends
        case timetable
    }
}

enum GradeyAIStreamEvent: Codable, Equatable, Sendable {
    case start(assistantMessageID: String, remaining: Int)
    case delta(text: String)
    case done(
        finishReason: String?,
        remaining: Int,
        inputTokens: Int?,
        outputTokens: Int?,
        persistedMessage: GradeyAIMessage?
    )
    case error(code: String, message: String, retryable: Bool, remaining: Int?)

    private enum CodingKeys: String, CodingKey {
        case type
        case assistantMessageID = "assistant_message_id"
        case remaining
        case text
        case finishReason = "finish_reason"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case persistedMessage = "persisted_message"
        case code
        case message
        case retryable
    }

    private enum EventType: String, Codable {
        case start
        case delta
        case done
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .start:
            self = .start(
                assistantMessageID: try container.decode(String.self, forKey: .assistantMessageID),
                remaining: try container.decode(Int.self, forKey: .remaining)
            )
        case .delta:
            self = .delta(text: try container.decode(String.self, forKey: .text))
        case .done:
            self = .done(
                finishReason: try container.decodeIfPresent(String.self, forKey: .finishReason),
                remaining: try container.decode(Int.self, forKey: .remaining),
                inputTokens: try container.decodeIfPresent(Int.self, forKey: .inputTokens),
                outputTokens: try container.decodeIfPresent(Int.self, forKey: .outputTokens),
                persistedMessage: try container.decodeIfPresent(GradeyAIMessage.self, forKey: .persistedMessage)
            )
        case .error:
            self = .error(
                code: try container.decode(String.self, forKey: .code),
                message: try container.decode(String.self, forKey: .message),
                retryable: try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false,
                remaining: try container.decodeIfPresent(Int.self, forKey: .remaining)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let assistantMessageID, let remaining):
            try container.encode(EventType.start, forKey: .type)
            try container.encode(assistantMessageID, forKey: .assistantMessageID)
            try container.encode(remaining, forKey: .remaining)
        case .delta(let text):
            try container.encode(EventType.delta, forKey: .type)
            try container.encode(text, forKey: .text)
        case .done(let finishReason, let remaining, let inputTokens, let outputTokens, let persistedMessage):
            try container.encode(EventType.done, forKey: .type)
            try container.encodeIfPresent(finishReason, forKey: .finishReason)
            try container.encode(remaining, forKey: .remaining)
            try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
            try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
            try container.encodeIfPresent(persistedMessage, forKey: .persistedMessage)
        case .error(let code, let message, let retryable, let remaining):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
            try container.encode(retryable, forKey: .retryable)
            try container.encodeIfPresent(remaining, forKey: .remaining)
        }
    }
}

struct GradeyAIConversationDetail: Equatable, Sendable {
    let conversation: GradeyAIConversation
    let messages: [GradeyAIMessage]
}
