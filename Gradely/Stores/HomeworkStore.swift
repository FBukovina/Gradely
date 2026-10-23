import Foundation
import Observation

/// Homework from the school for the signed-in account. The repository's cache
/// is the durable copy; this is what the Planner, Today and lessons read.
@MainActor @Observable
final class HomeworkStore {
    private(set) var items: [Homework] = []
    private(set) var scope: SchoolDataScope?
    private(set) var isSupported = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    /// Done ticks still on their way to Bakaláři.
    private(set) var pendingIDs: Set<String> = []
    private let repository: SchoolRepository
    private let now: () -> Date
    @ObservationIgnored private var identity: String?
    @ObservationIgnored private var lastSuccessAt: Date?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(repository: SchoolRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    /// Shows the cached list for the current account, dropping another account's.
    func activate() {
        let session = try? repository.currentStoredSession()
        let current = session.map { [SchoolDataScope(session: $0).rawValue, repository.sessionGeneration.uuidString].joined(separator: "\u{1F}") }
        guard current != identity else { return }
        invalidate()
        identity = current
        guard let session, session.provider == .bakalari else { return }
        scope = SchoolDataScope(session: session)
        isSupported = true
        if let cached = repository.loadCachedHomework() {
            items = Self.sorted(cached.response.homeworks.map(Homework.init))
        }
    }

    func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
        identity = nil
        lastSuccessAt = nil
        scope = nil
        isSupported = false
        isRefreshing = false
        errorMessage = nil
        pendingIDs = []
        items = []
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
                let response = try await self.repository.loadHomework()
                guard self.identity == requestedIdentity else { return }
                // A tick still in flight keeps the state the user just chose.
                self.items = Self.sorted(response.homeworks.map(Homework.init).map { homework in
                    var homework = homework
                    if self.pendingIDs.contains(homework.id),
                       let local = self.items.first(where: { $0.id == homework.id }) {
                        homework.isDone = local.isDone
                    }
                    return homework
                })
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

    /// Shows the tick at once and puts it back if Bakaláři refuses it.
    func setDone(_ isDone: Bool, id: String) async throws {
        guard let index = items.firstIndex(where: { $0.id == id }), !pendingIDs.contains(id) else { return }
        let requestedIdentity = identity
        let previous = items[index].isDone
        items[index].isDone = isDone
        pendingIDs.insert(id)
        defer { if identity == requestedIdentity { pendingIDs.remove(id) } }
        do {
            try await repository.setHomeworkDone(id: id, isDone: isDone)
        } catch {
            if identity == requestedIdentity, let index = items.firstIndex(where: { $0.id == id }) {
                items[index].isDone = previous
            }
            throw error
        }
    }

    func download(_ attachment: HomeworkAttachment) async throws -> URL {
        try await repository.downloadHomeworkAttachment(attachment)
    }

    func homework(id: String) -> Homework? { items.first { $0.id == id } }

    func homework(eventID: UUID) -> Homework? {
        guard let scope else { return nil }
        return items.first { $0.eventID(scope: scope) == eventID }
    }

    /// Open homework that is due today or later, as Planner events.
    func upcomingEvents(at date: Date? = nil) -> [SchoolEvent] {
        guard let scope else { return [] }
        let now = date ?? self.now()
        return items.filter(\.isOpen).compactMap { $0.event(scope: scope) }.filter { $0.expiresAt > now }
    }

    /// Homework given in this lesson, then homework due in it.
    func items(for lesson: ScheduledLesson, on day: ScheduledDay, calendar: Calendar = .current) -> [Homework] {
        let assigned = lesson.homeworkIDs.compactMap { id in items.first { $0.id == id } }
        var due: [Homework] = []
        if let subjectID = lesson.subjectID, let date = day.date {
            due = items.filter { homework in
                homework.subjectID == subjectID
                    && !lesson.homeworkIDs.contains(homework.id)
                    && homework.dueDay(in: calendar).map { calendar.isDate($0, inSameDayAs: date) } == true
            }
        }
        return assigned + due
    }

    private static func sorted(_ items: [Homework]) -> [Homework] {
        items.sorted {
            switch ($0.dueOn, $1.dueOn) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return ($0.subjectLabel ?? "", $0.id) < ($1.subjectLabel ?? "", $1.id)
            }
        }
    }
}
