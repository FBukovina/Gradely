import Foundation
import Testing
@testable import Gradely

@MainActor
struct PlannerReminderTests {
    private let scope = SchoolDataScope(rawValue: "reminder-school")
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Prague")!
        return value
    }
    private func date(_ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    private func item(_ day: Int, type: PlannerItemType = .test, subjectID: String? = " M") -> PlannerItem {
        var value = PlannerItem()
        value.title = "Private preparation title"
        value.notes = "Private notes must not appear"
        value.type = type
        value.dueDate = date(day)
        value.dueHasTime = true
        value.timeZoneIdentifier = calendar.timeZone.identifier
        if let subjectID { value.subject = PlannerSubjectReference(scope: scope, id: subjectID, name: "Mathematics", abbreviation: "Math") }
        return value
    }

    @Test func projectionPreservesScopeRawIDsAndDatePrecedence() {
        let linked = item(12)
        let unscoped = item(12, subjectID: nil)
        var completed = item(12); completed.isCompleted = true
        var deleted = item(12); deleted.deletedAt = date(11)
        var undated = item(12); undated.dueDate = nil
        let values = [linked, unscoped, completed, deleted, undated]
        #expect(PlannerEventProjection.events(from: values, scope: scope).count == 2)
        #expect(PlannerEventProjection.events(from: values, scope: scope, subjectID: " M").map(\.id) == [linked.id])
        #expect(PlannerEventProjection.events(from: values, scope: scope, subjectID: "M").isEmpty)
        #expect(PlannerEventProjection.events(from: values, scope: SchoolDataScope(rawValue: "other")).map(\.id) == [unscoped.id])
        var precedence = linked
        precedence.linkedDate = date(11)
        #expect(PlannerEventProjection.events(from: [precedence], scope: scope).first?.date == date(12))
    }

    @Test func singleDailyAggregateHasSevenDayHorizonAndNoCatchup() throws {
        let events = PlannerEventProjection.events(from: [item(12), item(12, type: .homework), item(18), item(19)], scope: scope)
        let reminders = PlannerReminderEngine.make(events: events, preferences: .default, now: date(11, hour: 17), calendar: calendar)
        #expect(reminders.count == 2)
        #expect(reminders.first?.fireDate == date(11, hour: 18))
        #expect(reminders.first?.eventIDs.count == 2)
        let after = PlannerReminderEngine.make(events: events, preferences: .default, now: date(11, hour: 19), calendar: calendar)
        #expect(after.count == 1)
        #expect(!after.contains { $0.fireDate <= date(11, hour: 19) })
        #expect(try #require(reminders.first).body.contains("Private notes") == false)
    }

    @Test func quietHoursDeferBeforeDueAndNeverPastDeadline() {
        var preferences = NotificationPreferences.default
        preferences.quietHoursEnabled = true
        preferences.quietHoursStartMinute = 17 * 60
        preferences.quietHoursEndMinute = 7 * 60
        let events = PlannerEventProjection.events(from: [item(12)], scope: scope)
        #expect(PlannerReminderEngine.make(events: events, preferences: preferences, now: date(11, hour: 16), calendar: calendar).first?.fireDate == date(12, hour: 7))
        preferences.quietHoursEndMinute = 9 * 60
        #expect(PlannerReminderEngine.make(events: events, preferences: preferences, now: date(11, hour: 16), calendar: calendar).isEmpty)
        preferences.quietHoursEndMinute = preferences.quietHoursStartMinute
        #expect(PlannerReminderEngine.make(events: events, preferences: preferences, now: date(11, hour: 16), calendar: calendar).isEmpty)
    }

    @Test func privateCopyDoesNotContainSubjectOrPlannerContent() throws {
        var preferences = NotificationPreferences.default
        preferences.lockScreenDetail = .privateSummary
        let events = PlannerEventProjection.events(from: [item(12)], scope: scope)
        let reminder = try #require(PlannerReminderEngine.make(events: events, preferences: preferences, now: date(11, hour: 17), calendar: calendar).first)
        #expect(!reminder.body.contains("Math"))
        #expect(!reminder.body.contains("preparation title"))
    }

    @Test func traveledDateOnlyReminderAndTapUseTheSameCivilDay() throws {
        var authored = Calendar(identifier: .gregorian)
        authored.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var device = Calendar(identifier: .gregorian)
        device.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var value = item(12)
        value.timeZoneIdentifier = authored.timeZone.identifier
        value.dueDate = authored.date(from: DateComponents(year: 2026, month: 9, day: 12))
        value.dueHasTime = false
        let now = try #require(device.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 17)))
        var preferences = NotificationPreferences.default
        preferences.quietHoursEnabled = false
        let reminder = try #require(PlannerReminderEngine.make(events: PlannerEventProjection.events(from: [value], scope: scope),
            preferences: preferences, now: now, calendar: device).first)
        #expect(device.component(.day, from: reminder.fireDate) == 11)
        #expect(device.component(.hour, from: reminder.fireDate) == 18)
        let destination = try #require(PlannerNavigationTarget(url: reminder.deepLink, calendar: device))
        #expect(destination.day == PlannerDayProjection.day(for: value, calendar: device))
    }

    @Test func schedulerIsOffByDefaultAndCancelsOnlyItsOwnRequests() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let center = ReminderCenterFixture()
        center.otherIdentifiers = ["existing-cloud-grade"]
        let scheduler = PlannerNotificationScheduler(userDefaults: defaults, center: center)
        #expect(!scheduler.isEnabled)
        scheduler.isEnabled = true
        await scheduler.reconcile(items: [item(12)], scope: scope, preferences: .default, now: date(11, hour: 17), calendar: calendar)
        #expect(center.reminders.count == 1)
        await scheduler.reconcile(items: [], scope: scope, preferences: .default, now: date(11, hour: 17), calendar: calendar)
        #expect(center.reminders.isEmpty)
        #expect(center.otherIdentifiers == ["existing-cloud-grade"])
        center.authorized = false
        await scheduler.reconcile(items: [item(12)], scope: scope, preferences: .default, now: date(11, hour: 17), calendar: calendar)
        #expect(center.reminders.isEmpty)
    }

    @Test func aSuspendedOlderAddCannotResurrectCancelledReminders() async {
        let center = ReminderCenterFixture()
        center.suspendNextAdd = true
        let scheduler = PlannerNotificationScheduler(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, center: center)
        scheduler.isEnabled = true
        let first = Task { await scheduler.reconcile(items: [item(12)], scope: scope, preferences: .default,
            now: date(11, hour: 17), calendar: calendar) }
        await center.waitUntilSuspended()
        scheduler.isEnabled = false
        await scheduler.reconcile(items: [], scope: scope, preferences: .default, now: date(11, hour: 17), calendar: calendar)
        center.resumeAdd()
        await first.value
        #expect(center.reminders.isEmpty)
    }
}

@MainActor
private final class ReminderCenterFixture: PlannerNotificationScheduling {
    var authorized = true
    var reminders: [String: PlannerReminder] = [:]
    var otherIdentifiers: [String] = []
    var suspendNextAdd = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func isAuthorized() async -> Bool { authorized }
    func pendingIdentifiers() async -> [String] { Array(reminders.keys) + otherIdentifiers }
    func remove(identifiers: [String]) {
        for id in identifiers { reminders[id] = nil }
        otherIdentifiers.removeAll { identifiers.contains($0) }
    }
    func add(_ reminder: PlannerReminder) async throws {
        if suspendNextAdd {
            suspendNextAdd = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        reminders[reminder.id] = reminder
    }
    func waitUntilSuspended() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func resumeAdd() { continuation?.resume(); continuation = nil }
}
