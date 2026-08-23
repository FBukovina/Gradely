import Foundation

#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(FirebaseFunctions)
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
#endif

enum GradeyAIError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case invalidPrompt
    case requestTooLarge
    case invalidStream
    case unauthenticated
    case server(code: String, message: String, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return AppL10n.string("gradey.auth.error.notConfigured")
        case .invalidResponse, .invalidStream:
            return AppL10n.string("gradey.account.error.invalidResponse")
        case .invalidPrompt:
            return "Enter a message between 1 and 2,000 characters."
        case .requestTooLarge:
            return "The selected school context is too large to send. Refresh it and try again."
        case .unauthenticated:
            return AppL10n.string("gradey.ai.error.unauthenticated")
        case .server(_, let message, _):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .server(_, _, let retryable):
            return retryable
        case .unauthenticated:
            return true
        default:
            return false
        }
    }
}

protocol GradeyAIClient {
    func loadStatus() async throws -> GradeyAIStatus
    func acceptConsent() async throws -> GradeyAIConsent
    func revokeConsent() async throws
    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation]
    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation
    func loadConversation(id: String) async throws -> GradeyAIConversationDetail
    func deleteConversation(id: String) async throws
    func deleteAllConversations(schoolScope: String) async throws
    func streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot
    ) -> AsyncThrowingStream<GradeyAIStreamEvent, Error>
}

final class MockGradeyAIClient: GradeyAIClient {
    var status: GradeyAIStatus
    var conversations: [GradeyAIConversation]
    var messagesByConversationID: [String: [GradeyAIMessage]]
    var responseText: String
    var error: Error?
    var holdsList = false

    private var listContinuation: CheckedContinuation<Void, Never>?

    init(
        status: GradeyAIStatus = GradeyAIStatus(
            enabled: true,
            consentRequired: false,
            termsVersion: "1",
            dailyLimit: 5,
            dailyUsed: 0,
            remaining: 5,
            resetAt: nil
        ),
        conversations: [GradeyAIConversation] = [],
        messagesByConversationID: [String: [GradeyAIMessage]] = [:],
        responseText: String = "I can help you understand your marks and plan around your timetable."
    ) {
        self.status = status
        self.conversations = conversations
        self.messagesByConversationID = messagesByConversationID
        self.responseText = responseText
    }

    func loadStatus() async throws -> GradeyAIStatus {
        if let error { throw error }
        return status
    }

    func acceptConsent() async throws -> GradeyAIConsent {
        if let error { throw error }
        status.consentRequired = false
        return GradeyAIConsent(consented: true, termsVersion: status.termsVersion)
    }

    func revokeConsent() async throws {
        if let error { throw error }
        status.consentRequired = true
        conversations = []
        messagesByConversationID = [:]
    }

    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation] {
        if let error { throw error }
        if holdsList {
            await withCheckedContinuation { continuation in
                listContinuation = continuation
            }
        }
        return conversations
            .filter { $0.schoolScope == schoolScope }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func releaseList() {
        listContinuation?.resume()
        listContinuation = nil
        holdsList = false
    }

    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation {
        if let error { throw error }
        let now = Date()
        let conversation = GradeyAIConversation(
            id: UUID().uuidString,
            schoolScope: schoolScope,
            title: title ?? "New chat",
            createdAt: now,
            updatedAt: now,
            lastMessageAt: nil
        )
        conversations.insert(conversation, at: 0)
        messagesByConversationID[conversation.id] = []
        return conversation
    }

    func loadConversation(id: String) async throws -> GradeyAIConversationDetail {
        if let error { throw error }
        guard let conversation = conversations.first(where: { $0.id == id }) else {
            throw GradeyAIError.server(code: "not_found", message: "Chat not found.", retryable: false)
        }
        return GradeyAIConversationDetail(
            conversation: conversation,
            messages: messagesByConversationID[id] ?? []
        )
    }

    func deleteConversation(id: String) async throws {
        if let error { throw error }
        conversations.removeAll { $0.id == id }
        messagesByConversationID[id] = nil
    }

    func deleteAllConversations(schoolScope: String) async throws {
        if let error { throw error }
        let ids = Set(conversations.filter { $0.schoolScope == schoolScope }.map(\.id))
        conversations.removeAll { ids.contains($0.id) }
        messagesByConversationID = messagesByConversationID.filter { !ids.contains($0.key) }
    }

    func streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot
    ) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }

                let now = Date()
                let assistantID = UUID().uuidString
                let remaining = max(0, status.remaining - 1)
                continuation.yield(.start(assistantMessageID: assistantID, remaining: remaining))
                let chunks = responseText.split(separator: " ", omittingEmptySubsequences: false)
                for (index, chunk) in chunks.enumerated() {
                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(.delta(text: index == 0 ? String(chunk) : " \(chunk)"))
                    await Task.yield()
                }
                status.dailyUsed += 1
                status.remaining = remaining
                continuation.yield(.done(
                    finishReason: "stop",
                    remaining: remaining,
                    inputTokens: nil,
                    outputTokens: nil,
                    persistedMessage: nil
                ))

                let userMessage = GradeyAIMessage(
                    id: clientMessageID,
                    conversationID: conversationID,
                    clientMessageID: clientMessageID,
                    role: .user,
                    content: text,
                    status: .complete,
                    createdAt: now,
                    contextGeneratedAt: context.generatedAt
                )
                let assistantMessage = GradeyAIMessage(
                    id: assistantID,
                    conversationID: conversationID,
                    clientMessageID: nil,
                    role: .assistant,
                    content: responseText,
                    status: .complete,
                    createdAt: now,
                    contextGeneratedAt: context.generatedAt
                )
                messagesByConversationID[conversationID, default: []].append(contentsOf: [userMessage, assistantMessage])
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
