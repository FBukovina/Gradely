import Foundation
import GradelyWatchShared
import Testing
@testable import Gradely

@MainActor
struct WatchSyncTests {
    @Test func repositoryPublishesSessionAfterLogin() async throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache(),
            watchSyncService: watchSync
        )

        let session = try await repository.login(
            schoolURL: "https://demo.gradely.app",
            username: "student",
            password: "password"
        )

        #expect(watchSync.sessions == [session])
    }

    @Test func repositoryPublishesTimetableAfterLoad() async throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            timetableCache: InMemoryTimetableCache(),
            watchSyncService: watchSync
        )

        _ = try await repository.loadTimetable(weekContaining: Date())

        #expect(watchSync.timetables.count == 1)
        #expect(watchSync.timetables[0]?.days.isEmpty == false)
    }

    @Test func recordingServiceStoresSupportTier() {
        let watchSync = RecordingWatchSyncService()
        watchSync.update(supportTier: .standard)
        watchSync.update(supportTier: .plus)
        #expect(watchSync.supportTiers == [.standard, .plus])
    }

    @Test func repositoryPublishesSignedOutOnLogout() throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            timetableCache: InMemoryTimetableCache(),
            watchSyncService: watchSync
        )

        try repository.logout()

        #expect(watchSync.didPublishSignedOut)
    }
}

@MainActor
private final class RecordingWatchSyncService: WatchSyncing {
    private(set) var sessions: [StoredSession?] = []
    private(set) var users: [UserResponse?] = []
    private(set) var timetables: [GradelyWatchTimetable?] = []
    private(set) var supportTiers: [GradelyWatchSupportTier] = []
    private(set) var didPublishSignedOut = false

    func start() {}

    func update(session: StoredSession?) {
        sessions.append(session)
    }

    func update(user: UserResponse?) {
        users.append(user)
    }

    func update(timetable: GradelyWatchTimetable?) {
        timetables.append(timetable)
    }

    func update(supportTier: GradelyWatchSupportTier) {
        supportTiers.append(supportTier)
    }

    func configureAIRelay(
        client: any GradeyAIClient,
        contextBuilder: any GradeyAIContextBuilding,
        supportProvider: any SupportTipProviding
    ) {}

    func publishSignedOut() {
        didPublishSignedOut = true
    }
}

