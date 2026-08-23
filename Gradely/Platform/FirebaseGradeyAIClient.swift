import Foundation

#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(FirebaseFunctions)
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions

final class FirebaseGradeyAIClient: GradeyAIClient {
    private static let region = "europe-west1"
    private static let maximumPromptLength = 2_000
    private static let maximumContextBytes = 96 * 1_024
    private static let maximumRequestBytes = 128 * 1_024
    private static let callableTimeout: TimeInterval = 120

    private let identityCoordinator = FirebaseGradeyAIIdentityCoordinator()
    private let accountIDProvider: @Sendable () -> String?

    init(accountIDProvider: @escaping @Sendable () -> String? = { nil }) {
        self.accountIDProvider = accountIDProvider
    }

    private var gradeyAccountID: String? {
        let trimmed = accountIDProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func loadStatus() async throws -> GradeyAIStatus {
        let response: FirebaseGradeyAIStatusDTO = try await call(
            "gradeyAIGetStatus",
            request: FirebaseGradeyAIEmptyRequest(gradeyAccountID: gradeyAccountID)
        )
        return response.model
    }

    func acceptConsent() async throws -> GradeyAIConsent {
        try await identityCoordinator.ensureIdentity()
        let currentStatus = try await loadStatus()
        let response: FirebaseGradeyAIStatusEnvelope = try await call(
            "gradeyAIAcceptConsent",
            request: FirebaseGradeyAIAcceptConsentRequest(
                termsVersion: currentStatus.termsVersion,
                gradeyAccountID: gradeyAccountID
            )
        )
        return GradeyAIConsent(consented: true, termsVersion: response.status.termsVersion)
    }

    func revokeConsent() async throws {
        let response: FirebaseGradeyAIRevokeResponse = try await call(
            "gradeyAIRevokeConsent",
            request: FirebaseGradeyAIEmptyRequest(gradeyAccountID: gradeyAccountID)
        )
        if response.anonymousIdentityDeleted == true {
            try? Auth.auth().signOut()
        }
    }

    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation] {
        let response: FirebaseGradeyAIChatsResponse = try await call(
            "gradeyAIListChats",
            request: FirebaseGradeyAISchoolScopeRequest(schoolScope: schoolScope, gradeyAccountID: gradeyAccountID)
        )
        return response.chats.map(\.model)
    }

    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation {
        let response: FirebaseGradeyAIChatResponse = try await call(
            "gradeyAICreateChat",
            request: FirebaseGradeyAICreateChatRequest(
                schoolScope: schoolScope,
                title: title,
                gradeyAccountID: gradeyAccountID
            )
        )
        return response.chat.model
    }

    func loadConversation(id: String) async throws -> GradeyAIConversationDetail {
        let response: FirebaseGradeyAIChatDetailResponse = try await call(
            "gradeyAILoadChat",
            request: FirebaseGradeyAIChatRequest(chatID: id, gradeyAccountID: gradeyAccountID)
        )
        return GradeyAIConversationDetail(
            conversation: response.chat.model,
            messages: response.decodedMessages(fallbackConversationID: id)
        )
    }

    func deleteConversation(id: String) async throws {
        let _: FirebaseGradeyAIDeletionResponse = try await call(
            "gradeyAIDeleteChat",
            request: FirebaseGradeyAIChatRequest(chatID: id, gradeyAccountID: gradeyAccountID)
        )
    }

    func deleteAllConversations(schoolScope: String) async throws {
        let _: FirebaseGradeyAIDeletionResponse = try await call(
            "gradeyAIDeleteAll",
            request: FirebaseGradeyAISchoolScopeRequest(schoolScope: schoolScope, gradeyAccountID: gradeyAccountID)
        )
    }

