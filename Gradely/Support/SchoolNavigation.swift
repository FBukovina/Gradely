import Foundation
import Observation
import UserNotifications

struct PlannerNavigationTarget: Equatable, Identifiable {
    let day: Date?
    let itemID: UUID?
    var id: String { "\(day?.timeIntervalSince1970 ?? 0)-\(itemID?.uuidString ?? "day")" }

    init?(url: URL, calendar: Calendar = .current) {
        guard ["gradey", "gradely"].contains(url.scheme ?? ""),
              url.host == "planner" || url.path == "/planner",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = components.queryItems ?? []
        let path = url.pathComponents.filter { $0 != "/" }
        let rawItemID = values.first(where: { $0.name == "item" })?.value
            ?? (path.count == 2 && path[0] == "item" ? path[1] : nil)
        if let rawItemID {
            guard let parsed = UUID(uuidString: rawItemID) else { return nil }
            itemID = parsed
        } else { itemID = nil }
        if let key = values.first(where: { $0.name == "day" })?.value {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let parsed = formatter.date(from: key), formatter.string(from: parsed) == key else { return nil }
            day = parsed
        } else { day = nil }
    }
}

enum PlannerDayProjection {
    static func day(for item: PlannerItem, calendar: Calendar = .current) -> Date? {
        guard let date = item.orderingDate else { return nil }
        let hasTime = item.dueDate != nil ? item.dueHasTime : item.lesson?.start != nil
        if hasTime { return calendar.startOfDay(for: date) }
        return calendar.date(from: item.calendar.dateComponents([.year, .month, .day], from: date))
    }
}

enum SchoolNotificationRouting {
    static func url(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let value = userInfo["url"] as? String, let url = URL(string: value), isSupported(url) else { return nil }
        return url
    }

    static func isSupported(_ url: URL) -> Bool {
        guard ["gradey", "gradely"].contains(url.scheme ?? "") else { return false }
        if PlannerNavigationTarget(url: url) != nil || GradeySiriID.from(url: url) != nil { return true }
        return ["marks", "subjects", "timetable"].contains(url.host ?? "")
            || ["/marks", "/subjects", "/timetable"].contains(url.path)
    }
}

/// Retains a notification destination until the signed-in root is ready, including cold launch.
@MainActor @Observable
final class SchoolNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SchoolNotificationRouter()
    var pendingURL: URL?
    @ObservationIgnored private weak var forwardingDelegate: (any UNUserNotificationCenterDelegate)?

    @discardableResult func enqueue(userInfo: [AnyHashable: Any]) -> Bool {
        guard let url = SchoolNotificationRouting.url(from: userInfo) else { return false }
        pendingURL = url
        return true
    }

    func takePendingURL(ifReady isReady: Bool) -> URL? {
        guard isReady else { return nil }
        defer { pendingURL = nil }
        return pendingURL
    }

    func install(center: UNUserNotificationCenter = .current()) {
        guard center.delegate !== self else { return }
        forwardingDelegate = center.delegate
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if self.enqueue(userInfo: response.notification.request.content.userInfo) {
                completionHandler()
            } else if let delegate = self.forwardingDelegate,
                      delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                delegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if let delegate = self.forwardingDelegate,
               delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
                delegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            } else {
                completionHandler([])
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in self.forwardingDelegate?.userNotificationCenter?(center, openSettingsFor: notification) }
    }
}
