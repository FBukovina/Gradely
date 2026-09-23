import Foundation
import UserNotifications

@MainActor
protocol PlannerNotificationScheduling: AnyObject {
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func remove(identifiers: [String])
    func add(_ reminder: PlannerReminder) async throws
}

@MainActor
final class SystemPlannerNotificationCenter: PlannerNotificationScheduling {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func remove(identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func add(_ reminder: PlannerReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["url": reminder.deepLink.absoluteString, "plannerEventIDs": reminder.eventIDs.map(\.uuidString)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
}

/// Device-local opt-in. Grade alerts remain owned by the existing backend APNs pipeline.
@MainActor
final class PlannerNotificationScheduler {
    static let enabledKey = "gradey.plannerReminders.enabled.v1"
    private let defaults: UserDefaults
    private let center: any PlannerNotificationScheduling
    private var revision = 0
    private var pendingDesired: [PlannerReminder]?
    private var isReconciling = false
    private(set) var errorMessage: String?

    init(userDefaults: UserDefaults = .standard, center: (any PlannerNotificationScheduling)? = nil) {
        defaults = userDefaults
        self.center = center ?? SystemPlannerNotificationCenter()
    }
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func reconcile(items: [PlannerItem], scope: SchoolDataScope?, preferences: NotificationPreferences,
                   now: Date = Date(), calendar: Calendar = .current) async {
        revision += 1
        errorMessage = nil
        let events = PlannerEventProjection.events(from: items, scope: scope)
        pendingDesired = isEnabled ? PlannerReminderEngine.make(events: events, preferences: preferences, now: now, calendar: calendar) : []
        await drain()
    }

    func cancelAll() async {
        revision += 1
        pendingDesired = []
        await drain()
    }

    private func drain() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        while let requested = pendingDesired {
            pendingDesired = nil
            let token = revision
            let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(PlannerReminderEngine.identifierPrefix) }
            guard token == revision else { continue }
            let authorized = await center.isAuthorized()
            guard token == revision else { continue }
            let desired = authorized && isEnabled ? requested : []
            let desiredIDs = Set(desired.map(\.id))
            center.remove(identifiers: pending.filter { !desiredIDs.contains($0) })
            for reminder in desired {
                guard token == revision else { break }
                do { try await center.add(reminder) }
                catch { if token == revision { errorMessage = error.localizedDescription } }
                // A newer request is queued, never raced, so it will replace or remove this add.
            }
        }
    }
}