    func streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot
    ) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty, trimmedText.count <= Self.maximumPromptLength else {
                        throw GradeyAIError.invalidPrompt
                    }

                    var minimizedContext = FirebaseGradeyAIContextDTO(context)
                    try minimizedContext.constrainEncodedSize(to: Self.maximumContextBytes)
                    let request = FirebaseGradeyAIStreamRequest(
                        chatID: conversationID,
                        clientMessageID: clientMessageID,
                        text: trimmedText,
                        locale: Locale.current.identifier,
                        schoolScope: context.schoolScope,
                        context: minimizedContext,
                        contextGeneratedAt: Self.milliseconds(context.generatedAt),
                        gradeyAccountID: gradeyAccountID
                    )
                    guard try JSONEncoder().encode(request).count <= Self.maximumRequestBytes else {
                        throw GradeyAIError.requestTooLarge
                    }

                    try await identityCoordinator.ensureIdentity()
                    guard GradeyFirebaseConfiguration.isConfigured else {
                        throw GradeyAIError.notConfigured
                    }

                    typealias FirebaseStream = FirebaseFunctions.StreamResponse<
                        FirebaseGradeyAIStreamEventDTO,
                        FirebaseGradeyAIStreamEventDTO
                    >
                    var callable: Callable<FirebaseGradeyAIStreamRequest, FirebaseStream> =
                        Functions.functions(region: Self.region).httpsCallable(
                            "gradeyAIStreamReply",
                            options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)
                        )
                    callable.timeoutInterval = Self.callableTimeout

                    var receivedTerminalEvent = false
                    for try await response in try callable.stream(request) {
                        try Task.checkCancellation()
                        let payload: FirebaseGradeyAIStreamEventDTO
                        let isFinalResult: Bool
                        switch response {
                        case .message(let message):
                            payload = message
                            isFinalResult = false
                        case .result(let result):
                            payload = result
                            isFinalResult = true
                        }

                        if isFinalResult, receivedTerminalEvent { continue }
                        let event = try payload.model(fallbackConversationID: conversationID)
                        continuation.yield(event)
                        if payload.isTerminal { receivedTerminalEvent = true }
                    }

                    guard receivedTerminalEvent else { throw GradeyAIError.invalidStream }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: Self.mappedError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        requiresIdentity: Bool = true
    ) async throws -> Response {
        do {
            GradeyFirebaseConfiguration.configureIfNeeded()
            guard GradeyFirebaseConfiguration.isConfigured else {
                throw GradeyAIError.notConfigured
            }
            if requiresIdentity {
                try await identityCoordinator.ensureIdentity()
            }
            var callable: Callable<Request, Response> = Functions.functions(region: Self.region)
                .httpsCallable(name)
            callable.timeoutInterval = Self.callableTimeout
            return try await callable(request)
        } catch {
            throw Self.mappedError(error)
        }
    }

    private static func milliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1_000).rounded()
    }

    private static func mappedError(_ error: Error) -> Error {
        if error is DecodingError {
            return GradeyAIError.invalidResponse
        }
        if error is CancellationError || error is GradeyAIError { return error }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            return GradeyAIError.unauthenticated
        }
        guard nsError.domain == FunctionsErrorDomain else { return error }
        let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let code = details?["code"] as? String ?? "firebase_\(nsError.code)"
        let message = details?["message"] as? String ?? nsError.localizedDescription
        if nsError.code == FunctionsErrorCode.unauthenticated.rawValue
            || code.caseInsensitiveCompare("unauthenticated") == .orderedSame
            || message.localizedCaseInsensitiveContains("unauthenticated") {
            return GradeyAIError.unauthenticated
        }
        let retryable = details?["retryable"] as? Bool
            ?? [
                FunctionsErrorCode.cancelled.rawValue,
                FunctionsErrorCode.deadlineExceeded.rawValue,
                FunctionsErrorCode.resourceExhausted.rawValue,
                FunctionsErrorCode.aborted.rawValue,
                FunctionsErrorCode.internal.rawValue,
                FunctionsErrorCode.unavailable.rawValue,
            ].contains(nsError.code)
        return GradeyAIError.server(code: code, message: message, retryable: retryable)
    }
}

private actor FirebaseGradeyAIIdentityCoordinator {
    func ensureIdentity() async throws {
        GradeyFirebaseConfiguration.configureIfNeeded()
        guard GradeyFirebaseConfiguration.isConfigured else {
            throw GradeyAIError.notConfigured
        }
        if let user = Auth.auth().currentUser {
            do {
                _ = try await user.getIDToken()
                return
            } catch {
                try? Auth.auth().signOut()
            }
        }
        _ = try await Auth.auth().signInAnonymously()
    }
}

