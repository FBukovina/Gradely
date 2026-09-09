import Foundation
import Observation

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

    init(persistence: any PlannerPersisting, calendarService: any PlannerCalendarSyncing, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.calendarService = calendarService
        self.now = now
    }

    var pendingCalendarCount: Int { records.filter(\.calendarNeedsSync).count }

    func loadIfNeeded() {
        guard !isLoaded else { return }
        do {
            records = try persistence.load()
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
        await syncPending(requestAccess: false)
    }

    func save(_ draft: PlannerItem) async throws {
        loadIfNeeded()
        guard isLoaded else { throw PlannerError.storageUnavailable }
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { throw PlannerError.titleRequired }
        // Sync is on by default, so an undated item simply stays local rather than
        // failing a save over a date the user was never asked for.
        if !item.hasCalendarDate { item.calendarSyncEnabled = false }
        item.notes = item.notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let previous = records.first { $0.id == item.id }
        guard previous?.deletedAt == nil else { throw PlannerError.storageUnavailable }
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
        try commit(updated) // Local source of truth is durable before contacting Calendar.
        await syncPending(requestAccess: item.calendarNeedsSync)
    }

    func setCompleted(_ completed: Bool, id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.isCompleted = completed
        try await save(item)
    }

    func delete(id: UUID) async throws {
        guard var item = records.first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        var updated = records.filter { $0.id != id }
        if item.calendarLastStart != nil || item.calendarEventIdentifier != nil {
            item.calendarSyncEnabled = false
            item.calendarNeedsSync = true
            item.deletedAt = now()
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
    }

    func attachedItems(to lesson: ScheduledLesson, on day: ScheduledDay, scope: SchoolDataScope) -> [PlannerItem] {
        items.filter { !$0.isCompleted && $0.lesson?.matches(lesson: lesson, day: day, scope: scope) == true }
    }

    func syncPending(requestAccess: Bool) async {
        guard isLoaded, !isSyncing, pendingCalendarCount > 0 else { return }
        isSyncing = true
        defer { isSyncing = false }
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
                if item.deletedAt == nil { updated.append(item) }
                try commit(updated)
            } catch {
                calendarError = (error as? PlannerError)?.localizedDescription ?? PlannerError.calendarUnavailable.localizedDescription
            }
        }
    }

    private func commit(_ updated: [PlannerItem]) throws {
        do {
            try persistence.save(updated)
            records = updated
            publishItems()
            storageError = nil
            if pendingCalendarCount == 0 { calendarError = nil }
        } catch {
            storageError = PlannerError.storageUnavailable.localizedDescription
            throw PlannerError.storageUnavailable
        }
    }

    private func publishItems() {
        items = records.filter { $0.deletedAt == nil }.sorted {
            if $0.orderingDate != $1.orderingDate { return ($0.orderingDate ?? .distantFuture) < ($1.orderingDate ?? .distantFuture) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
