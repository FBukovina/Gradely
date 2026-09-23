import Foundation
#if !os(macOS)
import GradelyWatchShared
#endif
#if canImport(WatchConnectivity) && !os(macOS)
import WatchConnectivity
#endif

@MainActor
protocol WatchSyncing: AnyObject {
    func start()
    func update(session: StoredSession?)
    func update(user: UserResponse?)
    #if !os(macOS)
    func update(timetable: GradelyWatchTimetable?)
    func update(supportTier: GradelyWatchSupportTier)
    func configureAIRelay(
        client: any GradeyAIClient,
        contextBuilder: any GradeyAIContextBuilding,
        supportProvider: any SupportTipProviding
    )
    #endif
    func publishSignedOut()
}

#if canImport(WatchConnectivity) && !os(macOS)
@MainActor
final class LiveWatchSyncService: NSObject, WatchSyncing {
    private var session: WCSession?
    private var activationState: WCSessionActivationState = .notActivated
    private var auth: GradelyWatchAuth?
    private var user: GradelyWatchUser?
    private var timetable: GradelyWatchTimetable?
    private var supportTier: GradelyWatchSupportTier = .none
    private var hasPendingPublish = false
    private var aiClient: (any GradeyAIClient)?
    private var contextBuilder: (any GradeyAIContextBuilding)?
    private var supportProvider: (any SupportTipProviding)?
    private var watchConversation: GradeyAIConversation?
    private var relayGeneration = UUID()
    private var relaySchoolScope: SchoolDataScope?
    private var activeAIRequestID: String?
    private var aiTask: Task<Void, Never>?

    func start() {
        guard WCSession.isSupported() else { return }

        let wcSession = WCSession.default
        session = wcSession
        wcSession.delegate = self
        wcSession.activate()
    }

    func update(session: StoredSession?) {
        let nextScope = session.map(SchoolDataScope.init(session:))
        if nextScope != relaySchoolScope {
            invalidateAIRelay()
            relaySchoolScope = nextScope
        }
        auth = session.map(WatchPayloadBuilder.auth)
        publishCurrentPayload()
    }

    func update(user: UserResponse?) {
        self.user = user.map(WatchPayloadBuilder.user)
        publishCurrentPayload()
    }

    func update(timetable: GradelyWatchTimetable?) {
        self.timetable = timetable
        publishCurrentPayload()
    }

    func update(supportTier: GradelyWatchSupportTier) {
        self.supportTier = supportTier
        publishCurrentPayload()
    }

    func configureAIRelay(
        client: any GradeyAIClient,
        contextBuilder: any GradeyAIContextBuilding,
        supportProvider: any SupportTipProviding
    ) {
        invalidateAIRelay()
        self.aiClient = client
        self.contextBuilder = contextBuilder
        self.supportProvider = supportProvider
        Task { await self.refreshSupportTier() }
    }

    func publishSignedOut() {
        auth = nil
        user = nil
        timetable = nil
        supportTier = .none
        relaySchoolScope = nil
        invalidateAIRelay()
        publish(payload: .signedOut())
    }

    private var currentPayload: GradelyWatchSyncPayload {
        guard let auth else {
            return .signedOut()
        }

        return GradelyWatchSyncPayload(
            generatedAt: Date(),
            isSignedIn: true,
            auth: auth,
            user: user,
            timetable: timetable,
            supportTier: supportTier
        )
    }

    private func publishCurrentPayload() {
        publish(payload: currentPayload)
    }

    private func publish(payload: GradelyWatchSyncPayload) {
        guard let session else { return }
        guard activationState == .activated else {
            hasPendingPublish = true
            return
        }

        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: payload) else {
            return
        }

        try? session.updateApplicationContext(envelope)
        session.transferUserInfo(envelope)

        if session.isReachable {
            session.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleActivation(state: WCSessionActivationState) {
        activationState = state
        guard state == .activated, hasPendingPublish else { return }

        hasPendingPublish = false
        publishCurrentPayload()
    }

    private func replyToSyncRequest(_ replyHandler: ([String: Any]) -> Void) {
        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: currentPayload) else {
            replyHandler([:])
            return
        }

        replyHandler(envelope)
    }

    private func refreshSupportTier() async {
        guard let supportProvider else { return }
        let entitlement = await supportProvider.currentEntitlement()
        update(supportTier: WatchPayloadBuilder.supportTier(from: entitlement))
    }

