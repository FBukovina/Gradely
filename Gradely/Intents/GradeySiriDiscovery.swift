import AppIntents
import CoreSpotlight
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class GradeySiriDiscoverySettings {
    static let shared = GradeySiriDiscoverySettings()
    static let enabledKey = "settings.siri.schoolDiscovery.v1"
    private let defaults: UserDefaults
    private(set) var isEnabled: Bool
    private(set) var errorMessage: String?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }
    func setError(_ error: Error?) { errorMessage = error == nil ? nil : AppL10n.string("siri.discovery.error") }
}

@MainActor protocol GradeySiriIndexing {
    func clear() async throws
    func replace(with snapshot: GradeySiriSnapshot) async throws
}

@MainActor final class GradeySiriSpotlightIndex: NSObject, GradeySiriIndexing, CSSearchableIndexDelegate {
    private let index = CSSearchableIndex(name: "com.bukovinafilip.gradey.siri.v1", protectionClass: .complete)
    var onReindex: (() async -> Void)?
    override init() { super.init(); index.indexDelegate = self }
    func clear() async throws { try await index.deleteAllSearchableItems() }
    func replace(with snapshot: GradeySiriSnapshot) async throws {
        var items: [CSSearchableItem] = []
        func add<E: IndexedEntity>(_ entity: E, id: String, modified: Date) {
            let attributes = entity.attributeSet
            attributes.associateAppEntity(entity)
            attributes.contentURL = GradeySiriID(id)?.url
            // Include provenance even for schema entities whose standard fields have no freshness property.
            let provenance = GradeyIntentService.freshness(modified, stale: true)
            attributes.contentDescription = [attributes.contentDescription, provenance].compactMap { $0 }.joined(separator: ". ")
            let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: GradeySiriID(id)?.scope, attributeSet: attributes)
            item.expirationDate = Date().addingTimeInterval(24 * 60 * 60)
            items.append(item)
        }
        for record in snapshot.subjects {
            if #available(iOS 27, macOS 27, *) { add(GradeyIntelligenceSubjectEntity(record), id: record.id, modified: record.updatedAt) }
            else { add(GradeySubjectEntity(record), id: record.id, modified: record.updatedAt) }
        }
        for record in snapshot.grades {
            if #available(iOS 27, macOS 27, *) { add(GradeyIntelligenceGradeEntity(record), id: record.id, modified: record.updatedAt) }
            else { add(GradeyGradeEntity(record), id: record.id, modified: record.updatedAt) }
        }
        for record in snapshot.lessons {
            if #available(iOS 27, macOS 27, *) { add(GradeyCalendarLessonEntity(record), id: record.id, modified: record.updatedAt) }
            else { add(GradeyLessonEntity(record), id: record.id, modified: record.updatedAt) }
        }
        for record in snapshot.planner {
            if #available(iOS 27, macOS 27, *), record.type != PlannerItemType.note.rawValue {
                add(GradeyReminderEntity(record), id: record.id, modified: record.updatedAt)
            } else { add(GradeyPlannerEntity(record), id: record.id, modified: record.updatedAt) }
        }
        // Identifiers are unique even if a provider sends the same lesson/grade more than once.
        let unique = Dictionary(items.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        try await index.indexSearchableItems(Array(unique.values))
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in await onReindex?(); acknowledgementHandler() }
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in await onReindex?(); acknowledgementHandler() }
    }
}

extension Notification.Name {
    static let gradeySiriDataDidInvalidate = Notification.Name("gradey.siri.dataDidInvalidate")
}

/// Serial replacement keeps a late indexing completion from undoing a newer privacy/account purge.
@MainActor final class GradeySiriDiscoveryCoordinator {
    private let service: GradeyIntentService
    private let settings: GradeySiriDiscoverySettings
    private let index: any GradeySiriIndexing
    private var revision = UUID()
    private var worker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    init(service: GradeyIntentService, settings: GradeySiriDiscoverySettings = .shared, index: (any GradeySiriIndexing)? = nil) {
        self.service = service; self.settings = settings
        self.index = index ?? GradeySiriSpotlightIndex()
        if let live = self.index as? GradeySiriSpotlightIndex {
            live.onReindex = { [weak self] in await self?.reconcileNow() }
        }
    }
    func start() {
        guard !started else { return }
        started = true
        for name in [Notification.Name.gradelySchoolAccountDidChange, .gradeySiriDataDidInvalidate, UserDefaults.didChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.requestReconcile() }
            })
        }
        observe()
        requestReconcile()
    }
    private func observe() {
        withObservationTracking {
            _ = settings.isEnabled
            _ = service.snapshot.revision
            _ = service.planner.items
            _ = AgeAttestationStore.shared.allowsAppUse
            _ = PrivacyPolicyConsentStore.shared.needsAcknowledgement
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
                self?.requestReconcile()
            }
        }
    }
    func requestReconcile() {
        revision = UUID()
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            var processed: UUID
            repeat {
                processed = revision
                do {
                    // Always purge first, including on launch after an interrupted removal.
                    try await index.clear()
                    guard settings.isEnabled, let expected = try? service.access() else { continue }
                    let snapshot = try await service.discoverySnapshot()
                    guard processed == revision, settings.isEnabled else { continue }
                    try service.validate(expected)
                    try await index.replace(with: snapshot)
                    if processed != revision || !settings.isEnabled || (try? service.access()) != expected {
                        try await index.clear()
                    }
                    settings.setError(nil)
                } catch {
                    // Missing setup is an ordinary empty index, not an indexing failure.
                    if (try? service.access()) == nil { try? await index.clear() }
                    else { settings.setError(error) }
                }
            } while processed != revision
            worker = nil
        }
    }
    func reconcileNow() async { requestReconcile(); await worker?.value }
}

struct GradeySiriDiscoverySettingsView: View {
    @State private var settings = GradeySiriDiscoverySettings.shared
    @State private var confirming = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { settings.isEnabled }, set: { enabled in
                if enabled { confirming = true } else { settings.setEnabled(false) }
            })) { Text("siri.discovery.title") }
                .accessibilityIdentifier("siriDiscoveryToggle")
            Text("siri.discovery.description").font(.footnote).foregroundStyle(.secondary)
            if let error = settings.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
        .alert("siri.discovery.title", isPresented: $confirming) {
            Button("siri.discovery.enable") { settings.setEnabled(true) }
            Button("action.cancel", role: .cancel) { }
        } message: { Text("siri.discovery.description") }
    }
}
