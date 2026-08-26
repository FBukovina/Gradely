import Combine
import Foundation
import GradelyWatchShared
import WidgetKit

struct WatchAIChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var text: String
    var isStreaming: Bool
}

@MainActor
final class WatchAppModel: ObservableObject {
    @Published private(set) var auth: GradelyWatchAuth?
    @Published private(set) var user: GradelyWatchUser?
    @Published private(set) var timetable: GradelyWatchTimetable?
    @Published private(set) var supportTier: GradelyWatchSupportTier = .none
    @Published private(set) var isSyncing = false
    @Published private(set) var isRefreshingPurchases = false
    @Published private(set) var purchaseRefreshMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPhoneReachable = false
    @Published var aiMessages: [WatchAIChatMessage] = []
    @Published var aiDraft = ""
    @Published private(set) var isAIStreaming = false
    @Published private(set) var aiErrorMessage: String?

    private let connectivity: WatchConnectivityClient
    private let sessionStore: WatchSessionStore
    private let timetableCache: WatchTimetableCache
    private let client: WatchBakalariClient
    private var hasStarted = false
    private var aiConversationID: String?
    private var aiRequestID: String?
    private var aiTimeoutTask: Task<Void, Never>?

    private static let supportTierDefaultsKey = "gradely.watch.supportTier"

    init(
        connectivity: WatchConnectivityClient = WatchConnectivityClient(),
        sessionStore: WatchSessionStore = WatchSessionStore(),
        timetableCache: WatchTimetableCache = WatchTimetableCache(),
        client: WatchBakalariClient = WatchBakalariClient()
    ) {
        self.connectivity = connectivity
        self.sessionStore = sessionStore
        self.timetableCache = timetableCache
        self.client = client
    }

    var isSignedIn: Bool {
        auth != nil
    }

    var isRecurringSupporter: Bool {
        supportTier.isRecurringSupporter
    }

    var statusTitle: String {
        if !isSignedIn {
            return String(localized: "watch.status.notSignedIn")
        }
        if let errorMessage, !errorMessage.isEmpty {
            return String(localized: "watch.status.needsAttention")
        }
        switch lessonSelection {
        case .lesson:
            return String(localized: "watch.status.timetable")
        case .noTimetable:
            return String(localized: "watch.status.syncing")
        case .noLessons:
            return String(localized: "watch.done.title")
        case .stale:
            return String(localized: "watch.stale.title")
        }
    }

    var lessonSelection: GradelyWatchLessonSelection {
        GradelyWatchSyncCodec.selectLesson(from: timetable)
    }

    var nowAndNext: GradelyWatchNowNext {
        GradelyWatchSyncCodec.nowAndNext(from: timetable)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        if let raw = UserDefaults.standard.string(forKey: Self.supportTierDefaultsKey),
           let stored = GradelyWatchSupportTier(rawValue: raw) {
            supportTier = stored
        }

        connectivity.onPayload = { [weak self] payload in
            Task { @MainActor in
                await self?.apply(payload)
            }
        }
        connectivity.onAIEvent = { [weak self] event in
            self?.handleAIEvent(event)
        }
        connectivity.onReachabilityChange = { [weak self] reachable in
            self?.isPhoneReachable = reachable
        }
        connectivity.start()

        auth = try? sessionStore.load()
        timetable = try? timetableCache.load()
        isPhoneReachable = connectivity.isReachable
        connectivity.requestSync()

        if auth != nil {
            await refreshTimetable()
        }
    }

