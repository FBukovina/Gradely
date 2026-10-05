import Foundation
import Observation
import Network

@MainActor
@Observable
final class PlannerStore {
    /// One shared store across live windows prevents stale windows overwriting each other's items.
    static let shared = PlannerStore(persistence: PlannerPersistence(), calendarService: PlannerCalendarService())

    private(set) var items: [PlannerItem] = []
    private(set) var isLoaded = false
    private(set) var isSyncing = false
    private(set) var storageError: String?
    private(set) var calendarError: String?
    private var records: [PlannerItem] = []
    private let persistence: any PlannerPersisting
    private let calendarService: any PlannerCalendarSyncing
    private let now: () -> Date
    private var authClient: (any GradeyAuthClient)?
    private var cloudClient: (any PlannerCloudSyncing)?
    private var cloudPersistence: any PlannerCloudPersisting = PlannerCloudPersistence()
    private var cloudState = PlannerCloudState()
    private var scopeGeneration = UUID()
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    private(set) var cloudOwnerID: String?
    private(set) var isCloudSyncing = false
    private(set) var cloudError: String?
    private(set) var cloudConflicts: [PlannerCloudConflict] = []
    private(set) var legacyImportItems: [PlannerItem] = []
    var pendingCloudCount: Int { cloudState.pending.count }
    var accountScopeToken: UUID { scopeGeneration }
    func cloudRecord(id: UUID) -> PlannerCloudRecord? {
        guard cloudOwnerID != nil, let item = records.first(where: { $0.id == id }) else { return nil }
        return PlannerCloudRecord(item: PlannerCloudItem(item), revision: cloudState.revisions[id.uuidString] ?? 0)
    }
    var cloudAccountLabel: String { (try? authClient?.bootstrapSession())?.account.email ?? "Gradey ID" }

    init(persistence: any PlannerPersisting, calendarService: any PlannerCalendarSyncing, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.calendarService = calendarService
        self.now = now
    }

    var pendingCalendarCount: Int { records.filter(\.calendarNeedsSync).count }

