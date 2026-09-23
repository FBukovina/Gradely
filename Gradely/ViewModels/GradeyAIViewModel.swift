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
    private(set) var contextSelection = GradeyAIContextSelection()
    private(set) var isPreparingReply = false
    private(set) var isRecoveringRequest = false
    var pendingRecoveryMessage: String?

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
        return !isStreaming && !isPreparingReply && !isRecoveringRequest
            && !trimmed.isEmpty
            && trimmed.count <= 2_000
            && contextSnapshot != nil
            && canAffordSelectedAction
            && isConversationPurposeCompatible
    }

    var canStartNewChat: Bool {
        status?.enabled == true
            && status?.consentRequired == false
            && (status?.remaining ?? 0) > 0
            && !isStreaming && !isPreparingReply && !isRecoveringRequest
    }

    var starterPrompts: [String] {
        switch contextSelection.action {
        case .reply: return [AppL10n.string("gradey.ai.prompt.general1"), AppL10n.string("gradey.ai.prompt.general2")]
        default: return [AppL10n.string(String.LocalizationValue("gradey.ai.prompt." + contextSelection.action.rawValue))]
        }
    }

    private let client: any GradeyAIClient
    private let contextBuilder: any GradeyAIContextBuilding
    private let pendingDefaults: UserDefaults
    @ObservationIgnored private var lifecycleGeneration = UUID()
    @ObservationIgnored private var pendingRequests: [String: GradeyAIPendingRequest] = [:]
    private var pendingRequest: GradeyAIPendingRequest? {
        guard let scope = try? contextBuilder.currentSchoolScope() else { return nil }
        return pendingRequests[scope]
    }
    private static let pendingStorageKey = "gradey.ai.pendingRequest.v1"
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var activeStreamToken: UUID?
    @ObservationIgnored private var activeSchoolScope: String?
    @ObservationIgnored private var lastFailedRequest: FailedRequest?
    @ObservationIgnored private var draftConversationID: String?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var supportTier: SupportTier?
    @ObservationIgnored private var serverStatus: GradeyAIStatus?

    var isDraftChat: Bool {
        guard let draftConversationID, let currentConversation else { return false }
        return currentConversation.id == draftConversationID
    }

    init(client: any GradeyAIClient, contextBuilder: any GradeyAIContextBuilding, pendingDefaults: UserDefaults = .standard) {
        self.client = client
        self.contextBuilder = contextBuilder
        self.pendingDefaults = pendingDefaults
        if let data = pendingDefaults.data(forKey: Self.pendingStorageKey) {
            if let stored = try? JSONDecoder().decode([String: GradeyAIPendingRequest].self, from: data) {
                pendingRequests = stored
            } else if let legacy = try? JSONDecoder().decode(GradeyAIPendingRequest.self, from: data) {
                pendingRequests[legacy.schoolScope] = legacy
            }
        }
    }

    var selectedActionCost: Int {
        guard let compute = status?.compute else { return contextSelection.action == .reply ? 1 : Int.max }
        guard compute.schemaVersion == 1, !compute.catalogVersion.isEmpty else { return Int.max }
        return compute.actions.first { $0.id == contextSelection.action.rawValue && $0.available }?.cost ?? Int.max
    }
    var canAffordSelectedAction: Bool {
        guard status?.enabled == true, status?.consentRequired == false else { return false }
        return selectedActionCost > 0 && (status?.remaining ?? 0) >= selectedActionCost
    }
    var isConversationPurposeCompatible: Bool {
        guard let conversation = currentConversation, !isDraftChat else { return true }
        guard let selectionID = conversation.contextSelectionID else { return contextSelection.action == .reply }
        return selectionID == contextSelection.identifier || (selectionID == conversation.schoolScope && contextSelection.action == .reply)
    }
    var availableSubjects: [GradeyAISubjectContext] { contextBuilder.availableSubjects() }
    var availableEvents: [GradeyAIEventContext] { contextBuilder.availableEvents() }
    var selectedContextName: String? {
        if contextSelection.action == .subjectHelp { return contextSnapshot?.subjects.first?.name }
        if contextSelection.action == .testPreparation { return contextSnapshot?.events?.first?.title }
        return nil
    }
    var selectedSharingSummary: String {
        let snapshot = contextSnapshot
        if contextSelection.action == .reply { return AppL10n.string("gradey.ai.context.none") }
        return String.localizedStringWithFormat(AppL10n.string("gradey.ai.context.selectionSummary"),
            snapshot?.subjects.count ?? 0, snapshot?.timetable.count ?? 0, snapshot?.events?.count ?? 0)
    }

    var localTomorrowSummary: String? {
        guard contextSelection.action == .tomorrow, let snapshot = contextSnapshot else { return nil }
        let lessons = snapshot.timetable.map { lesson in
            let cancellation = lesson.changeKind == .cancelled ? " (" + AppL10n.string("timetable.change.canceled") + ")" : ""
            return "\(lesson.beginsAt)–\(lesson.endsAt)  \(lesson.subject)" + cancellation
        }
        let events = (snapshot.events ?? []).map(\.title)
        let lines = lessons + events
        return lines.isEmpty ? AppL10n.string("gradey.ai.context.tomorrowEmpty") : lines.joined(separator: "\n")
    }

    func selectAction(_ action: GradeyAIAction, subjectID: String? = nil, eventID: UUID? = nil, includeNotes: Bool = false, prompt: String? = nil, weekContaining: Date? = nil) async {
        stop()
        lifecycleGeneration = UUID()
        isPreparingReply = false
        isRefreshingContext = false
        isRecoveringRequest = false
        contextSelection = GradeyAIContextSelection(action: action, subjectID: subjectID, eventID: eventID, includeNotes: includeNotes,
            weekStart: action == .weekSummary ? GradeyAIContextBuilder.weekStart(containing: weekContaining ?? Date()) : nil)
        contextSnapshot = nil
        contextError = nil
        beginDraftChat()
        if let prompt { draft = prompt }
        await refreshContext()
    }

    private func matchesScope(_ schoolScope: String, generation: UUID) -> Bool {
        lifecycleGeneration == generation && (try? contextBuilder.currentSchoolScope()) == schoolScope
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

    func refreshStatus(refreshEntitlement: Bool = false) async {
        let generation = lifecycleGeneration
        let scope = try? contextBuilder.currentSchoolScope()
        if let loadedStatus = try? await client.loadStatus(refreshEntitlement: refreshEntitlement),
           generation == lifecycleGeneration, scope == (try? contextBuilder.currentSchoolScope()) {
            ingestStatus(loadedStatus)
        }
    }

    func applySupportTier(_ tier: SupportTier, catalogLoaded: Bool) {
        guard catalogLoaded || tier != .none else { return }
        supportTier = tier
        // StoreKit metadata is not authorization to mint Compute. The backend
        // verifies entitlements when refreshStatus(refreshEntitlement: true) runs.
    }

    private func performBootstrap() async {
        let generation = lifecycleGeneration
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
                lastFailedRequest = nil
                isOpeningConversation = false
            }
            activeSchoolScope = schoolScope
            if contextSnapshot == nil {
                contextSnapshot = try contextBuilder.cachedContext(for: contextSelection)
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
                guard matchesScope(schoolScope, generation: generation) else { return }
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
                        guard matchesScope(schoolScope, generation: generation) else { return }
                        conversations = loadedConversations
                        if let currentConversation,
                           let refreshed = loadedConversations.first(where: { $0.id == currentConversation.id }) {
                            self.currentConversation = refreshed
                        }
                    case .failure(let error):
                        guard matchesScope(schoolScope, generation: generation) else { return }
                        if conversations.isEmpty, currentConversation == nil {
                            errorMessage = userFacingMessage(for: error)
                        }
                    }
                }
            case .failure(let error):
                guard matchesScope(schoolScope, generation: generation) else { return }
                isLoading = false
                if status == nil {
                    errorMessage = userFacingMessage(for: error)
                }
            }

            let contextResult = await contextAttempt
            guard matchesScope(schoolScope, generation: generation) else { return }
            applyContextResult(contextResult)
            await recoverPendingRequest()
        } catch {
            guard generation == lifecycleGeneration else { return }
            isLoading = false
            errorMessage = userFacingMessage(for: error)
            contextError = userFacingMessage(for: error)
        }
    }

    func acceptConsent() async {
        guard let scope = try? contextBuilder.currentSchoolScope() else { return }
        let generation = lifecycleGeneration
        errorMessage = nil
        isLoading = true
        defer { if generation == lifecycleGeneration { isLoading = false } }
        do {
            _ = try await client.acceptConsent()
            guard matchesScope(scope, generation: generation) else { return }
            let loadedStatus = try await client.loadStatus()
            guard matchesScope(scope, generation: generation) else { return }
            ingestStatus(loadedStatus)
            if let status, !status.consentRequired {
                let loaded = try await client.listConversations(schoolScope: scope)
                guard matchesScope(scope, generation: generation) else { return }
                conversations = loaded
            }
        } catch {
            guard matchesScope(scope, generation: generation) else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    func revokeConsent() async {
        stop()
        invalidatePendingOperations()
        guard let scope = try? contextBuilder.currentSchoolScope() else { return }
        let generation = lifecycleGeneration
        errorMessage = nil
        isLoading = true
        defer { if generation == lifecycleGeneration { isLoading = false } }
        do {
            try await client.revokeConsent()
            guard matchesScope(scope, generation: generation) else { return }
            clearPendingRequest()
            conversations = []
            messages = []
            currentConversation = nil
            if var currentStatus = serverStatus ?? status {
                currentStatus.consentRequired = true
                ingestStatus(currentStatus)
            }
        } catch {
            guard matchesScope(scope, generation: generation) else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    func beginDraftChat() {
        stop()
        invalidatePendingOperations()
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
                lastMessageAt: nil,
                contextSelectionID: contextSelection.identifier
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
        let generation = lifecycleGeneration
        let expectedScope = try? contextBuilder.currentSchoolScope()
        errorMessage = nil
        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            let selectionID = contextSelection.identifier
            let conversation = try await client.createConversation(
                schoolScope: schoolScope,
                title: title,
                contextSelectionID: selectionID
            )
            guard matchesScope(schoolScope, generation: generation), selectionID == contextSelection.identifier else { return nil }
            upsert(conversation)
            currentConversation = conversation
            draftConversationID = nil
            if replacingCurrentChat {
                messages = []
                lastFailedRequest = nil
            }
            return conversation
        } catch {
            guard generation == lifecycleGeneration, expectedScope == (try? contextBuilder.currentSchoolScope()) else { return nil }
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    func open(_ conversation: GradeyAIConversation) async {
        stop()
        invalidatePendingOperations()
        let generation = lifecycleGeneration
        errorMessage = nil
        draftConversationID = nil
        currentConversation = conversation
        messages = []
        lastFailedRequest = nil
        isOpeningConversation = true
        defer { if generation == lifecycleGeneration { isOpeningConversation = false } }
        do {
            let detail = try await client.loadConversation(id: conversation.id)
            guard matchesScope(conversation.schoolScope, generation: generation), currentConversation?.id == conversation.id else { return }
            currentConversation = detail.conversation
            messages = detail.messages
            upsert(detail.conversation)
        } catch {
            guard matchesScope(conversation.schoolScope, generation: generation), currentConversation?.id == conversation.id else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    func closeConversation() {
        stop()
        invalidatePendingOperations()
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
        guard !isStreaming, !isPreparingReply, !isRecoveringRequest else { return }
        let text = proposedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else { errorMessage = GradeyAIError.invalidPrompt.localizedDescription; return }
        guard status?.enabled == true else { errorMessage = AppL10n.string("gradey.ai.compute.unavailable"); return }
        guard status?.consentRequired == false else { errorMessage = AppL10n.string("gradey.ai.compute.consentRequired"); return }
        guard canAffordSelectedAction else { errorMessage = AppL10n.string("gradey.ai.limit.reached"); return }
        guard isConversationPurposeCompatible else { errorMessage = AppL10n.string("gradey.ai.context.newPurpose"); return }
        guard let scope = try? contextBuilder.currentSchoolScope() else { return }
        let generation = lifecycleGeneration, selection = contextSelection
        isPreparingReply = true
        defer { if generation == lifecycleGeneration { isPreparingReply = false } }
        if pendingRequest != nil {
            await recoverPendingRequest()
            guard pendingRequest == nil else { errorMessage = AppL10n.string("gradey.ai.compute.pending"); return }
        }
        if contextSnapshot == nil { await refreshContext() }
        guard matchesScope(scope, generation: generation), selection == contextSelection,
              let snapshot = contextSnapshot, snapshot.schoolScope == scope else { return }
        if selection.action == .subjectHelp && selection.subjectID == nil || selection.action == .testPreparation && selection.eventID == nil {
            errorMessage = AppL10n.string("gradey.ai.context.chooseItem"); return
        }
        let clientMessageID = UUID().uuidString
        var conversation = currentConversation
        if conversation == nil || isDraftChat {
            conversation = await create(title: Self.title(from: text), replacingCurrentChat: false)
        }
        guard matchesScope(scope, generation: generation), selection == contextSelection, let conversation else { return }
        draft = ""
        errorMessage = nil
        messages.append(GradeyAIMessage(id: clientMessageID, conversationID: conversation.id, clientMessageID: clientMessageID,
                                       role: .user, content: text, status: .complete, createdAt: Date(), contextGeneratedAt: snapshot.generatedAt))
        lastFailedRequest = nil
        updateConversationAfterMessage(conversation, title: Self.title(from: text))
        await startStream(conversation: conversation, text: text, clientMessageID: clientMessageID, context: snapshot)
    }

    func retry() async {
        guard !isStreaming, !isPreparingReply, !isRecoveringRequest, let failed = lastFailedRequest,
              let conversation = currentConversation, conversation.id == failed.conversationID,
              (try? contextBuilder.currentSchoolScope()) == failed.request.context.schoolScope else { return }
        let generation = lifecycleGeneration
        isPreparingReply = true
        defer { if generation == lifecycleGeneration { isPreparingReply = false } }
        var retryRequest = failed.request
        // Query first: a disconnected completed request can be restored for free,
        // including when its successful reservation consumed the last Compute.
        if let pending = pendingRequest {
            do {
                let recovery = try await client.recoverRequest(pending)
                guard matchesScope(failed.request.context.schoolScope, generation: generation), lastFailedRequest?.request == failed.request else { return }
                if let status = recovery.status { ingestStatus(status) }
                if recovery.state == "complete", let message = recovery.message {
                    restoreRecoveredMessage(message); clearPendingRequest(); lastFailedRequest = nil; return
                }
                if recovery.state == "pending" {
                    pendingRecoveryMessage = AppL10n.string("gradey.ai.compute.pending"); return
                }
                if recovery.state == "failed" || recovery.state == "cancelled" {
                    // A settled attempt is immutable. The explicit Retry action
                    // starts a new request only after the server confirms it ended.
                    let newID = UUID().uuidString
                    retryRequest = GradeyAIReplyRequest(conversationID: failed.conversationID, clientMessageID: newID,
                        text: failed.request.text, context: failed.request.context, actionID: failed.request.actionID,
                        contextSelectionID: failed.request.contextSelectionID, catalogVersion: status?.compute?.catalogVersion,
                        maximumComputeCost: failed.request.maximumComputeCost)
                    clearPendingRequest()
                }
            } catch {
                guard matchesScope(failed.request.context.schoolScope, generation: generation) else { return }
                errorMessage = userFacingMessage(for: error); return
            }
        }
        messages.removeAll { $0.role == .assistant && $0.status == .failed && $0.createdAt >= failed.startedAt }
        if retryRequest.clientMessageID != failed.clientMessageID {
            messages.append(GradeyAIMessage(id: retryRequest.clientMessageID, conversationID: conversation.id,
                clientMessageID: retryRequest.clientMessageID, role: .user, content: retryRequest.text, status: .complete,
                createdAt: Date(), contextGeneratedAt: retryRequest.context.generatedAt))
        }
        errorMessage = nil
        await startStream(conversation: conversation, request: retryRequest)
    }

    func canRetry(_ message: GradeyAIMessage) -> Bool {
        guard message.role == .assistant,
              message.status == .failed,
              let failed = lastFailedRequest,
              currentConversation?.id == failed.conversationID,
              status?.enabled == true, status?.consentRequired == false
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
        if pendingRequest != nil { pendingRecoveryMessage = AppL10n.string("gradey.ai.compute.pending") }
    }

    func delete(_ conversation: GradeyAIConversation) async {
        let generation = lifecycleGeneration
        if currentConversation?.id == conversation.id { stop() }
        errorMessage = nil
        if conversation.id == draftConversationID {
            closeConversation()
            return
        }
        do {
            try await client.deleteConversation(id: conversation.id)
            guard matchesScope(conversation.schoolScope, generation: generation) else { return }
            if pendingRequest?.conversationID == conversation.id { clearPendingRequest() }
            conversations.removeAll { $0.id == conversation.id }
            if currentConversation?.id == conversation.id {
                currentConversation = nil
                messages = []
                lastFailedRequest = nil
            }
        } catch {
            guard matchesScope(conversation.schoolScope, generation: generation) else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    func deleteAll() async {
        stop()
        invalidatePendingOperations()
        guard let schoolScope = try? contextBuilder.currentSchoolScope() else { return }
        let generation = lifecycleGeneration
        errorMessage = nil
        do {
            try await client.deleteAllConversations(schoolScope: schoolScope)
            guard matchesScope(schoolScope, generation: generation) else { return }
            clearPendingRequest()
            conversations = []
            messages = []
            currentConversation = nil
            lastFailedRequest = nil
            draftConversationID = nil
        } catch {
            guard matchesScope(schoolScope, generation: generation) else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    func refreshContext() async {
        guard !isRefreshingContext, let scope = try? contextBuilder.currentSchoolScope() else { return }
        let generation = lifecycleGeneration, selection = contextSelection
        isRefreshingContext = true
        contextError = nil
        defer { if generation == lifecycleGeneration { isRefreshingContext = false } }
        let result = await refreshContextAttempt()
        guard matchesScope(scope, generation: generation), contextSelection == selection else { return }
        applyContextResult(result)
    }

    func reset() {
        lifecycleGeneration = UUID()
        bootstrapTask?.cancel()
        bootstrapTask = nil
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
        supportTier = nil
        serverStatus = nil
        contextSelection = GradeyAIContextSelection()
        isPreparingReply = false
        isRecoveringRequest = false
        pendingRecoveryMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func invalidatePendingOperations() {
        lifecycleGeneration = UUID()
        isPreparingReply = false
        isRefreshingContext = false
        isRecoveringRequest = false
    }

    private func startStream(conversation: GradeyAIConversation, text: String, clientMessageID: String, context: GradeyAIContextSnapshot) async {
        let request = GradeyAIReplyRequest(conversationID: conversation.id, clientMessageID: clientMessageID,
            text: text, context: context, actionID: contextSelection.action,
            contextSelectionID: conversation.contextSelectionID ?? context.schoolScope,
            catalogVersion: status?.compute?.catalogVersion, maximumComputeCost: selectedActionCost)
        await startStream(conversation: conversation, request: request)
    }

    private func startStream(conversation: GradeyAIConversation, request: GradeyAIReplyRequest) async {
        let token = UUID()
        activeStreamToken = token
        isStreaming = true
        pendingRecoveryMessage = nil
        savePendingRequest(request)
        let startedAt = Date()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeStream(token: token, conversation: conversation, request: request, startedAt: startedAt)
        }
        streamTask = task
        await task.value
        if activeSchoolScope == request.context.schoolScope { await refreshStatus() }
    }

    private func consumeStream(
        token: UUID,
        conversation: GradeyAIConversation,
        request: GradeyAIReplyRequest,
        startedAt: Date
    ) async {
        let context = request.context
        var assistantMessageID: String?
        var receivedTerminalEvent = false
        defer {
            if activeStreamToken == token {
                if pendingRequest?.clientMessageID == request.clientMessageID, pendingRecoveryMessage == nil {
                    pendingRecoveryMessage = AppL10n.string("gradey.ai.compute.recoveryUnavailable")
                }
                activeStreamToken = nil
                streamTask = nil
                isStreaming = false
            }
        }

        do {
            for try await event in client.streamReply(request: request) {
                guard activeStreamToken == token, (try? contextBuilder.currentSchoolScope()) == context.schoolScope else { return }
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
                    clearPendingRequest()
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
                    if code == "catalog_changed" || code == "price_changed" {
                        clearPendingRequest()
                        lastFailedRequest = nil
                        draft = request.text
                        errorMessage = AppL10n.string("gradey.ai.compute.priceChanged")
                    } else if retryable {
                        lastFailedRequest = FailedRequest(request: request, startedAt: startedAt)
                    }
                }
            }

            if !receivedTerminalEvent, activeStreamToken == token {
                throw GradeyAIError.invalidStream
            }
        } catch {
            guard activeStreamToken == token, (try? contextBuilder.currentSchoolScope()) == context.schoolScope else { return }
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
                lastFailedRequest = FailedRequest(request: request, startedAt: startedAt)
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
        do { return .success(try await contextBuilder.refreshContext(for: contextSelection)) }
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
        status = loadedStatus
    }

    private func updateRemaining(_ remaining: Int) {
        status?.remaining = max(0, remaining)
        status?.compute?.remaining = max(0, remaining)
        serverStatus = status
    }

    private func savePendingRequest(_ request: GradeyAIReplyRequest) {
        let pending = GradeyAIPendingRequest(conversationID: request.conversationID, clientMessageID: request.clientMessageID,
            schoolScope: request.context.schoolScope, contextSelectionID: request.contextSelectionID, payloadHash: request.payloadHash)
        pendingRequests[pending.schoolScope] = pending
        persistPendingRequests()
    }

    private func clearPendingRequest() {
        if let scope = try? contextBuilder.currentSchoolScope() { pendingRequests[scope] = nil }
        pendingRecoveryMessage = nil
        persistPendingRequests()
    }

    private func persistPendingRequests() {
        if pendingRequests.isEmpty { pendingDefaults.removeObject(forKey: Self.pendingStorageKey) }
        else if let data = try? JSONEncoder().encode(pendingRequests) { pendingDefaults.set(data, forKey: Self.pendingStorageKey) }
    }

    func recoverPendingRequest() async {
        guard !isStreaming, !isRecoveringRequest, status?.consentRequired == false,
              let pending = pendingRequest, let scope = try? contextBuilder.currentSchoolScope(), pending.schoolScope == scope else { return }
        let generation = lifecycleGeneration
        isRecoveringRequest = true
        defer { if generation == lifecycleGeneration { isRecoveringRequest = false } }
        do {
            let recovery = try await client.recoverRequest(pending)
            guard matchesScope(scope, generation: generation), pendingRequest == pending else { return }
            if let status = recovery.status { ingestStatus(status) }
            if recovery.state == "pending" {
                pendingRecoveryMessage = AppL10n.string("gradey.ai.compute.pending")
                return
            }
            if let message = recovery.message, currentConversation?.id == pending.conversationID { restoreRecoveredMessage(message) }
            clearPendingRequest()
        } catch {
            guard matchesScope(scope, generation: generation) else { return }
            pendingRecoveryMessage = AppL10n.string("gradey.ai.compute.recoveryUnavailable")
        }
    }

    private func restoreRecoveredMessage(_ message: GradeyAIMessage) {
        let userIndex = pendingRequest.flatMap { pending in messages.firstIndex { $0.clientMessageID == pending.clientMessageID && $0.role == .user } }
        let supersededIDs = userIndex.map { index in Set(messages.dropFirst(index + 1).prefix { $0.role != .user }.filter { $0.role == .assistant }.map(\.id)) } ?? []
        messages.removeAll { $0.id == message.id || supersededIDs.contains($0.id) }
        messages.append(message)
        errorMessage = nil
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
        let affected = Set(snapshot.unavailableSections.map(\.rawValue) + (snapshot.sourceFreshness ?? []).filter(\.isStale).map(\.section))
        guard !affected.isEmpty else { return snapshot.isStale ? AppL10n.string("gradey.ai.context.partial") : nil }
        let sections = Set(affected.map { section in
            GradeyAIContextSection(rawValue: section)?.localizedName
                ?? AppL10n.string("gradey.ai.context.section.other")
        }).sorted().joined(separator: ", ")
        return String(format: AppL10n.string("gradey.ai.context.stale"), sections)
    }

    private func userFacingMessage(for error: Error) -> String {
        if error is DecodingError {
            return AppL10n.string("gradey.ai.error.couldNotComplete")
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
    let request: GradeyAIReplyRequest
    let startedAt: Date
    var conversationID: String { request.conversationID }
    var clientMessageID: String { request.clientMessageID }
}
