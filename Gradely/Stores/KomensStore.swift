import Foundation
import Observation

/// Komens messages and the school's noticeboard for the signed-in account.
/// The repository's cache is the durable copy; this is what the envelope
/// button and the messages sheet read.
@MainActor @Observable
final class KomensStore {
    private(set) var received: [KomensMessage] = []
    private(set) var noticeboard: [KomensMessage] = []
    private(set) var isSupported = false
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private let repository: SchoolRepository
    private let now: () -> Date
    @ObservationIgnored private var identity: String?
    @ObservationIgnored private var lastSuccessAt: Date?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Opened here, so they stay read even if a list loaded meanwhile says otherwise.
    @ObservationIgnored private var readIDs: Set<String> = []

    init(repository: SchoolRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    /// Messages that are unread, counting one pinned to the noticeboard only once.
    var unreadCount: Int {
        Set((received + noticeboard).filter { !$0.isRead }.map(\.messageID)).count
    }

    func messages(in box: KomensBox) -> [KomensMessage] {
        box == .received ? received : noticeboard
    }

    func unreadCount(in box: KomensBox) -> Int {
        messages(in: box).filter { !$0.isRead }.count
    }

    func message(id: String) -> KomensMessage? {
        received.first { $0.id == id } ?? noticeboard.first { $0.id == id }
    }

    /// Shows the cached lists for the current account, dropping another account's.
    func activate() {
        let session = try? repository.currentStoredSession()
        let current = session.map { [SchoolDataScope(session: $0).rawValue, repository.sessionGeneration.uuidString].joined(separator: "\u{1F}") }
        guard current != identity else { return }
        invalidate()
        identity = current
        guard let session, session.provider == .bakalari else { return }
        isSupported = true
        if let cached = repository.loadCachedKomens() {
            apply(cached.value)
        }
    }

    func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
        identity = nil
        lastSuccessAt = nil
        isSupported = false
        isRefreshing = false
        hasLoaded = false
        errorMessage = nil
        readIDs = []
        received = []
        noticeboard = []
    }

    func refresh(force: Bool = false) async {
        activate()
        guard isSupported else { return }
        if let refreshTask { return await refreshTask.value }
        if !force, let lastSuccessAt, now().timeIntervalSince(lastSuccessAt) < 900 { return }
        let requestedIdentity = identity
        isRefreshing = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.identity == requestedIdentity {
                    self.isRefreshing = false
                    self.refreshTask = nil
                }
            }
            do {
                let snapshot = try await self.repository.loadKomens()
                guard self.identity == requestedIdentity else { return }
                self.apply(snapshot)
                self.lastSuccessAt = self.now()
                self.errorMessage = nil
            } catch {
                guard self.identity == requestedIdentity, !(error is CancellationError) else { return }
                self.errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }

    /// Shows the message as read at once. If Bakaláři refuses, it turns unread
    /// again and is marked the next time it's opened.
    func markRead(_ message: KomensMessage) async {
        guard !message.isRead, !readIDs.contains(message.messageID) else { return }
        let requestedIdentity = identity
        readIDs.insert(message.messageID)
        setRead(true, messageID: message.messageID)
        do {
            try await repository.markKomensRead(id: message.messageID)
        } catch {
            guard identity == requestedIdentity else { return }
            readIDs.remove(message.messageID)
            setRead(false, messageID: message.messageID)
        }
    }

    func download(_ attachment: SchoolAttachment) async throws -> URL {
        try await repository.downloadAttachment(attachment)
    }

    private func apply(_ snapshot: KomensSnapshot) {
        received = messages(from: snapshot.received, box: .received)
        noticeboard = messages(from: snapshot.noticeboard, box: .noticeboard)
        hasLoaded = true
    }

    private func messages(from dtos: [KomensMessageDTO], box: KomensBox) -> [KomensMessage] {
        KomensMessage.sorted(dtos.filter { !$0.hidden }.map { dto in
            var message = KomensMessage(dto, box: box)
            if readIDs.contains(message.messageID) { message.isRead = true }
            return message
        })
    }

    private func setRead(_ isRead: Bool, messageID: String) {
        for index in received.indices where received[index].messageID == messageID { received[index].isRead = isRead }
        for index in noticeboard.indices where noticeboard[index].messageID == messageID { noticeboard[index].isRead = isRead }
    }
}