    private func handlePurchaseRefreshRequest(_ replyHandler: @escaping ([String: Any]) -> Void) async {
        if let supportProvider {
            do {
                let entitlement = try await supportProvider.restorePurchases()
                update(supportTier: WatchPayloadBuilder.supportTier(from: entitlement))
            } catch {
                await refreshSupportTier()
            }
        }
        replyToSyncRequest(replyHandler)
    }

    /// The Watch has no explicit school-context picker, so it always starts or
    /// continues a general chat with no attached school records.
    func handleAIRequest(
        _ request: GradelyWatchAIStreamRequest,
        replyHandler: @escaping ([String: Any]) -> Void
    ) async {
        aiTask?.cancel()
        aiTask = nil
        relayGeneration = UUID()
        let generation = relayGeneration
        activeAIRequestID = request.requestID
        var handedOffToStream = false
        defer {
            if !handedOffToStream, relayGeneration == generation { activeAIRequestID = nil }
        }

        guard let aiClient, let contextBuilder else {
            reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.notConfigured, message: "Gradey AI is not available."))
            return
        }

        do {
            let schoolScope = try contextBuilder.currentSchoolScope()
            let selection = GradeyAIContextSelection(action: .reply)
            let status = try await aiClient.loadStatus()
            try validateAIRelay(scope: schoolScope, generation: generation, requestID: request.requestID)
            guard !status.consentRequired else {
                reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.consentRequired, message: "Enable Gradey AI on iPhone."))
                return
            }
            guard status.enabled else {
                reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.notConfigured, message: "Gradey AI is not available."))
                return
            }

            let cost: Int
            if let compute = status.compute {
                guard compute.schemaVersion == 1, !compute.catalogVersion.isEmpty,
                      let action = compute.actions.first(where: { $0.id == GradeyAIAction.reply.rawValue && $0.available }),
                      action.cost > 0 else {
                    reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.notConfigured, message: "Gradey AI is not available."))
                    return
                }
                guard ["standard", "plus"].contains(compute.supportTier) else {
                    reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.supporterRequired, message: "Subscribe in Gradey on iPhone."))
                    return
                }
                cost = action.cost
            } else {
                // Keep the old relay contract usable against a legacy backend;
                // local StoreKit metadata never changes the server's balance.
                let entitlement = await supportProvider?.currentEntitlement() ?? .none
                try validateAIRelay(scope: schoolScope, generation: generation, requestID: request.requestID)
                guard entitlement.tier != .none else {
                    reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.supporterRequired, message: "Subscribe in Gradey on iPhone."))
                    return
                }
                cost = 1
            }
            guard status.remaining >= cost else {
                reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.quotaExceeded, message: "Daily Gradey AI limit reached."))
                return
            }

            var conversation: GradeyAIConversation?
            var createdConversation = false
            if let existingID = request.conversationID ?? watchConversation?.id {
                if let cached = watchConversation, cached.id == existingID {
                    conversation = cached
                } else {
                    conversation = try? await aiClient.loadConversation(id: existingID).conversation
                    try validateAIRelay(scope: schoolScope, generation: generation, requestID: request.requestID)
                }
            }
            // Legacy chats attached whole school records. A fresh purpose-scoped
            // chat avoids carrying those records forward through chat history.
            if conversation?.schoolScope != schoolScope || conversation?.contextSelectionID != selection.identifier {
                conversation = nil
            }
            if conversation == nil {
                createdConversation = true
                conversation = try await aiClient.createConversation(schoolScope: schoolScope, title: "Watch", contextSelectionID: selection.identifier)
                try validateAIRelay(scope: schoolScope, generation: generation, requestID: request.requestID)
            }
            guard let conversation, conversation.schoolScope == schoolScope,
                  conversation.contextSelectionID == selection.identifier
                    || (createdConversation && status.compute == nil && conversation.contextSelectionID == nil) else {
                throw GradeyAIError.invalidResponse
            }
            let context = GradeyAIContextBuilder.emptyContext(schoolScope: schoolScope, now: Date())
            let frozen = GradeyAIReplyRequest(conversationID: conversation.id, clientMessageID: request.clientMessageID,
                text: request.text, context: context, actionID: .reply, contextSelectionID: selection.identifier,
                catalogVersion: status.compute?.catalogVersion, maximumComputeCost: cost)
            try validateAIRelay(scope: schoolScope, generation: generation, requestID: request.requestID)
            watchConversation = conversation
            reply(replyHandler, .success(conversationID: conversation.id))
            handedOffToStream = true
            aiTask = Task { [weak self] in
                await self?.stream(requestID: request.requestID, frozen: frozen, client: aiClient, generation: generation)
            }
        } catch is CancellationError {
            reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.cancelled, message: "Cancelled. Open Gradey on iPhone and try again."))
        } catch let error as GradeyAIContextError where error == .noSchoolAccount {
            reply(replyHandler, .failure(code: GradelyWatchAIErrorCode.noSchoolAccount, message: "Open Gradey on iPhone and sign in to school."))
        } catch {
            reply(replyHandler, .failure(code: "failed", message: error.localizedDescription))
        }
    }

    private func stream(requestID: String, frozen: GradeyAIReplyRequest, client: any GradeyAIClient, generation: UUID) async {
        do {
            try validateAIRelay(scope: frozen.context.schoolScope, generation: generation, requestID: requestID)
            for try await event in client.streamReply(request: frozen) {
                try validateAIRelay(scope: frozen.context.schoolScope, generation: generation, requestID: requestID)
                sendAIEvent(Self.watchEvent(from: event, requestID: requestID, conversationID: frozen.conversationID))
            }
        } catch {
            // A request for the previous student must never publish events after
            // the Watch has switched to a new school session.
            guard relayGeneration == generation, activeAIRequestID == requestID,
                  (try? contextBuilder?.currentSchoolScope()) == frozen.context.schoolScope else { return }
            sendAIEvent(GradelyWatchAIStreamEvent(requestID: requestID, conversationID: frozen.conversationID, kind: .failed,
                errorCode: error is CancellationError ? GradelyWatchAIErrorCode.cancelled : "failed",
                errorMessage: error is CancellationError ? "Cancelled." : error.localizedDescription))
        }
        if relayGeneration == generation, activeAIRequestID == requestID {
            activeAIRequestID = nil
            aiTask = nil
        }
    }

    private func validateAIRelay(scope: String, generation: UUID, requestID: String) throws {
        try Task.checkCancellation()
        guard relayGeneration == generation, activeAIRequestID == requestID,
              let contextBuilder, try contextBuilder.currentSchoolScope() == scope else { throw CancellationError() }
    }

    private func invalidateAIRelay() {
        relayGeneration = UUID()
        watchConversation = nil
        aiTask?.cancel()
        aiTask = nil
        activeAIRequestID = nil
    }

    private func handleAICancel(_ cancel: GradelyWatchAICancel) {
        guard cancel.requestID == activeAIRequestID else { return }
        relayGeneration = UUID()
        aiTask?.cancel()
        aiTask = nil
        activeAIRequestID = nil
    }

    private func sendAIEvent(_ event: GradelyWatchAIStreamEvent) {
        guard let session, session.isReachable else { return }
        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: event) else { return }
        session.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
    }

    private func reply(_ handler: ([String: Any]) -> Void, _ ack: GradelyWatchAIStreamAck) {
        handler((try? GradelyWatchSyncCodec.envelope(for: ack)) ?? [:])
    }

    private static func watchEvent(
        from event: GradeyAIStreamEvent,
        requestID: String,
        conversationID: String
    ) -> GradelyWatchAIStreamEvent {
        switch event {
        case .start(_, let remaining):
            return GradelyWatchAIStreamEvent(
                requestID: requestID,
                conversationID: conversationID,
                kind: .started,
                remaining: remaining
            )
        case .delta(let text):
            return GradelyWatchAIStreamEvent(
                requestID: requestID,
                conversationID: conversationID,
                kind: .delta,
                text: text
            )
        case .done(_, let remaining, _, _, _):
            return GradelyWatchAIStreamEvent(
                requestID: requestID,
                conversationID: conversationID,
                kind: .done,
                remaining: remaining
            )
        case .error(let code, let message, _, let remaining):
            return GradelyWatchAIStreamEvent(
                requestID: requestID,
                conversationID: conversationID,
                kind: .failed,
                errorCode: code,
                errorMessage: message,
                remaining: remaining
            )
        }
    }
}

extension LiveWatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.handleActivation(state: activationState)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if GradelyWatchSyncCodec.isRequestPurchaseRefresh(message) {
            Task { @MainActor in
                await self.handlePurchaseRefreshRequest(replyHandler)
            }
            return
        }

        if GradelyWatchSyncCodec.isRequestSync(message) {
            Task { @MainActor in
                await self.refreshSupportTier()
                self.replyToSyncRequest(replyHandler)
            }
            return
        }

        if let request = try? GradelyWatchSyncCodec.aiRequest(from: message) {
            Task { @MainActor in
                await self.handleAIRequest(request, replyHandler: replyHandler)
            }
            return
        }

        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let cancel = try? GradelyWatchSyncCodec.aiCancel(from: message) {
            Task { @MainActor in
                self.handleAICancel(cancel)
            }
        }
    }
}
#endif