nonisolated private struct FirebaseGradeyAIEmptyRequest: Codable, Sendable {
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct FirebaseGradeyAIAcceptConsentRequest: Codable, Sendable {
    let termsVersion: String
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case termsVersion
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct FirebaseGradeyAISchoolScopeRequest: Codable, Sendable {
    let schoolScope: String
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case schoolScope
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct FirebaseGradeyAIChatRequest: Codable, Sendable {
    let chatID: String
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case chatID
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct FirebaseGradeyAICreateChatRequest: Codable, Sendable {
    let schoolScope: String
    let title: String?
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case schoolScope
        case title
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct FirebaseGradeyAIStreamRequest: Codable, Sendable {
    let chatID: String
    let clientMessageID: String
    let text: String
    let locale: String
    let schoolScope: String
    let context: FirebaseGradeyAIContextDTO
    let contextGeneratedAt: Double
    var gradeyAccountID: String?

    enum CodingKeys: String, CodingKey {
        case chatID
        case clientMessageID
        case text
        case locale
        case schoolScope
        case context
        case contextGeneratedAt
        case gradeyAccountID = "gradey_account_id"
    }
}

nonisolated private struct AnyFirebaseCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

nonisolated private enum FirebaseFlexibleJSON: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([FirebaseFlexibleJSON])
    case object([String: FirebaseFlexibleJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FirebaseFlexibleJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FirebaseFlexibleJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Firebase JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

nonisolated private enum FirebaseFlexibleTime {
    static func milliseconds(
        in container: KeyedDecodingContainer<AnyFirebaseCodingKey>,
        names: String...
    ) -> Double? {
        for name in names {
            let key = AnyFirebaseCodingKey(name)
            if let value = try? container.decode(Double.self, forKey: key) {
                return normalize(value)
            }
            if let value = try? container.decode(Int64.self, forKey: key) {
                return normalize(Double(value))
            }
            if let value = try? container.decode(String.self, forKey: key),
               let parsed = parse(value) {
                return parsed
            }
            if let timestamp = try? container.decode(Timestamp.self, forKey: key) {
                return timestamp.milliseconds
            }
        }
        return nil
    }

    static func normalize(_ value: Double) -> Double {
        abs(value) < 10_000_000_000 ? value * 1_000 : value
    }

    private static func parse(_ value: String) -> Double? {
        if let number = Double(value) {
            return normalize(number)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date.timeIntervalSince1970 * 1_000
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value).map { $0.timeIntervalSince1970 * 1_000 }
    }

    private struct Timestamp: Decodable {
        let milliseconds: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyFirebaseCodingKey.self)
            if let value = try container.decodeIfPresent(String.self, forKey: AnyFirebaseCodingKey("value")) {
                if let parsed = FirebaseFlexibleTime.parse(value) {
                    milliseconds = parsed
                    return
                }
            }
            let seconds = FirebaseFlexibleTime.number(in: container, names: "seconds", "_seconds")
            let nanos = FirebaseFlexibleTime.number(in: container, names: "nanos", "nanoseconds", "_nanoseconds") ?? 0
            guard let seconds else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Missing timestamp seconds")
                )
            }
            milliseconds = seconds * 1_000 + nanos / 1_000_000
        }
    }

    private static func number(
        in container: KeyedDecodingContainer<AnyFirebaseCodingKey>,
        names: String...
    ) -> Double? {
        for name in names {
            let key = AnyFirebaseCodingKey(name)
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Int64.self, forKey: key) {
                return Double(value)
            }
            if let value = try? container.decode(String.self, forKey: key), let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }
}

private extension KeyedDecodingContainer where Key == AnyFirebaseCodingKey {
    func flexibleString(_ names: String...) -> String? {
        for name in names {
            let key = AnyFirebaseCodingKey(name)
            if let value = try? decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }
        }
        return nil
    }

    func flexibleBool(_ names: String..., fallback: Bool) -> Bool {
        for name in names {
            if let value = boolValue(for: AnyFirebaseCodingKey(name)) {
                return value
            }
        }
        return fallback
    }

    private func boolValue(for key: AnyFirebaseCodingKey) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            switch value {
            case 0: return false
            case 1: return true
            default: return nil
            }
        }
        if let value = try? decode(Double.self, forKey: key) {
            if value == 0 { return false }
            if value == 1 { return true }
            return nil
        }
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    func flexibleInt(_ names: String..., fallback: Int) -> Int {
        for name in names {
            let key = AnyFirebaseCodingKey(name)
            if let value = try? decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? decode(Double.self, forKey: key) {
                return Int(value.rounded())
            }
            if let value = try? decode(String.self, forKey: key), let parsed = Int(value) {
                return parsed
            }
        }
        return fallback
    }
}

nonisolated private struct FirebaseGradeyAIStatusDTO: Codable, Sendable {
    let enabled: Bool
    let consentRequired: Bool
    let termsVersion: String
    let tier: String
    let dailyLimit: Int
    let dailyUsed: Int
    let remaining: Int
    let resetAt: Double?

    var model: GradeyAIStatus {
        GradeyAIStatus(
            enabled: enabled,
            consentRequired: consentRequired,
            termsVersion: termsVersion,
            dailyLimit: dailyLimit,
            dailyUsed: dailyUsed,
            remaining: remaining,
            resetAt: resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
            tier: GradeyAIIdentityTier(rawValue: tier) ?? .anonymous
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyFirebaseCodingKey.self)
        enabled = container.flexibleBool("enabled", fallback: false)
        consentRequired = container.flexibleBool("consentRequired", "consent_required", fallback: true)
        termsVersion = container.flexibleString("termsVersion", "terms_version") ?? ""
        tier = container.flexibleString("tier") ?? GradeyAIIdentityTier.anonymous.rawValue
        dailyLimit = container.flexibleInt("dailyLimit", "daily_limit", fallback: 5)
        dailyUsed = container.flexibleInt("dailyUsed", "daily_used", fallback: 0)
        remaining = container.flexibleInt(
            "remaining",
            fallback: max(0, dailyLimit - dailyUsed)
        )
        resetAt = FirebaseFlexibleTime.milliseconds(in: container, names: "resetAt", "reset_at")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyFirebaseCodingKey.self)
        try container.encode(enabled, forKey: AnyFirebaseCodingKey("enabled"))
        try container.encode(consentRequired, forKey: AnyFirebaseCodingKey("consentRequired"))
        try container.encode(termsVersion, forKey: AnyFirebaseCodingKey("termsVersion"))
        try container.encode(tier, forKey: AnyFirebaseCodingKey("tier"))
        try container.encode(dailyLimit, forKey: AnyFirebaseCodingKey("dailyLimit"))
        try container.encode(dailyUsed, forKey: AnyFirebaseCodingKey("dailyUsed"))
        try container.encode(remaining, forKey: AnyFirebaseCodingKey("remaining"))
        try container.encodeIfPresent(resetAt, forKey: AnyFirebaseCodingKey("resetAt"))
    }
}