    func configureCloud(authClient: any GradeyAuthClient, client: any PlannerCloudSyncing = SupabasePlannerCloudClient(),
                        persistence: any PlannerCloudPersisting = PlannerCloudPersistence(), observeConnectivity: Bool = true) {
        self.authClient = authClient; cloudClient = client; cloudPersistence = persistence
        refreshAccountScope()
        if observeConnectivity && pathMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.syncCloud() }
            }
            monitor.start(queue: DispatchQueue(label: "app.gradey.planner-connectivity"))
            pathMonitor = monitor
        }
    }

    /// This is synchronous so account switches hide the previous account before any await.
    func refreshAccountScope() {
        guard let authClient else { return }
        let owner = (try? authClient.bootstrapSession())?.account.id
        guard owner != cloudOwnerID else { return }
        cloudOwnerID = owner; scopeGeneration = UUID(); isCloudSyncing = false; isSyncing = false
        records = []; items = []; cloudState = PlannerCloudState(); cloudConflicts = []
        legacyImportItems = []; cloudError = nil; calendarError = nil; isLoaded = false
        loadIfNeeded()
    }

    func loadIfNeeded() {
        refreshAccountScope()
        guard !isLoaded else { return }
        do {
            if let owner = cloudOwnerID {
                cloudState = try cloudPersistence.load(owner: owner)
                records = cloudState.items
                cloudConflicts = cloudState.conflicts
                legacyImportItems = (try persistence.load()).filter { $0.deletedAt == nil && !cloudState.importedLegacyIDs.contains($0.id) }
            } else {
                records = try persistence.load()
            }
            publishItems()
            isLoaded = true
            storageError = nil
        } catch {
            // Never replace unreadable personal data with an empty, writable fallback.
            storageError = PlannerError.storageUnavailable.localizedDescription
        }
    }

    func activate() async {
        loadIfNeeded()
        await syncCloud()
        await syncPending(requestAccess: false)
    }

    /// Background actions may use existing Calendar access, but must not prompt for new access.
    func save(_ draft: PlannerItem, requestCalendarAccess: Bool = true, expectedScopeToken: UUID? = nil,
              expectedCloudRecord: PlannerCloudRecord? = nil) async throws {
        loadIfNeeded()
        if let expectedScopeToken, expectedScopeToken != scopeGeneration { throw PlannerError.storageUnavailable }
        guard isLoaded else { throw PlannerError.storageUnavailable }
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { throw PlannerError.titleRequired }
        if cloudOwnerID != nil, item.title.utf16.count > 500 || (item.notes?.utf16.count ?? 0) > 20_000 {
            throw PlannerError.cloudContentTooLarge
        }
        // Sync is on by default, so an undated item simply stays local rather than
        // failing a save over a date the user was never asked for.
        if !item.hasCalendarDate { item.calendarSyncEnabled = false }
        item.notes = item.notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let previous = records.first { $0.id == item.id }
        guard previous?.deletedAt == nil || (expectedCloudRecord != nil && cloudOwnerID != nil) else { throw PlannerError.storageUnavailable }
        item.createdAt = previous?.createdAt ?? now()
        item.updatedAt = now()
        item.calendarEventIdentifier = previous?.calendarEventIdentifier
        item.calendarLastStart = previous?.calendarLastStart
        item.calendarLastEnd = previous?.calendarLastEnd
        item.calendarNeedsSync = item.calendarSyncEnabled || previous?.calendarLastStart != nil
            || previous?.calendarEventIdentifier != nil
        item.deletedAt = nil
        var updated = records.filter { $0.id != item.id }
        updated.append(item)
        let previousConflicts = cloudState.conflicts
        if let expectedCloudRecord, let current = cloudRecord(id: item.id),
           current.item != expectedCloudRecord.item, current.item != PlannerCloudItem(item) {
            // Preserve an update received while this editor was open for an explicit decision.
            cloudState.conflicts.removeAll { $0.itemId == item.id }
            cloudState.conflicts.append(PlannerCloudConflict(itemId: item.id, remote: current,
                pendingAlternative: cloudState.pending.first { $0.item.id == item.id }))
        }
        do { try commit(updated) } catch { cloudState.conflicts = previousConflicts; throw error }
        cloudConflicts = cloudState.conflicts
        await syncPending(requestAccess: item.calendarNeedsSync && requestCalendarAccess)
        await syncCloud()
    }

    func setCompleted(_ completed: Bool, id: UUID) async throws {
        loadIfNeeded()
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.isCompleted = completed
        try await save(item)
    }

    func delete(id: UUID, expectedScopeToken: UUID? = nil) async throws {
        loadIfNeeded()
        if let expectedScopeToken, expectedScopeToken != scopeGeneration { throw PlannerError.storageUnavailable }
        guard var item = records.first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        var updated = records.filter { $0.id != id }
        if cloudOwnerID != nil || item.calendarLastStart != nil || item.calendarEventIdentifier != nil {
            item.calendarSyncEnabled = false
            item.calendarNeedsSync = item.calendarLastStart != nil || item.calendarEventIdentifier != nil
            item.deletedAt = now()
            item.updatedAt = now()
            item.title = ""
            item.notes = nil
            item.subject = nil
            item.lesson = nil
            item.linkedDate = nil
            item.dueDate = nil
            updated.append(item)
        }
        try commit(updated)
        await syncPending(requestAccess: item.calendarLastStart != nil || item.calendarEventIdentifier != nil)
        await syncCloud()
    }

    func attachedItems(to lesson: ScheduledLesson, on day: ScheduledDay, scope: SchoolDataScope) -> [PlannerItem] {
        items.filter { !$0.isCompleted && $0.lesson?.matches(lesson: lesson, day: day, scope: scope) == true }
    }

    func syncPending(requestAccess: Bool) async {
        guard isLoaded, !isSyncing, pendingCalendarCount > 0 else { return }
        let generation = scopeGeneration
        isSyncing = true
        defer { if scopeGeneration == generation { isSyncing = false } }
        calendarError = nil
        do {
            if requestAccess {
                try await calendarService.requestAccess()
            } else if !calendarService.hasAccess {
                calendarError = PlannerError.calendarPermission.localizedDescription
                return
            }
        } catch {
            calendarError = (error as? PlannerError)?.localizedDescription ?? PlannerError.calendarPermission.localizedDescription
            return
        }
        guard scopeGeneration == generation else { return }
        // Re-read after the authorization suspension, since an item may have changed meanwhile.
        for id in records.filter(\.calendarNeedsSync).map(\.id) {
            guard var item = records.first(where: { $0.id == id && $0.calendarNeedsSync }) else { continue }
            do {
                if item.calendarSyncEnabled && item.deletedAt == nil {
                    let data = try PlannerCalendarEventData.make(from: item)
                    if item.calendarLastStart == nil {
                        // Record the attempted range before the external write. This distinguishes
                        // a denied request (no event ever attempted) from an interrupted export.
                        item.calendarLastStart = data.start
                        item.calendarLastEnd = data.end
                        var prepared = records.filter { $0.id != id }
                        prepared.append(item)
                        try commit(prepared)
                    }
                    item.calendarEventIdentifier = try calendarService.upsert(item)
                    item.calendarLastStart = data.start
                    item.calendarLastEnd = data.end
                } else {
                    try calendarService.remove(item)
                    item.calendarEventIdentifier = nil
                    item.calendarLastStart = nil
                    item.calendarLastEnd = nil
                }
                item.calendarNeedsSync = false
                var updated = records.filter { $0.id != id }
                if item.deletedAt == nil || cloudOwnerID != nil { updated.append(item) }
                try commit(updated)
            } catch {
                calendarError = (error as? PlannerError)?.localizedDescription ?? PlannerError.calendarUnavailable.localizedDescription
            }
        }
    }

    private func commit(_ updated: [PlannerItem]) throws {
        do {
            if let owner = cloudOwnerID {
                var state = cloudState
                for item in updated where records.first(where: { $0.id == item.id }).map(PlannerCloudItem.init) != PlannerCloudItem(item) {
                    state.pending.removeAll { $0.item.id == item.id }
                    state.pending.append(PlannerCloudChange(item: PlannerCloudItem(item),
                        baseRevision: state.revisions[item.id.uuidString] ?? 0, mutationId: UUID()))
                }
                state.items = updated
                try cloudPersistence.save(state, owner: owner)
                cloudState = state
            } else {
                try persistence.save(updated)
            }
            records = updated
            publishItems()
            storageError = nil
            if pendingCalendarCount == 0 { calendarError = nil }
        } catch {
            storageError = PlannerError.storageUnavailable.localizedDescription
            throw PlannerError.storageUnavailable
        }
    }

    func importLegacyItems(ids: Set<UUID>, expectedOwnerID: String? = nil) async throws {
        loadIfNeeded()
        guard cloudOwnerID != nil, isLoaded else { throw PlannerError.storageUnavailable }
        if let expectedOwnerID, cloudOwnerID != expectedOwnerID { throw PlannerError.storageUnavailable }
        let selected = legacyImportItems.filter { ids.contains($0.id) }
        guard selected.allSatisfy({ $0.title.utf16.count <= 500 && ($0.notes?.utf16.count ?? 0) <= 20_000 }) else {
            throw PlannerError.cloudContentTooLarge
        }
        var updated = records
        for original in selected where !updated.contains(where: { $0.id == original.id }) {
            var item = original
            // Existing unowned calendar events remain with the preserved local Planner.
            item.calendarSyncEnabled = false; item.calendarEventIdentifier = nil; item.calendarNeedsSync = false
            item.calendarLastStart = nil; item.calendarLastEnd = nil
            updated.append(item)
        }
        let priorIDs = cloudState.importedLegacyIDs
        cloudState.importedLegacyIDs.formUnion(selected.map(\.id))
        do { try commit(updated) } catch { cloudState.importedLegacyIDs = priorIDs; throw error }
        legacyImportItems.removeAll { ids.contains($0.id) }
        await syncCloud()
    }

    func syncCloud() async {
        refreshAccountScope()
        guard let owner = cloudOwnerID, let authClient, let cloudClient, isLoaded, !isCloudSyncing else { return }
        let generation = scopeGeneration
        isCloudSyncing = true
        var hasMoreWork = false
        defer {
            if scopeGeneration == generation {
                isCloudSyncing = false
                if hasMoreWork { Task { await self.syncCloud() } }
            }
        }
        do {
            let session = try await authClient.validSession()
            guard scopeGeneration == generation, session.account.id == owner,
                  (try authClient.bootstrapSession())?.account.id == owner else { return }
            let blocked = Set(cloudState.conflicts.map(\.itemId))
            let sent = try PlannerCloudCoding.batch(cloudState.pending.filter { !blocked.contains($0.item.id) }, cursor: cloudState.cursor)
            let result = try await cloudClient.sync(PlannerCloudRequest(changes: sent, cursor: cloudState.cursor), session: session)
            guard scopeGeneration == generation, (try authClient.bootstrapSession())?.account.id == owner else { return }
            var state = cloudState
            let accepted = Set(result.acceptedMutationIds)
            state.pending.removeAll { accepted.contains($0.mutationId) }
            for conflict in result.conflicts {
                state.conflicts.removeAll { $0.itemId == conflict.itemId }
                if conflict.remote?.item.deletedAt != nil,
                   state.pending.first(where: { $0.item.id == conflict.itemId })?.item.deletedAt != nil {
                    state.pending.removeAll { $0.item.id == conflict.itemId }
                    continue
                }
                state.conflicts.append(conflict)
            }
            for remote in result.items {
                state.revisions[remote.item.id.uuidString] = max(state.revisions[remote.item.id.uuidString] ?? 0, remote.revision)
                if let index = state.pending.firstIndex(where: { $0.item.id == remote.item.id }) {
                    // A later local edit made while the accepted request was in flight is rebased,
                    // while actual conflicts remain pending for an explicit decision.
                    if sent.contains(where: { $0.item.id == remote.item.id && accepted.contains($0.mutationId) }) {
                        state.pending[index].baseRevision = remote.revision
                        state.pending[index].mutationId = UUID()
                        if let conflictIndex = state.conflicts.firstIndex(where: {
                            $0.itemId == remote.item.id && $0.pendingAlternative.map { accepted.contains($0.mutationId) } == true
                        }) {
                            state.conflicts[conflictIndex].remote = remote
                            state.conflicts[conflictIndex].pendingAlternative = nil
                        }
                    }
                    continue
                }
                let previous = state.items.first { $0.id == remote.item.id }
                state.items.removeAll { $0.id == remote.item.id }
                state.items.append(remote.item.local(preserving: previous))
            }
            state.cursor = max(state.cursor, result.cursor)
            try cloudPersistence.save(state, owner: owner)
            cloudState = state; records = state.items; cloudConflicts = state.conflicts
            publishItems(); cloudError = nil
            hasMoreWork = !accepted.isEmpty && state.pending.contains { pending in !state.conflicts.contains { $0.itemId == pending.item.id } }
        } catch {
            guard scopeGeneration == generation else { return }
            cloudError = AppL10n.string("planner.cloud.error")
        }
    }

    func resolveCloudConflict(id: UUID, keepLocal: Bool) async throws {
        refreshAccountScope()
        guard let owner = cloudOwnerID, let conflict = cloudState.conflicts.first(where: { $0.itemId == id }) else { return }
        var state = cloudState
        let local = state.items.first { $0.id == id }
        state.conflicts.removeAll { $0.itemId == id }; state.pending.removeAll { $0.item.id == id }
        if keepLocal, var item = local {
            if conflict.remote?.item.deletedAt != nil {
                // Deleted IDs are never resurrected; retaining a local edit creates a new item.
                item.id = UUID(); item.deletedAt = nil; item.createdAt = now()
                item.calendarSyncEnabled = false; item.calendarEventIdentifier = nil
                item.calendarNeedsSync = false; item.calendarLastStart = nil; item.calendarLastEnd = nil
                if let remote = conflict.remote {
                    state.items.removeAll { $0.id == id }; state.items.append(remote.item.local(preserving: local))
                }
            } else { state.items.removeAll { $0.id == id } }
            item.updatedAt = now(); state.items.append(item)
            state.pending.append(PlannerCloudChange(item: PlannerCloudItem(item),
                baseRevision: item.id == id ? conflict.remote?.revision ?? 0 : 0, mutationId: UUID()))
        } else {
            state.items.removeAll { $0.id == id }
            if let remote = conflict.remote { state.items.append(remote.item.local(preserving: local)) }
            if let pending = conflict.pendingAlternative { state.pending.append(pending) }
        }
        try cloudPersistence.save(state, owner: owner)
        cloudState = state; records = state.items; cloudConflicts = state.conflicts
        publishItems()
        await syncCloud(); await syncPending(requestAccess: false)
    }

    private func publishItems() {
        items = records.filter { $0.deletedAt == nil }.sorted {
            if $0.orderingDate != $1.orderingDate { return ($0.orderingDate ?? .distantFuture) < ($1.orderingDate ?? .distantFuture) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
