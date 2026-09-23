import EventKit
import Foundation

@MainActor
protocol PlannerCalendarSyncing {
    var hasAccess: Bool { get }
    func requestAccess() async throws
    func upsert(_ item: PlannerItem) throws -> String
    func remove(_ item: PlannerItem) throws
}

/// One-way export only. Reads are limited to identifying Gradey-owned events for update/removal.
@MainActor
final class PlannerCalendarService: PlannerCalendarSyncing {
    private lazy var eventStore = EKEventStore()
    private let defaults: UserDefaults
    private let calendarKey = "planner.calendarIdentifier"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws {
        if hasAccess { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .notDetermined || status == .writeOnly else { throw PlannerError.calendarPermission }
        // Full access is necessary to update/remove previously created events. Write-only cannot
        // fetch those events. Request only when the user explicitly saves or retries calendar work.
        guard try await eventStore.requestFullAccessToEvents() else { throw PlannerError.calendarPermission }
    }

    func upsert(_ item: PlannerItem) throws -> String {
        guard hasAccess else { throw PlannerError.calendarPermission }
        let data = try PlannerCalendarEventData.make(from: item)
        let event = ownedEvent(for: item) ?? EKEvent(eventStore: eventStore)
        if event.calendar == nil {
            event.calendar = try gradeyCalendar()
        }
        guard event.calendar.allowsContentModifications else { throw PlannerError.calendarUnavailable }
        event.title = data.title
        event.notes = data.notes
        event.startDate = data.start
        event.endDate = data.end
        event.isAllDay = data.isAllDay
        event.timeZone = TimeZone(identifier: data.timeZoneIdentifier)
        event.url = data.url
        try eventStore.save(event, span: .thisEvent, commit: true)
        guard let identifier = event.eventIdentifier else { throw PlannerError.calendarUnavailable }
        return identifier
    }

    func remove(_ item: PlannerItem) throws {
        guard hasAccess else { throw PlannerError.calendarPermission }
        // A user-deleted event is already in the desired state.
        guard let event = ownedEvent(for: item) else { return }
        guard event.calendar.allowsContentModifications else { throw PlannerError.calendarUnavailable }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    private func ownedEvent(for item: PlannerItem) -> EKEvent? {
        if let identifier = item.calendarEventIdentifier,
           let event = eventStore.event(withIdentifier: identifier), event.url == item.calendarURL {
            return event
        }
        // Recover an identifier changed by Calendar, or a save interrupted before the identifier
        // reached disk. Only inspect bounded known date ranges in the dedicated calendar.
        let calendars = eventStore.calendars(for: .event).filter {
            $0.calendarIdentifier == defaults.string(forKey: calendarKey) || $0.title == "Gradey"
        }
        guard !calendars.isEmpty else { return nil }
        var ranges: [(Date, Date)] = []
        if let start = item.calendarLastStart, let end = item.calendarLastEnd { ranges.append((start, end)) }
        if let data = try? PlannerCalendarEventData.make(from: item) { ranges.append((data.start, data.end)) }
        for (start, end) in ranges {
            let predicate = eventStore.predicateForEvents(
                withStart: start.addingTimeInterval(-86_400),
                end: end.addingTimeInterval(86_400), calendars: calendars
            )
            if let event = eventStore.events(matching: predicate).first(where: { $0.url == item.calendarURL }) {
                return event
            }
        }
        return nil
    }

    private func gradeyCalendar() throws -> EKCalendar {
        if let identifier = defaults.string(forKey: calendarKey),
           let calendar = eventStore.calendar(withIdentifier: identifier), calendar.allowsContentModifications {
            return calendar
        }
        if let calendar = eventStore.calendars(for: .event).first(where: { $0.title == "Gradey" && $0.allowsContentModifications }) {
            defaults.set(calendar.calendarIdentifier, forKey: calendarKey)
            return calendar
        }
        var sources: [EKSource] = []
        if let source = eventStore.defaultCalendarForNewEvents?.source { sources.append(source) }
        sources += eventStore.sources.filter { source in
            [.local, .calDAV, .exchange].contains(source.sourceType)
                && !sources.contains(where: { $0.sourceIdentifier == source.sourceIdentifier })
        }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = "Gradey"
            calendar.source = source
            do {
                try eventStore.saveCalendar(calendar, commit: true)
                defaults.set(calendar.calendarIdentifier, forKey: calendarKey)
                return calendar
            } catch {
                continue // Some account sources prohibit creating calendars; try another source.
            }
        }
        throw PlannerError.calendarUnavailable
    }
}

/// Previews and mock environments never write to the user's Calendar.
@MainActor
final class UnavailablePlannerCalendarService: PlannerCalendarSyncing {
    var hasAccess: Bool { false }
    func requestAccess() async throws { throw PlannerError.calendarUnavailable }
    func upsert(_ item: PlannerItem) throws -> String { throw PlannerError.calendarUnavailable }
    func remove(_ item: PlannerItem) throws { throw PlannerError.calendarUnavailable }
}
