import Foundation
import Observation

/// One app-wide instance: Today, Timetable, Settings and the Taneční screen
/// all read the same course, events and notice board.
@MainActor
@Observable
final class VavruskaViewModel {
    enum Phase: Equatable {
        case disconnected
        case connected
        case needsReconnect
    }

    private(set) var course: VavruskaStoredCourse?
    private(set) var snapshot = VavruskaSnapshot()
    private(set) var isRefreshing = false
    private(set) var lastRefreshFailed = false
    private(set) var ticketAlertsEnabled: Bool
    private(set) var seenNoticeDigest: String?

    /// The single writer of `settings.showVavruska`.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: VavruskaSettings.enabledKey)
            Task { await reconcileNotifications() }
        }
    }

    @ObservationIgnored private let repository: VavruskaRepository
    @ObservationIgnored private let notificationScheduler: VavruskaNotificationScheduler
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(
        repository: VavruskaRepository,
        notificationScheduler: VavruskaNotificationScheduler? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.notificationScheduler = notificationScheduler ?? VavruskaNotificationScheduler(userDefaults: userDefaults)
        defaults = userDefaults
        isEnabled = userDefaults.bool(forKey: VavruskaSettings.enabledKey)
        ticketAlertsEnabled = userDefaults.bool(forKey: VavruskaSettings.ticketAlertsKey)
        seenNoticeDigest = userDefaults.string(forKey: VavruskaSettings.seenNoticeDigestKey)
        reloadFromStorage()
    }

    var phase: Phase {
        guard course != nil else { return .disconnected }
        return snapshot.calendarUnavailable ? .needsReconnect : .connected
    }

    /// Whether Today, Timetable and the Taneční link should show anything.
    var isActive: Bool { isEnabled && course != nil }

    // MARK: - Lifecycle

    /// Keychain + cache only, no network. Also realigns after Settings changed things.
    func reloadFromStorage() {
        course = repository.storedCourse()
        snapshot = course == nil ? VavruskaSnapshot() : (repository.cachedSnapshot() ?? VavruskaSnapshot())
    }

    func connect(password: String) async throws {
        course = try await repository.connect(password: password)
        snapshot = VavruskaSnapshot()
        lastRefreshFailed = false
        isEnabled = true
        await performRefresh(force: true, includeTicketLinks: true)
    }

    /// Cheap to call often: the repository decides what is actually due.
    func refreshIfNeeded(force: Bool = false, includeTicketLinks: Bool = false) async {
        guard isActive else { return }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh(force: force, includeTicketLinks: includeTicketLinks) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func disconnect() async {
        inFlight?.cancel()
        repository.disconnect()
        course = nil
        snapshot = VavruskaSnapshot()
        lastRefreshFailed = false
        seenNoticeDigest = nil
        defaults.removeObject(forKey: VavruskaSettings.seenNoticeDigestKey)
        await notificationScheduler.cancelAll()
    }

    func clearCache() {
        repository.clearCache()
        snapshot = VavruskaSnapshot()
    }

    private func performRefresh(force: Bool, includeTicketLinks: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await repository.refresh(force: force, includeTicketLinks: includeTicketLinks)
            guard course != nil else { return }
            snapshot = result.snapshot
            lastRefreshFailed = result.failed
            // The first board after connecting is the baseline, not news.
            if seenNoticeDigest == nil, let digest = snapshot.noticeBoard?.digest {
                markNoticeBoardSeen(digest: digest)
            }
        } catch {
            lastRefreshFailed = true
        }
        await reconcileNotifications()
    }

    // MARK: - Notifications

    /// Injected by ContentView; asks for notification permission on first opt-in.
    @ObservationIgnored var notificationAuthorizer: (any NotificationAuthorizing)?

    func setTicketAlertsEnabled(_ enabled: Bool) async {
        if enabled, let notificationAuthorizer {
            var status = await notificationAuthorizer.authorizationStatus()
            if status == .denied {
                notificationAuthorizer.openSystemSettings()
                return
            }
            if status == .notDetermined {
                status = await notificationAuthorizer.requestAuthorization()
            }
            guard status == .authorized else { return }
        }
        ticketAlertsEnabled = enabled
        notificationScheduler.isEnabled = enabled
        await reconcileNotifications()
    }

    func reconcileNotifications() async {
        await notificationScheduler.reconcile(sales: snapshot.ticketSales, integrationEnabled: isActive)
    }

    func cancelNotifications() async {
        await notificationScheduler.cancelAll()
    }

    // MARK: - Notice board

    var hasUnreadNotices: Bool {
        guard let digest = snapshot.noticeBoard?.digest, let seenNoticeDigest else { return false }
        return digest != seenNoticeDigest
    }

    func markNoticeBoardSeen() {
        guard let digest = snapshot.noticeBoard?.digest else { return }
        markNoticeBoardSeen(digest: digest)
    }

    private func markNoticeBoardSeen(digest: String) {
        seenNoticeDigest = digest
        defaults.set(digest, forKey: VavruskaSettings.seenNoticeDigestKey)
    }

    // MARK: - Derived

    /// Lessons on a given civil day, for the Timetable's "after school" block.
    func events(on day: Date, calendar: Calendar = .current) -> [VavruskaEvent] {
        guard isActive else { return [] }
        return snapshot.events.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    func upcomingEvents(after now: Date) -> [VavruskaEvent] {
        snapshot.events.filter { $0.end > now }
    }

    func pastEvents(before now: Date) -> [VavruskaEvent] {
        snapshot.events.filter { $0.end <= now }.reversed()
    }

    /// Sales opening within three weeks, or open now for an event still ahead.
    func relevantTicketSales(now: Date) -> [VavruskaTicketSale] {
        snapshot.ticketSales.filter { sale in
            sale.eventStart > now && sale.saleStart < now.addingTimeInterval(21 * 24 * 60 * 60)
        }
    }

    func isCourseEnded(at now: Date) -> Bool {
        guard let last = snapshot.events.map(\.end).max() else { return false }
        return last < now
    }

    var lessonCount: Int {
        snapshot.events.filter { !$0.kind.isEvent }.count
    }
}
