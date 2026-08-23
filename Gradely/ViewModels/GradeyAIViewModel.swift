import Foundation
import Observation

@MainActor
@Observable
final class GradeyAIViewModel {
    var conversations: [GradeyAIConversation] = []
    var messages: [GradeyAIMessage] = []
    var status: GradeyAIStatus?
    var draft = ""
    var currentConversation: GradeyAIConversation?
    var isLoading = false
    var isStreaming = false
    var isRefreshingContext = false
    var isOpeningConversation = false
    var contextSnapshot: GradeyAIContextSnapshot?
    var contextError: String?
    var errorMessage: String?

    var selectedConversation: GradeyAIConversation? {
        currentConversation
    }

    var hasConsent: Bool {
        status?.consentRequired == false
    }

    var contextGeneratedAt: Date? {
        contextSnapshot?.generatedAt
    }

    var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isStreaming
            && !trimmed.isEmpty
            && trimmed.count <= 2_000
            && contextSnapshot != nil
            && status?.canSend == true
    }

    var canStartNewChat: Bool {
        status?.enabled == true
            && status?.consentRequired == false
            && (status?.remaining ?? 0) > 0
            && !isStreaming
    }

    var starterPrompts: [String] {
        let usesCzech = Locale.current.language.languageCode?.identifier == "cs"
        var prompts: [String] = []

        if let trend = contextSnapshot?.trends.first(where: { ($0.averageDelta ?? 0) > 0.01 }) {
            prompts.append(usesCzech
                ? "Jak se můžu zlepšit v předmětu \(trend.subjectName)?"
                : "How can I improve in \(trend.subjectName)?")
        }
        if let lesson = contextSnapshot?.timetable.first {
            prompts.append(usesCzech
                ? "Jak se mám připravit na \(lesson.subject)?"
                : "How should I prepare for \(lesson.subject)?")
        }
        prompts.append(usesCzech
            ? "Shrň moje známky a navrhni, na co se zaměřit."
            : "Summarize my marks and suggest what to focus on.")
        prompts.append(usesCzech
            ? "Co mě čeká v rozvrhu tento a příští týden?"
            : "What is coming up in my timetable this and next week?")
        return Array(prompts.prefix(3))
    }

    private let client: any GradeyAIClient
    private let contextBuilder: any GradeyAIContextBuilding
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var activeStreamToken: UUID?
    @ObservationIgnored private var activeSchoolScope: String?
    @ObservationIgnored private var lastFailedRequest: FailedRequest?
    @ObservationIgnored private var draftConversationID: String?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var reportedDailyLimit = 0
    @ObservationIgnored private var reportedUsed = 0
    @ObservationIgnored private var supportTier: SupportTier?
    @ObservationIgnored private var serverStatus: GradeyAIStatus?

    var isDraftChat: Bool {
        guard let draftConversationID, let currentConversation else { return false }
        return currentConversation.id == draftConversationID
    }

    init(client: any GradeyAIClient, contextBuilder: any GradeyAIContextBuilding) {
        self.client = client
        self.contextBuilder = contextBuilder
    }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            if status != nil { return }
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBootstrap()
        }
        bootstrapTask = task
        await task.value
        if bootstrapTask == task {
            bootstrapTask = nil
        }
    }

    func refreshStatus() async {
        if case .success(let loadedStatus) = await loadStatusAttempt() {
            ingestStatus(loadedStatus)
        }
    }

    func applySupportTier(_ tier: SupportTier, catalogLoaded: Bool) {
        guard catalogLoaded || tier != .none else { return }
        supportTier = tier
        recomposeStatus()
    }

    private func performBootstrap() async {
        stop()
        errorMessage = nil
        contextError = nil

        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            if let activeSchoolScope, activeSchoolScope != schoolScope {
                conversations = []
                messages = []
                currentConversation = nil
                draftConversationID = nil
                status = nil
                serverStatus = nil
                reportedDailyLimit = 0
                reportedUsed = 0
                lastFailedRequest = nil
                isOpeningConversation = false
            }
            activeSchoolScope = schoolScope
            if contextSnapshot == nil {
                contextSnapshot = try contextBuilder.cachedContext()
            }

            let isInitialLoad = status == nil
            if isInitialLoad {
                isLoading = true
            }

            async let statusAttempt = loadStatusAttempt()
            async let conversationsAttempt = loadConversationsAttempt(schoolScope: schoolScope)
            async let contextAttempt = refreshContextAttempt()

            switch await statusAttempt {
            case .success(let loadedStatus):
                ingestStatus(loadedStatus)
                isLoading = false
                if loadedStatus.consentRequired {
                    conversations = []
                    if currentConversation != nil, !isDraftChat {
                        currentConversation = nil
                        messages = []
                    }
                } else {
                    switch await conversationsAttempt {
                    case .success(let loadedConversations):
                        conversations = loadedConversations
                        if let currentConversation,
                           let refreshed = loadedConversations.first(where: { $0.id == currentConversation.id }) {
                            self.currentConversation = refreshed
                        }
                    case .failure(let error):
                        if conversations.isEmpty, currentConversation == nil {
                            errorMessage = userFacingMessage(for: error)
                        }
                    }
                }
            case .failure(let error):
                isLoading = false
                if status == nil {
                    errorMessage = userFacingMessage(for: error)
                }
            }

            applyContextResult(await contextAttempt)
        } catch {
            isLoading = false
            errorMessage = userFacingMessage(for: error)
            contextError = userFacingMessage(for: error)
        }
    }

    func acceptConsent() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.acceptConsent()
            if var currentStatus = status {
                currentStatus.consentRequired = false
                status = currentStatus
            }
            ingestStatus(try await client.loadStatus())
            if let status, !status.consentRequired {
                let schoolScope = try contextBuilder.currentSchoolScope()
                conversations = try await client.listConversations(schoolScope: schoolScope)
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func revokeConsent() async {
        stop()
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.revokeConsent()
            conversations = []
            messages = []
            currentConversation = nil
            reportedUsed = 0
            if var currentStatus = serverStatus ?? status {
                currentStatus.consentRequired = true
                currentStatus.dailyUsed = 0
                currentStatus.remaining = currentStatus.dailyLimit
                ingestStatus(currentStatus)
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func beginDraftChat() {
        stop()
        errorMessage = nil
        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            let now = Date()
            let conversation = GradeyAIConversation(
                id: UUID().uuidString,
                schoolScope: schoolScope,
                title: AppL10n.string("gradey.ai.newChat"),
                createdAt: now,
                updatedAt: now,
                lastMessageAt: nil
            )
            draftConversationID = conversation.id
            currentConversation = conversation
            messages = []
            draft = ""
            lastFailedRequest = nil
            isOpeningConversation = false
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    @discardableResult
    func create(title: String? = nil, replacingCurrentChat: Bool = true) async -> GradeyAIConversation? {
        errorMessage = nil
        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            let conversation = try await client.createConversation(
                schoolScope: schoolScope,
                title: title
            )
            upsert(conversation)
            currentConversation = conversation
            draftConversationID = nil
            if replacingCurrentChat {
                messages = []
                lastFailedRequest = nil
            }
            return conversation
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    func open(_ conversation: GradeyAIConversation) async {
        stop()
        errorMessage = nil
        draftConversationID = nil
        currentConversation = conversation
        messages = []
        lastFailedRequest = nil
        isOpeningConversation = true
        defer { isOpeningConversation = false }
        do {
            let detail = try await client.loadConversation(id: conversation.id)
            currentConversation = detail.conversation
            messages = detail.messages
            upsert(detail.conversation)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func closeConversation() {
        stop()
        if let draftConversationID {
            conversations.removeAll { $0.id == draftConversationID }
        }
        draftConversationID = nil
        currentConversation = nil
        messages = []
        lastFailedRequest = nil
        isOpeningConversation = false
    }

    func send() async {
        await send(draft)
    }

    func send(_ proposedText: String) async {
        guard !isStreaming else { return }
        let text = proposedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else {
            errorMessage = GradeyAIError.invalidPrompt.localizedDescription
            return
        }
        guard status?.enabled == true else {
            errorMessage = "Gradey AI is not available right now."
            return
        }
        guard status?.consentRequired == false else {
            errorMessage = "Accept the Gradey AI privacy notice before sending a message."
            return
        }
        guard (status?.remaining ?? 0) > 0 else {
            errorMessage = AppL10n.string("gradey.ai.limit.reached")
            return
        }

        if contextSnapshot == nil {
            await refreshContext()
        }
        guard let contextSnapshot else {
            errorMessage = contextError ?? GradeyAIContextError.noContextAvailable.localizedDescription
            return
        }

        draft = ""
        errorMessage = nil
        let clientMessageID = UUID().uuidString
        var conversation = currentConversation
        let needsServerCreate = conversation == nil || isDraftChat
        let userMessage = GradeyAIMessage(
            id: clientMessageID,
            conversationID: conversation?.id ?? clientMessageID,
            clientMessageID: clientMessageID,
            role: .user,
            content: text,
            status: .complete,
            createdAt: Date(),
            contextGeneratedAt: contextSnapshot.generatedAt
        )
        messages.append(userMessage)
        lastFailedRequest = nil

        if needsServerCreate {
            let draftID = draftConversationID
            conversation = await create(title: Self.title(from: text), replacingCurrentChat: false)
            if let conversation, let index = messages.lastIndex(where: { $0.id == clientMessageID }) {
                messages[index] = GradeyAIMessage(
                    id: clientMessageID,
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    role: .user,
                    content: text,
                    status: .complete,
                    createdAt: userMessage.createdAt,
                    contextGeneratedAt: contextSnapshot.generatedAt
                )
            }
            if let draftID {
                conversations.removeAll { $0.id == draftID }
            }
        }
        guard let conversation else {
            messages.removeAll { $0.id == clientMessageID }
            draft = text
            return
        }

        updateConversationAfterMessage(conversation, title: Self.title(from: text))
        await startStream(
            conversation: conversation,
            text: text,
            clientMessageID: clientMessageID,
            context: contextSnapshot
        )
    }

    func retry() async {
        guard !isStreaming, let failed = lastFailedRequest else { return }
        guard currentConversation?.id == failed.conversationID else {
            lastFailedRequest = nil
            return
        }
        guard status?.canSend == true, let contextSnapshot else { return }

        messages.removeAll {
            $0.role == .assistant && $0.status == .failed && $0.createdAt >= failed.startedAt
        }
        errorMessage = nil
        await startStream(
            conversation: currentConversation!,
            text: failed.text,
            clientMessageID: failed.clientMessageID,
            context: contextSnapshot
        )
    }

    func canRetry(_ message: GradeyAIMessage) -> Bool {
        guard message.role == .assistant,
              message.status == .failed,
              let failed = lastFailedRequest,
              currentConversation?.id == failed.conversationID,
              status?.canSend == true
        else {
            return false
        }
        return message.createdAt >= failed.startedAt
    }

    func stop() {
        guard streamTask != nil || isStreaming else { return }
        activeStreamToken = nil
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.status == .streaming }) {
            messages[index].status = .cancelled
        }
        lastFailedRequest = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, let refreshed = try? await self.client.loadStatus() else { return }
            self.status = refreshed
        }
    }

    func delete(_ conversation: GradeyAIConversation) async {
        if currentConversation?.id == conversation.id { stop() }
        errorMessage = nil
        if conversation.id == draftConversationID {
            closeConversation()
            return
        }
        do {
            try await client.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if currentConversation?.id == conversation.id {
                currentConversation = nil
                messages = []
                lastFailedRequest = nil
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func deleteAll() async {
        stop()
        errorMessage = nil
        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            try await client.deleteAllConversations(schoolScope: schoolScope)
            conversations = []
            messages = []
            currentConversation = nil
            lastFailedRequest = nil
            draftConversationID = nil
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func refreshContext() async {
        guard !isRefreshingContext else { return }
        isRefreshingContext = true
        contextError = nil
        defer { isRefreshingContext = false }
        let result = await refreshContextAttempt()
        applyContextResult(result)
    }

    func reset() {
        stop()
        conversations = []
        messages = []
        status = nil
        draft = ""
        currentConversation = nil
        isLoading = false
        isOpeningConversation = false
        isRefreshingContext = false
        contextSnapshot = nil
        contextError = nil
        errorMessage = nil
        activeSchoolScope = nil
        lastFailedRequest = nil
        draftConversationID = nil
        reportedDailyLimit = 0
        reportedUsed = 0
        supportTier = nil
        serverStatus = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func startStream(
        conversation: GradeyAIConversation,
        text: String,
        clientMessageID: String,
        context: GradeyAIContextSnapshot
    ) async {
        let token = UUID()
        activeStreamToken = token
        isStreaming = true
        let startedAt = Date()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeStream(
                token: token,
                conversation: conversation,
                text: text,
                clientMessageID: clientMessageID,
                context: context,
                startedAt: startedAt
            )
        }
        streamTask = task
        await task.value
    }

    private func consumeStream(
        token: UUID,
        conversation: GradeyAIConversation,
        text: String,
        clientMessageID: String,
        context: GradeyAIContextSnapshot,
        startedAt: Date
    ) async {
        var assistantMessageID: String?
        var receivedTerminalEvent = false
        defer {
            if activeStreamToken == token {
                activeStreamToken = nil
                streamTask = nil
                isStreaming = false
            }
        }

        do {
            for try await event in client.streamReply(
                conversationID: conversation.id,
                clientMessageID: clientMessageID,
                text: text,
                context: context
            ) {
                guard activeStreamToken == token else { return }
                switch event {
                case .start(let messageID, let remaining):
                    assistantMessageID = messageID
                    updateRemaining(remaining)
                    messages.append(GradeyAIMessage(
                        id: messageID,
                        conversationID: conversation.id,
                        clientMessageID: nil,
                        role: .assistant,
                        content: "",
                        status: .streaming,
                        createdAt: Date(),
                        contextGeneratedAt: context.generatedAt
                    ))
                case .delta(let fragment):
                    if let assistantMessageID,
                       let index = messages.lastIndex(where: { $0.id == assistantMessageID }) {
                        messages[index].content += fragment
                    }
                case .done(_, let remaining, _, _, let persistedMessage):
                    receivedTerminalEvent = true
                    updateRemaining(remaining)
                    if let persistedMessage,
                       let index = messages.lastIndex(where: { $0.id == persistedMessage.id }) {
                        messages[index] = persistedMessage
                    } else if let persistedMessage {
                        assistantMessageID = persistedMessage.id
                        messages.append(persistedMessage)
                    } else if let assistantMessageID,
                              let index = messages.lastIndex(where: { $0.id == assistantMessageID }) {
                        messages[index].status = .complete
                    }
                    lastFailedRequest = nil
                    updateConversationAfterMessage(conversation, title: nil)
                case .error(let code, let message, let retryable, let remaining):
                    receivedTerminalEvent = true
                    if let remaining { updateRemaining(remaining) }
                    markAssistantFailed(
                        id: assistantMessageID,
                        conversationID: conversation.id,
                        contextGeneratedAt: context.generatedAt
                    )
                    let error = GradeyAIError.server(code: code, message: message, retryable: retryable)
                    errorMessage = userFacingMessage(for: error)
                    if retryable {
                        lastFailedRequest = FailedRequest(
                            conversationID: conversation.id,
                            clientMessageID: clientMessageID,
                            text: text,
                            startedAt: startedAt
                        )
                    }
                }
            }

            if !receivedTerminalEvent, activeStreamToken == token {
                throw GradeyAIError.invalidStream
            }
        } catch {
            guard activeStreamToken == token else { return }
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                if let assistantMessageID,
                   let index = messages.lastIndex(where: { $0.id == assistantMessageID }) {
                    messages[index].status = .cancelled
                }
                return
            }
            markAssistantFailed(
                id: assistantMessageID,
                conversationID: conversation.id,
                contextGeneratedAt: context.generatedAt
            )
            errorMessage = userFacingMessage(for: error)
            if (error as? GradeyAIError)?.isRetryable == true || error is URLError {
                lastFailedRequest = FailedRequest(
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    text: text,
                    startedAt: startedAt
                )
            }
        }
    }

    private func markAssistantFailed(id: String?, conversationID: String, contextGeneratedAt: Date) {
        if let id, let index = messages.lastIndex(where: { $0.id == id }) {
            messages[index].status = .failed
            return
        }
        messages.append(GradeyAIMessage(
            id: id ?? UUID().uuidString,
            conversationID: conversationID,
            clientMessageID: nil,
            role: .assistant,
            content: "",
            status: .failed,
            createdAt: Date(),
            contextGeneratedAt: contextGeneratedAt
        ))
    }

    private func loadStatusAttempt() async -> Result<GradeyAIStatus, Error> {
        do { return .success(try await client.loadStatus()) }
        catch { return .failure(error) }
    }

    private func loadConversationsAttempt(schoolScope: String) async -> Result<[GradeyAIConversation], Error> {
        do { return .success(try await client.listConversations(schoolScope: schoolScope)) }
        catch { return .failure(error) }
    }

    private func refreshContextAttempt() async -> Result<GradeyAIContextSnapshot, Error> {
        do { return .success(try await contextBuilder.refreshContext()) }
        catch { return .failure(error) }
    }

    private func applyContextResult(_ result: Result<GradeyAIContextSnapshot, Error>) {
        switch result {
        case .success(let snapshot):
            contextSnapshot = snapshot
            contextError = Self.contextWarning(for: snapshot)
        case .failure(let error):
            contextError = userFacingMessage(for: error)
        }
    }

    private func ingestStatus(_ loadedStatus: GradeyAIStatus) {
        serverStatus = loadedStatus
        reportedDailyLimit = max(loadedStatus.dailyLimit, 0)
        reportedUsed = max(
            loadedStatus.dailyUsed,
            max(0, loadedStatus.dailyLimit - loadedStatus.remaining)
        )
        recomposeStatus()
    }

    private func recomposeStatus() {
        guard var loadedStatus = serverStatus else { return }
        let dailyLimit = supportTier.map { SupportTipCatalog.dailyLimit(for: $0) } ?? reportedDailyLimit
        loadedStatus.dailyLimit = dailyLimit
        loadedStatus.dailyUsed = reportedUsed
        loadedStatus.remaining = max(0, dailyLimit - reportedUsed)
        status = loadedStatus
    }

    private func updateRemaining(_ remaining: Int) {
        reportedUsed = max(0, reportedDailyLimit - remaining)
        recomposeStatus()
    }

    private func updateConversationAfterMessage(_ conversation: GradeyAIConversation, title: String?) {
        var updated = currentConversation?.id == conversation.id ? currentConversation! : conversation
        if let title,
           updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || updated.title == "New chat"
            || updated.title == AppL10n.string("gradey.ai.newChat") {
            updated.title = title
        }
        updated.updatedAt = Date()
        updated.lastMessageAt = updated.updatedAt
        currentConversation = updated
        upsert(updated)
    }

    private func upsert(_ conversation: GradeyAIConversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
        conversations.sort { first, second in
            (first.lastMessageAt ?? first.updatedAt) > (second.lastMessageAt ?? second.updatedAt)
        }
    }

    private static func title(from text: String) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(60))
    }

    private static func contextWarning(for snapshot: GradeyAIContextSnapshot) -> String? {
        guard !snapshot.unavailableSections.isEmpty else { return nil }
        let sections = snapshot.unavailableSections.map(\.rawValue).joined(separator: ", ")
        return "Some school context is unavailable or stale: \(sections)."
    }

    private func userFacingMessage(for error: Error) -> String {
        if error is DecodingError {
            return AppL10n.string("gradey.account.error.invalidResponse")
        }
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription,
           !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }
}

private struct FailedRequest {
    let conversationID: String
    let clientMessageID: String
    let text: String
    let startedAt: Date
}