#if canImport(WatchConnectivity) && !os(macOS)
extension WatchSyncTests {
    @Test func watchGeneralReplyHasNoSchoolContextAndUsesServerCompute() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        let service = relay(client: client, builder: builder)
        var envelope: [String: Any] = [:]
        await service.handleAIRequest(watchRequest()) { envelope = $0 }
        await waitForRelay { !client.requests.isEmpty }
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        let request = try #require(client.requests.first)
        #expect(ack.accepted)
        #expect(request.context.subjects.isEmpty && request.context.trends.isEmpty && request.context.timetable.isEmpty)
        #expect(request.context.events?.isEmpty != false && request.context.insights?.isEmpty != false)
        #expect(builder.schoolDataReadCount == 0)
        #expect(request.actionID == .reply && request.maximumComputeCost == 2 && request.catalogVersion == "watch-v1")
        #expect(request.contextSelectionID == GradeyAIContextSelection(action: .reply).identifier)
        service.publishSignedOut()
    }

    @Test func watchSchoolChangeDuringStatusCannotCreateOrDispatchRequest() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.holdsStatus = true
        let service = relay(client: client, builder: builder)
        var envelope: [String: Any] = [:]
        let request = Task { await service.handleAIRequest(watchRequest()) { envelope = $0 } }
        await waitForRelay { client.statusContinuation != nil }
        builder.scope = "school-other-student"
        client.releaseStatus()
        await request.value
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        #expect(!ack.accepted && ack.errorCode == GradelyWatchAIErrorCode.cancelled)
        #expect(client.createCount == 0 && client.requests.isEmpty)
    }

    @Test func watchSignOutDuringConversationCreationCannotDispatch() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.holdsCreate = true
        let service = relay(client: client, builder: builder)
        var envelope: [String: Any] = [:]
        let request = Task { await service.handleAIRequest(watchRequest()) { envelope = $0 } }
        await waitForRelay { client.createContinuation != nil }
        service.publishSignedOut()
        client.releaseCreate()
        await request.value
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        #expect(!ack.accepted && ack.errorCode == GradelyWatchAIErrorCode.cancelled)
        #expect(client.requests.isEmpty)
    }

    @Test func watchNeverContinuesLegacyChatWithAutomaticSchoolHistory() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.conversations["legacy"] = GradeyAIConversation(id: "legacy", schoolScope: builder.scope, title: "Old school context", createdAt: Date(), updatedAt: Date())
        let service = relay(client: client, builder: builder)
        var envelope: [String: Any] = [:]
        await service.handleAIRequest(watchRequest(conversationID: "legacy")) { envelope = $0 }
        await waitForRelay { !client.requests.isEmpty }
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        #expect(ack.accepted && ack.conversationID != "legacy")
        #expect(client.createCount == 1)
        #expect(client.requests.first?.context.subjects.isEmpty == true)
        service.publishSignedOut()
    }

    @Test func watchCanContinueAnExplicitGeneralChatWithoutReadingSchoolRecords() async {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.conversations["general"] = GradeyAIConversation(id: "general", schoolScope: builder.scope, title: "General", createdAt: Date(), updatedAt: Date(), contextSelectionID: GradeyAIContextSelection().identifier)
        let service = relay(client: client, builder: builder)
        await service.handleAIRequest(watchRequest(conversationID: "general")) { _ in }
        await waitForRelay { !client.requests.isEmpty }
        #expect(client.requests.first?.conversationID == "general")
        #expect(client.createCount == 0 && builder.schoolDataReadCount == 0)
        service.publishSignedOut()
    }

    @Test func watchServerBalanceGateDoesNotUseLocalPaidAllowance() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.status.remaining = 1
        var entitlement = SupportEntitlement.none
        entitlement.tier = .plus
        let service = LiveWatchSyncService()
        service.configureAIRelay(client: client, contextBuilder: builder, supportProvider: MockSupportTipService(entitlement: entitlement))
        var envelope: [String: Any] = [:]
        await service.handleAIRequest(watchRequest()) { envelope = $0 }
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        #expect(!ack.accepted && ack.errorCode == GradelyWatchAIErrorCode.quotaExceeded)
        #expect(client.createCount == 0 && client.requests.isEmpty)
    }

    @Test func watchLegacyBackendUsesFreshEmptyChatWithoutSelectionMetadata() async throws {
        let client = WatchRelayAIClient(), builder = WatchRelayContextBuilder()
        client.status.compute = nil
        client.returnsSelectionMetadata = false
        var entitlement = SupportEntitlement.none
        entitlement.tier = .plus
        let service = LiveWatchSyncService()
        service.configureAIRelay(client: client, contextBuilder: builder, supportProvider: MockSupportTipService(entitlement: entitlement))
        var envelope: [String: Any] = [:]
        await service.handleAIRequest(watchRequest()) { envelope = $0 }
        await waitForRelay { !client.requests.isEmpty }
        let decodedAck = try GradelyWatchSyncCodec.aiAck(from: envelope)
        let ack = try #require(decodedAck)
        #expect(ack.accepted)
        #expect(client.requests.first?.context.subjects.isEmpty == true)
        #expect(client.requests.first?.maximumComputeCost == 1)
        #expect(builder.schoolDataReadCount == 0)
        service.publishSignedOut()
    }

    private func relay(client: WatchRelayAIClient, builder: WatchRelayContextBuilder) -> LiveWatchSyncService {
        let service = LiveWatchSyncService()
        // The server reports the verified subscription. Empty local metadata
        // must neither mint a balance nor override the current server result.
        service.configureAIRelay(client: client, contextBuilder: builder, supportProvider: MockSupportTipService())
        return service
    }
    private func watchRequest(conversationID: String? = nil) -> GradelyWatchAIStreamRequest {
        GradelyWatchAIStreamRequest(requestID: UUID().uuidString, conversationID: conversationID, clientMessageID: UUID().uuidString, text: "Help me plan my study time")
    }
    private func waitForRelay(_ condition: () -> Bool) async {
        for _ in 0..<200 { if condition() { return }; await Task.yield() }
        #expect(condition())
    }
}