nonisolated private struct FirebaseGradeyAIStatusEnvelope: Codable, Sendable {
    let status: FirebaseGradeyAIStatusDTO
}

nonisolated private struct FirebaseGradeyAIChatDTO: Codable, Sendable {
    let id: String
    let schoolScope: String
    let title: String
    let createdAt: Double
    let updatedAt: Double
    let lastMessageAt: Double?

    var model: GradeyAIConversation {
        GradeyAIConversation(
            id: id,
            schoolScope: schoolScope,
            title: title,
            createdAt: Date(timeIntervalSince1970: createdAt / 1_000),
            updatedAt: Date(timeIntervalSince1970: updatedAt / 1_000),
            lastMessageAt: lastMessageAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyFirebaseCodingKey.self)
        let now = Date().timeIntervalSince1970 * 1_000
        id = container.flexibleString("id") ?? UUID().uuidString
        schoolScope = container.flexibleString("schoolScope", "school_scope") ?? ""
        title = container.flexibleString("title") ?? ""
        createdAt = FirebaseFlexibleTime.milliseconds(in: container, names: "createdAt", "created_at") ?? now
        updatedAt = FirebaseFlexibleTime.milliseconds(in: container, names: "updatedAt", "updated_at") ?? createdAt
        lastMessageAt = FirebaseFlexibleTime.milliseconds(in: container, names: "lastMessageAt", "last_message_at")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyFirebaseCodingKey.self)
        try container.encode(id, forKey: AnyFirebaseCodingKey("id"))
        try container.encode(schoolScope, forKey: AnyFirebaseCodingKey("schoolScope"))
        try container.encode(title, forKey: AnyFirebaseCodingKey("title"))
        try container.encode(createdAt, forKey: AnyFirebaseCodingKey("createdAt"))
        try container.encode(updatedAt, forKey: AnyFirebaseCodingKey("updatedAt"))
        try container.encodeIfPresent(lastMessageAt, forKey: AnyFirebaseCodingKey("lastMessageAt"))
    }
}

