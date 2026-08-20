import Foundation

public struct GradelyWatchAIStreamRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let conversationID: String?
    public let clientMessageID: String
    public let text: String

    public init(
        requestID: String,
        conversationID: String?,
        clientMessageID: String,
        text: String
    ) {
        self.requestID = requestID
        self.conversationID = conversationID
        self.clientMessageID = clientMessageID
        self.text = text
    }
}

public struct GradelyWatchAIStreamAck: Codable, Equatable, Sendable {
    public let accepted: Bool
    public let conversationID: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        accepted: Bool,
        conversationID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.accepted = accepted
        self.conversationID = conversationID
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public static func success(conversationID: String) -> GradelyWatchAIStreamAck {
        GradelyWatchAIStreamAck(accepted: true, conversationID: conversationID)
    }

    public static func failure(code: String, message: String) -> GradelyWatchAIStreamAck {
        GradelyWatchAIStreamAck(accepted: false, errorCode: code, errorMessage: message)
    }
}

public enum GradelyWatchAIStreamKind: String, Codable, Equatable, Sendable {
    case started
    case delta
    case done
    case failed
}

public struct GradelyWatchAIStreamEvent: Codable, Equatable, Sendable {
    public let requestID: String
    public let conversationID: String?
    public let kind: GradelyWatchAIStreamKind
    public let text: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let remaining: Int?

    public init(
        requestID: String,
        conversationID: String? = nil,
        kind: GradelyWatchAIStreamKind,
        text: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        remaining: Int? = nil
    ) {
        self.requestID = requestID
        self.conversationID = conversationID
        self.kind = kind
        self.text = text
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.remaining = remaining
    }
}

public struct GradelyWatchAICancel: Codable, Equatable, Sendable {
    public let requestID: String

    public init(requestID: String) {
        self.requestID = requestID
    }
}

public enum GradelyWatchAIErrorCode {
    public static let supporterRequired = "supporter_required"
    public static let consentRequired = "consent_required"
    public static let phoneUnreachable = "phone_unreachable"
    public static let notConfigured = "not_configured"
    public static let noSchoolAccount = "no_school_account"
    public static let quotaExceeded = "quota_exceeded"
    public static let cancelled = "cancelled"
}

public extension GradelyWatchSyncCodec {
    static func envelope(for request: GradelyWatchAIStreamRequest) throws -> [String: Any] {
        try envelope(messageType: GradelyWatchMessageType.aiStreamRequest, payload: request)
    }

    static func envelope(for ack: GradelyWatchAIStreamAck) throws -> [String: Any] {
        try envelope(messageType: GradelyWatchMessageType.aiStreamAck, payload: ack)
    }

    static func envelope(for event: GradelyWatchAIStreamEvent) throws -> [String: Any] {
        try envelope(messageType: GradelyWatchMessageType.aiStreamEvent, payload: event)
    }

    static func envelope(for cancel: GradelyWatchAICancel) throws -> [String: Any] {
        try envelope(messageType: GradelyWatchMessageType.aiCancel, payload: cancel)
    }

    static func aiRequest(from envelope: [String: Any]) throws -> GradelyWatchAIStreamRequest? {
        try decode(GradelyWatchAIStreamRequest.self, from: envelope, expectedType: GradelyWatchMessageType.aiStreamRequest)
    }

    static func aiAck(from envelope: [String: Any]) throws -> GradelyWatchAIStreamAck? {
        try decode(GradelyWatchAIStreamAck.self, from: envelope, expectedType: GradelyWatchMessageType.aiStreamAck)
    }

    static func aiEvent(from envelope: [String: Any]) throws -> GradelyWatchAIStreamEvent? {
        try decode(GradelyWatchAIStreamEvent.self, from: envelope, expectedType: GradelyWatchMessageType.aiStreamEvent)
    }

    static func aiCancel(from envelope: [String: Any]) throws -> GradelyWatchAICancel? {
        try decode(GradelyWatchAICancel.self, from: envelope, expectedType: GradelyWatchMessageType.aiCancel)
    }

    static func isAIStreamRequest(_ envelope: [String: Any]) -> Bool {
        envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.aiStreamRequest
    }

    static func isAICancel(_ envelope: [String: Any]) -> Bool {
        envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.aiCancel
    }

    static func isAIStreamEvent(_ envelope: [String: Any]) -> Bool {
        envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.aiStreamEvent
    }

    private static func envelope<T: Encodable>(messageType: String, payload: T) throws -> [String: Any] {
        [
            GradelyWatchMessageKey.messageType: messageType,
            GradelyWatchMessageKey.schemaVersion: GradelyWatchSyncPayload.currentSchemaVersion,
            GradelyWatchMessageKey.payloadData: try encoder.encode(payload)
        ]
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from envelope: [String: Any],
        expectedType: String
    ) throws -> T? {
        guard envelope[GradelyWatchMessageKey.messageType] as? String == expectedType,
              let data = envelope[GradelyWatchMessageKey.payloadData] as? Data
        else {
            return nil
        }

        return try decoder.decode(type, from: data)
    }
}