@MainActor
private final class WatchRelayContextBuilder: GradeyAIContextBuilding {
    var scope = "school-watch"
    var schoolDataReadCount = 0
    func currentSchoolScope() throws -> String { scope }
    func cachedContext() throws -> GradeyAIContextSnapshot? { schoolDataReadCount += 1; return schoolSnapshot() }
    func refreshContext() async throws -> GradeyAIContextSnapshot { schoolDataReadCount += 1; return schoolSnapshot() }
    private func schoolSnapshot() -> GradeyAIContextSnapshot {
        let subjects = GradeyAIContextBuilder.makeSubjects(from: PreviewData.subjects)
        let lesson = GradeyAILessonContext(id: "private-lesson", date: "2026-09-11", subject: "Math", subjectAbbreviation: "M", beginsAt: "08:00", endsAt: "08:45", teacher: "Private teacher name", room: nil, groups: [], changeKind: .none, changeDescription: nil)
        return GradeyAIContextSnapshot(schoolScope: scope, generatedAt: Date(), isStale: false, unavailableSections: [], subjects: subjects, trends: [], timetable: [lesson])
    }
}

@MainActor
private final class WatchRelayAIClient: GradeyAIClient {
    var status = GradeyAIStatus(enabled: true, consentRequired: false, termsVersion: "2.2", dailyLimit: 10, dailyUsed: 0, remaining: 10, resetAt: nil,
        compute: GradeyComputeBalance(schemaVersion: 1, catalogVersion: "watch-v1", allowance: 10, used: 0, reserved: 0, remaining: 10, resetAt: nil,
            supportTier: "plus", actions: [GradeyComputeAction(id: "reply", cost: 2, available: true)]))
    var requests: [GradeyAIReplyRequest] = []
    var conversations: [String: GradeyAIConversation] = [:]
    var createCount = 0
    var holdsStatus = false
    var holdsCreate = false
    var returnsSelectionMetadata = true
    var statusContinuation: CheckedContinuation<Void, Never>?
    var createContinuation: CheckedContinuation<Void, Never>?
    func loadStatus() async throws -> GradeyAIStatus {
        if holdsStatus { await withCheckedContinuation { statusContinuation = $0 } }
        return status
    }
    func releaseStatus() { holdsStatus = false; statusContinuation?.resume(); statusContinuation = nil }
    func releaseCreate() { holdsCreate = false; createContinuation?.resume(); createContinuation = nil }
    func acceptConsent() async throws -> GradeyAIConsent { GradeyAIConsent(consented: true, termsVersion: "2.2") }
    func revokeConsent() async throws {}
    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation] { Array(conversations.values) }
    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation {
        try await createConversation(schoolScope: schoolScope, title: title, contextSelectionID: schoolScope)
    }
    func createConversation(schoolScope: String, title: String?, contextSelectionID: String) async throws -> GradeyAIConversation {
        createCount += 1
        if holdsCreate { await withCheckedContinuation { createContinuation = $0 } }
        let conversation = GradeyAIConversation(id: UUID().uuidString, schoolScope: schoolScope, title: title ?? "Watch", createdAt: Date(), updatedAt: Date(), contextSelectionID: returnsSelectionMetadata ? contextSelectionID : nil)
        conversations[conversation.id] = conversation
        return conversation
    }
    func loadConversation(id: String) async throws -> GradeyAIConversationDetail {
        guard let conversation = conversations[id] else { throw GradeyAIError.invalidResponse }
        return GradeyAIConversationDetail(conversation: conversation, messages: [])
    }
    func deleteConversation(id: String) async throws {}
    func deleteAllConversations(schoolScope: String) async throws {}
    func streamReply(request: GradeyAIReplyRequest) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.start(assistantMessageID: UUID().uuidString, remaining: status.remaining))
            continuation.yield(.done(finishReason: "stop", remaining: status.remaining, inputTokens: nil, outputTokens: nil, persistedMessage: nil))
            continuation.finish()
        }
    }
    func streamReply(conversationID: String, clientMessageID: String, text: String, context: GradeyAIContextSnapshot) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        streamReply(request: GradeyAIReplyRequest(conversationID: conversationID, clientMessageID: clientMessageID, text: text, context: context,
            actionID: .reply, contextSelectionID: context.schoolScope, catalogVersion: nil, maximumComputeCost: 1))
    }
}
#endif