nonisolated private struct FirebaseGradeyAIMessageDTO: Codable, Sendable {
    let id: String
    let conversationID: String?
    let chatID: String?
    let clientMessageID: String?
    let role: String
    let content: String
    let status: String
    let createdAt: Double
    let updatedAt: Double?
    let contextGeneratedAt: Double?

    func model(fallbackConversationID: String) -> GradeyAIMessage {
        GradeyAIMessage(
            id: id,
            conversationID: conversationID ?? chatID ?? fallbackConversationID,
            clientMessageID: clientMessageID,
            role: role == "user" ? .user : .assistant,
            content: content,
            status: modelStatus,
            createdAt: Date(timeIntervalSince1970: createdAt / 1_000),
            contextGeneratedAt: contextGeneratedAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        )
    }

    private var modelStatus: GradeyAIMessageStatus {
        switch status {
        case "pending", "streaming": .streaming
        case "cancelled", "canceled": .cancelled
        case "failed": .failed
        default: .complete
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyFirebaseCodingKey.self)
        let now = Date().timeIntervalSince1970 * 1_000
        guard let id = container.flexibleString("id") else {
            throw DecodingError.keyNotFound(
                AnyFirebaseCodingKey("id"),
                .init(codingPath: decoder.codingPath, debugDescription: "Gradey AI message is missing id")
            )
        }
        self.id = id
        conversationID = container.flexibleString("conversationID", "conversation_id")
        chatID = container.flexibleString("chatID", "chat_id", "chatId")
        clientMessageID = container.flexibleString("clientMessageID", "client_message_id")
        role = container.flexibleString("role") ?? "assistant"
        content = container.flexibleString("content", "text") ?? ""
        status = container.flexibleString("status", "state") ?? "complete"
        createdAt = FirebaseFlexibleTime.milliseconds(
            in: container,
            names: "createdAt", "created_at"
        ) ?? now
        updatedAt = FirebaseFlexibleTime.milliseconds(in: container, names: "updatedAt", "updated_at")
        contextGeneratedAt = FirebaseFlexibleTime.milliseconds(
            in: container,
            names: "contextGeneratedAt", "context_generated_at"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyFirebaseCodingKey.self)
        try container.encode(id, forKey: AnyFirebaseCodingKey("id"))
        try container.encodeIfPresent(conversationID, forKey: AnyFirebaseCodingKey("conversationID"))
        try container.encodeIfPresent(chatID, forKey: AnyFirebaseCodingKey("chatID"))
        try container.encodeIfPresent(clientMessageID, forKey: AnyFirebaseCodingKey("clientMessageID"))
        try container.encode(role, forKey: AnyFirebaseCodingKey("role"))
        try container.encode(content, forKey: AnyFirebaseCodingKey("content"))
        try container.encode(status, forKey: AnyFirebaseCodingKey("status"))
        try container.encode(createdAt, forKey: AnyFirebaseCodingKey("createdAt"))
        try container.encodeIfPresent(updatedAt, forKey: AnyFirebaseCodingKey("updatedAt"))
        try container.encodeIfPresent(contextGeneratedAt, forKey: AnyFirebaseCodingKey("contextGeneratedAt"))
    }
}

nonisolated private struct FirebaseGradeyAIChatsResponse: Codable, Sendable {
    let chats: [FirebaseGradeyAIChatDTO]
    let status: FirebaseGradeyAIStatusDTO
}

nonisolated private struct FirebaseGradeyAIChatResponse: Codable, Sendable {
    let chat: FirebaseGradeyAIChatDTO
    let status: FirebaseGradeyAIStatusDTO
}

