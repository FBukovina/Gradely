import Foundation

/// Device-local alert when ticket sales for the user's prodloužená or ball
/// open. Reuses the planner's notification center and reconcile pattern.
@MainActor
final class VavruskaNotificationScheduler {
    static let identifierPrefix = "gradey.vavruska.sale."
    private static let horizon: TimeInterval = 60 * 24 * 60 * 60
    private static let maxReminders = 10

    private let defaults: UserDefaults
    private let center: any PlannerNotificationScheduling
    private var revision = 0
    private var pendingDesired: [PlannerReminder]?
    private var isReconciling = false

    init(userDefaults: UserDefaults = .standard, center: (any PlannerNotificationScheduling)? = nil) {
        defaults = userDefaults
        self.center = center ?? SystemPlannerNotificationCenter()
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: VavruskaSettings.ticketAlertsKey) }
        set { defaults.set(newValue, forKey: VavruskaSettings.ticketAlertsKey) }
    }

    func reconcile(sales: [VavruskaTicketSale], integrationEnabled: Bool, now: Date = Date()) async {
        revision += 1
        guard isEnabled, integrationEnabled else {
            pendingDesired = []
            await drain()
            return
        }
        pendingDesired = sales
            .filter { $0.saleStart > now.addingTimeInterval(60) && $0.saleStart < now.addingTimeInterval(Self.horizon) }
            .sorted { $0.saleStart < $1.saleStart }
            .prefix(Self.maxReminders)
            .map { sale in
                PlannerReminder(
                    id: Self.identifierPrefix + sale.id,
                    eventIDs: [],
                    fireDate: sale.saleStart,
                    expiresAt: sale.eventStart,
                    title: AppL10n.string("vavruska.notification.sale.title"),
                    body: String(
                        format: AppL10n.string("vavruska.notification.sale.body"),
                        sale.eventTitle,
                        SchoolDateFormatting.weekdayShortDate(sale.eventStart)
                    ),
                    deepLink: URL(string: "gradey://vavruska")!
                )
            }
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
            let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(Self.identifierPrefix) }
            guard token == revision else { continue }
            let authorized = await center.isAuthorized()
            guard token == revision else { continue }
            let desired = authorized ? requested : []
            let desiredIDs = Set(desired.map(\.id))
            center.remove(identifiers: pending.filter { !desiredIDs.contains($0) })
            // Re-adding replaces a pending request with the same id, so moved sale times update.
            for reminder in desired {
                guard token == revision else { break }
                try? await center.add(reminder)
            }
        }
    }
}