    func refreshTimetable() async {
        guard var currentAuth = auth ?? (try? sessionStore.load()) else {
            auth = nil
            return
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            if currentAuth.expiresSoon() {
                currentAuth = try await client.refresh(auth: currentAuth)
                auth = currentAuth
                try sessionStore.save(currentAuth)
            }

            let loaded: GradelyWatchTimetable
            do {
                loaded = try await client.fetchTimetable(auth: currentAuth, weekContaining: Date())
            } catch {
                guard currentAuth.resolvedProvider == .eduPage || isAuthFailure(error) else { throw error }
                currentAuth = try await client.refresh(auth: currentAuth)
                auth = currentAuth
                try sessionStore.save(currentAuth)
                loaded = try await client.fetchTimetable(auth: currentAuth, weekContaining: Date())
            }
            timetable = loaded
            try timetableCache.save(loaded)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func refreshPurchases() async {
        guard !isRefreshingPurchases else { return }

        isRefreshingPurchases = true
        purchaseRefreshMessage = nil
        defer { isRefreshingPurchases = false }

        do {
            let payload = try await connectivity.requestPurchaseRefresh()
            persist(supportTier: payload.supportTier)
            if !isRecurringSupporter {
                purchaseRefreshMessage = String(localized: "watch.purchase.noPlan")
            }
        } catch {
            purchaseRefreshMessage = userFacingMessage(for: error)
        }
    }

    func sendAIMessage() async {
        let text = aiDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAIStreaming, isRecurringSupporter else { return }

        aiDraft = ""
        aiErrorMessage = nil
        let requestID = UUID().uuidString
        let clientMessageID = UUID().uuidString
        aiRequestID = requestID
        aiMessages.append(
            WatchAIChatMessage(id: clientMessageID, role: .user, text: text, isStreaming: false)
        )
        aiMessages.append(
            WatchAIChatMessage(id: UUID().uuidString, role: .assistant, text: "", isStreaming: true)
        )
        isAIStreaming = true
        startAITimeout()

        do {
            let ack = try await connectivity.sendAIRequest(
                GradelyWatchAIStreamRequest(
                    requestID: requestID,
                    conversationID: aiConversationID,
                    clientMessageID: clientMessageID,
                    text: text
                )
            )
            if let conversationID = ack.conversationID {
                aiConversationID = conversationID
            }
            guard ack.accepted else {
                failAI(message: ack.errorMessage)
                return
            }
        } catch {
            failAI(message: userFacingMessage(for: error))
        }
    }

    func cancelAI() {
        guard let aiRequestID else { return }
        connectivity.sendAICancel(GradelyWatchAICancel(requestID: aiRequestID))
        failAI(message: String(localized: "watch.ai.error.cancelled"))
    }

    private func handleAIEvent(_ event: GradelyWatchAIStreamEvent) {
        guard event.requestID == aiRequestID else { return }
        if let conversationID = event.conversationID {
            aiConversationID = conversationID
        }

        switch event.kind {
        case .started:
            break
        case .delta:
            guard let text = event.text,
                  let index = aiMessages.lastIndex(where: { $0.role == .assistant })
            else { return }
            aiMessages[index].text += text
        case .done:
            finishAIStream()
        case .failed:
            failAI(message: event.errorMessage)
        }
    }

    private func startAITimeout() {
        aiTimeoutTask?.cancel()
        aiTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.failAI(message: String(localized: "watch.ai.error.timeout"))
            }
        }
    }

    private func finishAIStream() {
        aiTimeoutTask?.cancel()
        aiTimeoutTask = nil
        isAIStreaming = false
        aiRequestID = nil
        if let index = aiMessages.lastIndex(where: { $0.role == .assistant }) {
            aiMessages[index].isStreaming = false
        }
    }

    private func failAI(message: String?) {
        finishAIStream()
        if let index = aiMessages.lastIndex(where: { $0.role == .assistant }),
           aiMessages[index].text.isEmpty {
            aiMessages.remove(at: index)
        }
        aiErrorMessage = message ?? String(localized: "watch.ai.error.generic")
    }

    private func apply(_ payload: GradelyWatchSyncPayload) async {
        persist(supportTier: payload.supportTier)

        guard payload.isSignedIn, let payloadAuth = payload.auth else {
            auth = nil
            user = nil
            timetable = nil
            errorMessage = nil
            try? sessionStore.clear()
            try? timetableCache.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        auth = payloadAuth
        user = payload.user
        try? sessionStore.save(payloadAuth)

        if let payloadTimetable = payload.timetable {
            timetable = payloadTimetable
            try? timetableCache.save(payloadTimetable)
            WidgetCenter.shared.reloadAllTimelines()
        }

        await refreshTimetable()
    }

    private func persist(supportTier: GradelyWatchSupportTier) {
        self.supportTier = supportTier
        UserDefaults.standard.set(supportTier.rawValue, forKey: Self.supportTierDefaultsKey)
    }

    private func isAuthFailure(_ error: Error) -> Bool {
        if case WatchBakalariError.httpStatus(401, _) = error {
            return true
        }
        return false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