nonisolated private struct FirebaseGradeyAIChatDetailResponse: Codable, Sendable {
    let chat: FirebaseGradeyAIChatDTO
    let messages: [FirebaseGradeyAIMessageDTO]
    let status: FirebaseGradeyAIStatusDTO?

    func decodedMessages(fallbackConversationID: String) -> [GradeyAIMessage] {
        messages
            .map { $0.model(fallbackConversationID: fallbackConversationID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyFirebaseCodingKey.self)
        if let decodedChat = try? container.decode(FirebaseGradeyAIChatDTO.self, forKey: AnyFirebaseCodingKey("chat")) {
            chat = decodedChat
        } else {
            chat = try container.decode(FirebaseGradeyAIChatDTO.self, forKey: AnyFirebaseCodingKey("conversation"))
        }
        messages = Self.decodeMessages(from: container)
        status = try container.decodeIfPresent(
            FirebaseGradeyAIStatusDTO.self,
            forKey: AnyFirebaseCodingKey("status")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyFirebaseCodingKey.self)
        try container.encode(chat, forKey: AnyFirebaseCodingKey("chat"))
        try container.encode(messages, forKey: AnyFirebaseCodingKey("messages"))
        try container.encodeIfPresent(status, forKey: AnyFirebaseCodingKey("status"))
    }

    private static func decodeMessages(
        from container: KeyedDecodingContainer<AnyFirebaseCodingKey>
    ) -> [FirebaseGradeyAIMessageDTO] {
        let keys = ["messages", "history", "items"]
        for keyName in keys {
            let key = AnyFirebaseCodingKey(keyName)
            if let decoded = try? container.decode([FirebaseGradeyAIMessageDTO].self, forKey: key) {
                return decoded
            }
            if let decoded = try? container.decode([String: FirebaseGradeyAIMessageDTO].self, forKey: key) {
                return decoded.values.sorted { $0.createdAt < $1.createdAt }
            }
            if let values = try? container.decode([FirebaseFlexibleJSON].self, forKey: key) {
                return decodeLossyMessages(values)
            }
            if let values = try? container.decode([String: FirebaseFlexibleJSON].self, forKey: key) {
                return decodeLossyMessages(Array(values.values))
            }
        }
        return []
    }

    private static func decodeLossyMessages(_ values: [FirebaseFlexibleJSON]) -> [FirebaseGradeyAIMessageDTO] {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        return values.compactMap { value in
            guard let data = try? encoder.encode(value) else { return nil }
            return try? decoder.decode(FirebaseGradeyAIMessageDTO.self, from: data)
        }
    }
}

nonisolated private struct FirebaseGradeyAIDeletionResponse: Codable, Sendable {
    let success: Bool
    let status: FirebaseGradeyAIStatusDTO?
}

nonisolated private struct FirebaseGradeyAIRevokeResponse: Codable, Sendable {
    let success: Bool
    let anonymousIdentityDeleted: Bool?
}

nonisolated private struct FirebaseGradeyAIUsageDTO: Codable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let estimatedCostUSD: Double?
}

