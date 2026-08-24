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
    private var watchConversationID: String?
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
        watchConversationID = nil
        aiTask?.cancel()
        aiTask = nil
        activeAIRequestID = nil
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

    private func handleAIRequest(
        _ request: GradelyWatchAIStreamRequest,
        replyHandler: @escaping ([String: Any]) -> Void
    ) async {
        aiTask?.cancel()
        activeAIRequestID = request.requestID

        let entitlement = await supportProvider?.currentEntitlement() ?? .none
        guard entitlement.tier != .none else {
            reply(replyHandler, .failure(
                code: GradelyWatchAIErrorCode.supporterRequired,
                message: "Subscribe in Gradey on iPhone."
            ))
            return
        }

        guard let aiClient, let contextBuilder else {
            reply(replyHandler, .failure(
                code: GradelyWatchAIErrorCode.notConfigured,
                message: "Gradey AI is not available."
            ))
            return
        }

        do {
            let status = try await aiClient.loadStatus()
            if status.consentRequired {
                reply(replyHandler, .failure(
                    code: GradelyWatchAIErrorCode.consentRequired,
                    message: "Enable Gradey AI on iPhone."
                ))
                return
            }
            guard status.enabled else {
                reply(replyHandler, .failure(
                    code: GradelyWatchAIErrorCode.notConfigured,
                    message: "Gradey AI is not available."
                ))
                return
            }
            guard status.remaining > 0 else {
                reply(replyHandler, .failure(
                    code: GradelyWatchAIErrorCode.quotaExceeded,
                    message: "Daily Gradey AI limit reached."
                ))
                return
            }

            let schoolScope = try contextBuilder.currentSchoolScope()
            let context: GradeyAIContextSnapshot
            if let refreshed = try? await contextBuilder.refreshContext() {
                context = refreshed
            } else if let cached = try contextBuilder.cachedContext() {
                context = cached
            } else {
                reply(replyHandler, .failure(
                    code: GradelyWatchAIErrorCode.noSchoolAccount,
                    message: "School context is unavailable."
                ))
                return
            }

            let conversationID: String
            if let existing = request.conversationID ?? watchConversationID {
                conversationID = existing
            } else {
                conversationID = try await aiClient.createConversation(
                    schoolScope: schoolScope,
                    title: "Watch"
                ).id
            }
            watchConversationID = conversationID

            reply(replyHandler, .success(conversationID: conversationID))

            aiTask = Task { [weak self] in
                await self?.stream(
                    request: request,
                    conversationID: conversationID,
                    context: context,
                    client: aiClient
                )
            }
        } catch let error as GradeyAIContextError where error == .noSchoolAccount {
            reply(replyHandler, .failure(
                code: GradelyWatchAIErrorCode.noSchoolAccount,
                message: "Open Gradey on iPhone and sign in to school."
            ))
        } catch {
            reply(replyHandler, .failure(
                code: "failed",
                message: error.localizedDescription
            ))
        }
    }

    private func stream(
        request: GradelyWatchAIStreamRequest,
        conversationID: String,
        context: GradeyAIContextSnapshot,
        client: any GradeyAIClient
    ) async {
        do {
            for try await event in client.streamReply(
                conversationID: conversationID,
                clientMessageID: request.clientMessageID,
                text: request.text,
                context: context
            ) {
                try Task.checkCancellation()
                sendAIEvent(Self.watchEvent(from: event, requestID: request.requestID, conversationID: conversationID))
            }
        } catch is CancellationError {
            sendAIEvent(
                GradelyWatchAIStreamEvent(
                    requestID: request.requestID,
                    conversationID: conversationID,
                    kind: .failed,
                    errorCode: GradelyWatchAIErrorCode.cancelled,
                    errorMessage: "Cancelled."
                )
            )
        } catch {
            sendAIEvent(
                GradelyWatchAIStreamEvent(
                    requestID: request.requestID,
                    conversationID: conversationID,
                    kind: .failed,
                    errorCode: "failed",
                    errorMessage: error.localizedDescription
                )
            )
        }

        if activeAIRequestID == request.requestID {
            activeAIRequestID = nil
            aiTask = nil
        }
    }

    private func handleAICancel(_ cancel: GradelyWatchAICancel) {
        guard cancel.requestID == activeAIRequestID else { return }
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
