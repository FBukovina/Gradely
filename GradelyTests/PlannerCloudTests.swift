import Foundation
import Testing
@testable import Gradely

@MainActor
struct PlannerCloudTests {
    private func session(_ owner: String = "11111111-1111-4111-8111-111111111111") -> GradeyAuthSession {
        GradeyAuthSession(accessToken: "test", refreshToken: nil, tokenType: "Bearer", expiresAt: nil,
            account: GradeyAccount(id: owner, email: "student@example.com", fullName: nil, avatarURL: nil, createdAt: Date()))
    }
    private func item(_ title: String = "Study") -> PlannerItem {
        var item = PlannerItem(); item.title = title; item.calendarSyncEnabled = false; return item
    }
    private func store(auth: MockGradeyAuthClient, cloud: TestPlannerCloud, persistence: any PlannerCloudPersisting,
                       local: InMemoryPlannerPersistence = InMemoryPlannerPersistence()) -> PlannerStore {
        let store = PlannerStore(persistence: local, calendarService: UnavailablePlannerCalendarService())
        store.configureCloud(authClient: auth, client: cloud, persistence: persistence, observeConnectivity: false)
        return store
    }

    @Test func offlineQueueSurvivesRelaunchAndAccountSwitchNeverMixesItems() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let first = store(auth: auth, cloud: cloud, persistence: disk)
        let draft = item(); try await first.save(draft)
        let mutation = try #require(disk.states[session().account.id]?.pending.first?.mutationId)
        let reopened = store(auth: auth, cloud: cloud, persistence: disk)
        #expect(reopened.items.map(\.id) == [draft.id]); #expect(reopened.pendingCloudCount == 1)
        #expect(disk.states[session().account.id]?.pending.first?.mutationId == mutation)
        auth.session = session("22222222-2222-4222-8222-222222222222")
        reopened.refreshAccountScope(); #expect(reopened.items.isEmpty); #expect(reopened.pendingCloudCount == 0)
        auth.session = session(); reopened.refreshAccountScope(); #expect(reopened.items.map(\.id) == [draft.id])
    }

    @Test func legacyItemsRequireSelectedImportAndOriginalFileIsUntouched() async throws {
        let original = item("Local only"), local = InMemoryPlannerPersistence(items: [item("Other")])
        local.items.append(original)
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let store = store(auth: auth, cloud: cloud, persistence: disk, local: local)
        #expect(store.items.isEmpty); #expect(store.legacyImportItems.count == 2); #expect(store.pendingCloudCount == 0)
        try await store.importLegacyItems(ids: [original.id])
        #expect(store.items.map(\.id) == [original.id]); #expect(local.items.count == 2)
        #expect(store.legacyImportItems.count == 1); #expect(store.pendingCloudCount == 1)
    }

    @Test func cloudDTOExcludesCalendarStateAndReadsBrowserFractionalDates() throws {
        var original = item(); original.calendarEventIdentifier = "private-event"; original.calendarNeedsSync = true
        let data = try PlannerCloudCoding.encoder().encode(PlannerCloudItem(original))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.keys.allSatisfy { !$0.hasPrefix("calendar") })
        var browserJSON = json; browserJSON["updatedAt"] = "2026-10-05T10:00:00.123Z"
        let remote = try PlannerCloudCoding.decoder().decode(PlannerCloudItem.self, from: JSONSerialization.data(withJSONObject: browserJSON))
        #expect(remote.local(preserving: original).calendarEventIdentifier == "private-event")
        #expect(!remote.local(preserving: nil).calendarSyncEnabled)
    }

    @Test func cloudDeleteRetainsTombstoneWithoutCalendarExport() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let store = store(auth: auth, cloud: cloud, persistence: disk), draft = item()
        try await store.save(draft); try await store.delete(id: draft.id)
        #expect(store.items.isEmpty)
        let change = try #require(disk.states[session().account.id]?.pending.first)
        #expect(change.item.deletedAt != nil); #expect(change.item.id == draft.id); #expect(change.item.title.isEmpty)
    }

    @Test func conflictPreservesLocalAndKeepingDeletedRemoteCreatesNewID() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let store = store(auth: auth, cloud: cloud, persistence: disk), draft = item()
        try await store.save(draft)
        var deleted = PlannerCloudItem(draft); deleted.deletedAt = Date(); deleted.title = ""
        let record = PlannerCloudRecord(item: deleted, revision: 2)
        cloud.error = nil
        cloud.result = PlannerCloudResult(items: [record], conflicts: [PlannerCloudConflict(itemId: draft.id, remote: record)], cursor: 2, acceptedMutationIds: [])
        await store.syncCloud()
        #expect(store.items.first?.title == draft.title); #expect(store.cloudConflicts.count == 1)
        cloud.error = URLError(.notConnectedToInternet)
        try await store.resolveCloudConflict(id: draft.id, keepLocal: true)
        #expect(store.items.count == 1); #expect(store.items.first?.id != draft.id)
        #expect(store.cloudConflicts.isEmpty); #expect(store.pendingCloudCount == 1)
    }

    @Test func responseAfterAccountChangeCannotPublishOldAccount() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        let store = store(auth: auth, cloud: cloud, persistence: disk)
        cloud.beforeResponse = { auth.session = self.session("22222222-2222-4222-8222-222222222222"); store.refreshAccountScope() }
        cloud.result = PlannerCloudResult(items: [PlannerCloudRecord(item: PlannerCloudItem(item()), revision: 1)], conflicts: [], cursor: 1, acceptedMutationIds: [])
        await store.syncCloud()
        #expect(store.items.isEmpty); #expect(store.cloudOwnerID == auth.session?.account.id)
    }

    @Test func diskPersistenceKeepsAccountQueuesSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = PlannerCloudPersistence(directory: directory)
        var state = PlannerCloudState(); state.items = [item()]; state.cursor = 17
        try disk.save(state, owner: session().account.id)
        #expect(try disk.load(owner: session().account.id).cursor == 17)
        #expect(try disk.load(owner: "22222222-2222-4222-8222-222222222222").items.isEmpty)
        #expect(throws: PlannerError.self) { try disk.load(owner: "../../outside") }
    }

    @Test func acceptedReplyCannotReplaceEditMadeDuringRequest() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let store = store(auth: auth, cloud: cloud, persistence: disk), draft = item("First edit")
        try await store.save(draft)
        cloud.error = nil
        cloud.beforeResponse = {
            cloud.beforeResponse = nil
            var newer = draft; newer.title = "Latest edit"
            try await store.save(newer)
        }
        cloud.respond = { request in
            PlannerCloudResult(items: request.changes.map { PlannerCloudRecord(item: $0.item, revision: $0.baseRevision + 1) },
                conflicts: [], cursor: 2, acceptedMutationIds: request.changes.map(\.mutationId))
        }
        await store.syncCloud()
        #expect(store.items.first?.title == "Latest edit")
        for _ in 0..<20 where store.pendingCloudCount > 0 { await Task.yield() }
        #expect(store.items.first?.title == "Latest edit")
        #expect(cloud.requests.contains { $0.changes.contains { $0.item.title == "Latest edit" && $0.baseRevision == 1 } })
    }

    @Test func legacyReviewCannotImportIntoChangedAccount() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        let draft = item(), local = InMemoryPlannerPersistence()
        local.items = [draft]
        let store = store(auth: auth, cloud: cloud, persistence: disk, local: local)
        auth.session = session("22222222-2222-4222-8222-222222222222")
        await #expect(throws: PlannerError.self) { try await store.importLegacyItems(ids: [draft.id], expectedOwnerID: session().account.id) }
        #expect(store.items.isEmpty); #expect(store.pendingCloudCount == 0)
    }

    @Test func failedAtomicCloudWriteDoesNotPublishOrQueueItem() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud()
        let store = store(auth: auth, cloud: cloud, persistence: FailingPlannerCloudPersistence())
        await #expect(throws: PlannerError.self) { try await store.save(item()) }
        #expect(store.items.isEmpty); #expect(store.pendingCloudCount == 0); #expect(cloud.requests.isEmpty)
    }

    @Test func draftFromPreviousAccountCannotBeSavedAfterSwitch() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud()
        let store = store(auth: auth, cloud: cloud, persistence: InMemoryPlannerCloudPersistence())
        let token = store.accountScopeToken
        auth.session = session("22222222-2222-4222-8222-222222222222")
        await #expect(throws: PlannerError.self) { try await store.save(item(), expectedScopeToken: token) }
        #expect(store.items.isEmpty); #expect(store.pendingCloudCount == 0)
    }

    @Test func staleEditorPreservesAnotherWindowsUnsentChange() async throws {
        let auth = MockGradeyAuthClient(session: session()), cloud = TestPlannerCloud(), disk = InMemoryPlannerCloudPersistence()
        cloud.error = URLError(.notConnectedToInternet)
        let store = store(auth: auth, cloud: cloud, persistence: disk), draft = item("Original")
        try await store.save(draft)
        let expected = try #require(store.cloudRecord(id: draft.id))
        var other = draft; other.title = "Other window"
        try await store.save(other)
        let otherMutation = try #require(disk.states[session().account.id]?.pending.first?.mutationId)
        var stale = draft; stale.title = "Editor draft"
        try await store.save(stale, expectedCloudRecord: expected)
        #expect(store.items.first?.title == "Editor draft"); #expect(store.cloudConflicts.first?.remote?.item.title == "Other window")
        try await store.resolveCloudConflict(id: draft.id, keepLocal: false)
        #expect(store.items.first?.title == "Other window")
        #expect(disk.states[session().account.id]?.pending.first?.mutationId == otherMutation)
    }

    @Test func batchCapsBothMutationCountAndEncodedUTF8Bytes() throws {
        let changes = (0..<205).map { _ in PlannerCloudChange(item: PlannerCloudItem(item()), baseRevision: 0, mutationId: UUID()) }
        #expect(try PlannerCloudCoding.batch(changes, cursor: 0).count == 100)
        var large = item(); large.notes = String(repeating: "ž", count: 20_000)
        let largeChanges = (0..<100).map { _ in PlannerCloudChange(item: PlannerCloudItem(large), baseRevision: 0, mutationId: UUID()) }
        let batch = try PlannerCloudCoding.batch(largeChanges, cursor: 1)
        #expect(!batch.isEmpty); #expect(batch.count < 100)
        #expect(try PlannerCloudCoding.encoder().encode(PlannerCloudRequest(changes: batch, cursor: 1)).count <= 480_000)
    }

    @Test func browserDatesKeepPragueAllDayAcrossDaylightSavingChange() throws {
        var original = item(); original.timeZoneIdentifier = "Europe/Prague"
        original.dueDate = ISO8601DateFormatter().date(from: "2026-10-25T00:00:00Z"); original.dueHasTime = false
        let downloaded = try PlannerCloudCoding.decoder().decode(PlannerCloudItem.self, from: PlannerCloudCoding.encoder().encode(PlannerCloudItem(original)))
        let event = try PlannerCalendarEventData.make(from: downloaded.local(preserving: nil))
        #expect(event.isAllDay); #expect(event.end.timeIntervalSince(event.start) == 25 * 60 * 60)
        #expect(event.timeZoneIdentifier == "Europe/Prague")
    }
}

private final class TestPlannerCloud: PlannerCloudSyncing {
    var error: Error?
    var beforeResponse: (@MainActor () async throws -> Void)?
    var requests: [PlannerCloudRequest] = []
    var respond: ((PlannerCloudRequest) -> PlannerCloudResult)?
    var result = PlannerCloudResult(items: [], conflicts: [], cursor: 0, acceptedMutationIds: [])
    @MainActor func sync(_ request: PlannerCloudRequest, session: GradeyAuthSession) async throws -> PlannerCloudResult {
        requests.append(request)
        if let error { throw error }
        try await beforeResponse?()
        return respond?(request) ?? result
    }
}

private struct FailingPlannerCloudPersistence: PlannerCloudPersisting {
    func load(owner: String) throws -> PlannerCloudState { PlannerCloudState() }
    func save(_ state: PlannerCloudState, owner: String) throws { throw CocoaError(.fileWriteOutOfSpace) }
}