nonisolated private struct FirebaseGradeyAIStreamEventDTO: Codable, Sendable {
    let type: String
    let chatID: String?
    let userMessageID: String?
    let assistantMessageID: String?
    let generationID: String?
    let text: String?
    let message: FirebaseGradeyAIMessageDTO?
    let status: FirebaseGradeyAIStatusDTO?
    let usage: FirebaseGradeyAIUsageDTO?
    let code: String?
    let retryable: Bool?

    var isTerminal: Bool { type == "completed" || type == "failed" }

    func model(fallbackConversationID: String) throws -> GradeyAIStreamEvent {
        switch type {
            case "started":
                guard let assistantMessageID, let status else { throw GradeyAIError.invalidStream }
                return .start(assistantMessageID: assistantMessageID, remaining: status.remaining)
            case "delta":
                guard let text else { throw GradeyAIError.invalidStream }
                return .delta(text: text)
            case "completed":
                guard let status else { throw GradeyAIError.invalidStream }
                return .done(
                    finishReason: "stop",
                    remaining: status.remaining,
                    inputTokens: usage?.inputTokens,
                    outputTokens: usage?.outputTokens,
                    persistedMessage: message?.model(fallbackConversationID: fallbackConversationID)
                )
            case "failed":
                guard let code, let text = messageText else { throw GradeyAIError.invalidStream }
                return .error(
                    code: code,
                    message: text,
                    retryable: retryable ?? false,
                    remaining: status?.remaining
                )
            default:
                throw GradeyAIError.invalidStream
        }
    }

    private var messageText: String? {
        // Failed events use a top-level string named `message`; completed events use a message
        // object. Firebase's typed decoder cannot represent both with one synthesized property,
        // so failed text is decoded by the custom initializer below.
        failedMessage
    }

    private let failedMessage: String?

    private enum CodingKeys: String, CodingKey {
        case type, chatID, userMessageID, assistantMessageID, generationID, text, message
        case status, usage, code, retryable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        chatID = try container.decodeIfPresent(String.self, forKey: .chatID)
        userMessageID = try container.decodeIfPresent(String.self, forKey: .userMessageID)
        assistantMessageID = try container.decodeIfPresent(String.self, forKey: .assistantMessageID)
        generationID = try container.decodeIfPresent(String.self, forKey: .generationID)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        message = try? container.decodeIfPresent(FirebaseGradeyAIMessageDTO.self, forKey: .message)
        failedMessage = try? container.decodeIfPresent(String.self, forKey: .message)
        status = try container.decodeIfPresent(FirebaseGradeyAIStatusDTO.self, forKey: .status)
        usage = try container.decodeIfPresent(FirebaseGradeyAIUsageDTO.self, forKey: .usage)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(chatID, forKey: .chatID)
        try container.encodeIfPresent(userMessageID, forKey: .userMessageID)
        try container.encodeIfPresent(assistantMessageID, forKey: .assistantMessageID)
        try container.encodeIfPresent(generationID, forKey: .generationID)
        try container.encodeIfPresent(text, forKey: .text)
        if let message {
            try container.encode(message, forKey: .message)
        } else {
            try container.encodeIfPresent(failedMessage, forKey: .message)
        }
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(retryable, forKey: .retryable)
    }
}

nonisolated private struct FirebaseGradeyAIContextDTO: Codable, Sendable {
    let schoolScope: String
    let generatedAt: Double
    let isStale: Bool
    let unavailableSections: [String]
    var subjects: [Subject]
    var trends: [Trend]
    var timetable: [Lesson]

    init(_ snapshot: GradeyAIContextSnapshot) {
        schoolScope = snapshot.schoolScope
        generatedAt = (snapshot.generatedAt.timeIntervalSince1970 * 1_000).rounded()
        isStale = snapshot.isStale
        unavailableSections = snapshot.unavailableSections.map(\.rawValue)
        subjects = snapshot.subjects.map(Subject.init)
        trends = snapshot.trends.map(Trend.init)
        timetable = snapshot.timetable.map(Lesson.init)
    }

    mutating func constrainEncodedSize(to maximumBytes: Int) throws {
        let encoder = JSONEncoder()
        while try encoder.encode(self).count > maximumBytes {
            if !timetable.isEmpty {
                timetable.removeLast()
                continue
            }
            if let index = subjects.indices
                .filter({ !subjects[$0].recentMarks.isEmpty })
                .max(by: { subjects[$0].recentMarks.count < subjects[$1].recentMarks.count }) {
                subjects[index].recentMarks.removeLast()
                continue
            }
            if !trends.isEmpty {
                trends.removeLast()
                continue
            }
            if !subjects.isEmpty {
                subjects.removeLast()
                continue
            }
            throw GradeyAIError.requestTooLarge
        }
    }

    nonisolated struct Mark: Codable, Sendable {
        let value: String
        let date: String
        let weight: Double?
        let title: String?
        let isPoints: Bool
        let pointsText: String?
        let maxPoints: Int?

        init(_ mark: GradeyAIMarkContext) {
            value = mark.value
            date = mark.date
            weight = mark.weight
            title = mark.title
            isPoints = mark.isPoints
            pointsText = mark.pointsText
            maxPoints = mark.maxPoints
        }
    }

    nonisolated struct Subject: Codable, Sendable {
        let id: String
        let name: String
        let abbreviation: String?
        let average: Double?
        let pointsOnly: Bool
        let totalMarkCount: Int
        var recentMarks: [Mark]

        init(_ subject: GradeyAISubjectContext) {
            id = subject.id
            name = subject.name
            abbreviation = subject.abbreviation
            average = subject.average
            pointsOnly = subject.pointsOnly
            totalMarkCount = subject.totalMarkCount
            recentMarks = subject.recentMarks.map(Mark.init)
        }
    }

    nonisolated struct Trend: Codable, Sendable {
        let subjectID: String
        let subjectName: String
        let subjectAbbreviation: String?
        let firstAverage: Double?
        let latestAverage: Double?
        let averageDelta: Double?
        let firstMarkCount: Int
        let latestMarkCount: Int

        init(_ trend: GradeyAITrendContext) {
            subjectID = trend.subjectID
            subjectName = trend.subjectName
            subjectAbbreviation = trend.subjectAbbreviation
            firstAverage = trend.firstAverage
            latestAverage = trend.latestAverage
            averageDelta = trend.averageDelta
            firstMarkCount = trend.firstMarkCount
            latestMarkCount = trend.latestMarkCount
        }
    }

    nonisolated struct Lesson: Codable, Sendable {
        let id: String
        let date: String
        let subject: String
        let subjectAbbreviation: String?
        let beginsAt: String
        let endsAt: String
        let teacher: String?
        let room: String?
        let groups: [String]
        let changeKind: String
        let changeDescription: String?

        init(_ lesson: GradeyAILessonContext) {
            id = lesson.id
            date = lesson.date
            subject = lesson.subject
            subjectAbbreviation = lesson.subjectAbbreviation
            beginsAt = lesson.beginsAt
            endsAt = lesson.endsAt
            teacher = lesson.teacher
            room = lesson.room
            groups = lesson.groups
            changeKind = lesson.changeKind.rawValue
            changeDescription = lesson.changeDescription
        }
    }
}

nonisolated enum FirebaseGradeyAIWireContract {
    static func decodeStatus(_ data: Data) throws -> GradeyAIStatus {
        try JSONDecoder().decode(FirebaseGradeyAIStatusDTO.self, from: data).model
    }

    static func decodeStreamEvent(
        _ data: Data,
        fallbackConversationID: String
    ) throws -> GradeyAIStreamEvent {
        let payload = try JSONDecoder().decode(FirebaseGradeyAIStreamEventDTO.self, from: data)
        return try payload.model(fallbackConversationID: fallbackConversationID)
    }

    static func decodeChatDetail(
        _ data: Data,
        fallbackConversationID: String
    ) throws -> GradeyAIConversationDetail {
        let payload = try JSONDecoder().decode(FirebaseGradeyAIChatDetailResponse.self, from: data)
        return GradeyAIConversationDetail(
            conversation: payload.chat.model,
            messages: payload.decodedMessages(fallbackConversationID: fallbackConversationID)
        )
    }

    static func encodeMinimizedContext(
        _ snapshot: GradeyAIContextSnapshot,
        maximumBytes: Int = 96 * 1_024
    ) throws -> Data {
        var context = FirebaseGradeyAIContextDTO(snapshot)
        try context.constrainEncodedSize(to: maximumBytes)
        return try JSONEncoder().encode(context)
    }
}

#else

final class FirebaseGradeyAIClient: GradeyAIClient {
    init(accountIDProvider: @escaping @Sendable () -> String? = { nil }) {
        _ = accountIDProvider
    }

    func loadStatus() async throws -> GradeyAIStatus { throw GradeyAIError.notConfigured }
    func acceptConsent() async throws -> GradeyAIConsent { throw GradeyAIError.notConfigured }
    func revokeConsent() async throws { throw GradeyAIError.notConfigured }
    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation] {
        throw GradeyAIError.notConfigured
    }
    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation {
        throw GradeyAIError.notConfigured
    }
    func loadConversation(id: String) async throws -> GradeyAIConversationDetail {
        throw GradeyAIError.notConfigured
    }
    func deleteConversation(id: String) async throws { throw GradeyAIError.notConfigured }
    func deleteAllConversations(schoolScope: String) async throws { throw GradeyAIError.notConfigured }
    func streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot
    ) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: GradeyAIError.notConfigured) }
    }
}

#endif
