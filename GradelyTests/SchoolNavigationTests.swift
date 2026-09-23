import Foundation
import Observation
import Testing
@testable import Gradely

@MainActor struct SchoolNavigationTests {
    @Test func plannerDayAndItemSurviveColdLaunchURL() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Prague"))
        let id = UUID()
        let url = try #require(URL(string: "gradey://planner?day=2026-10-25&item=\(id.uuidString)"))
        let route = try #require(PlannerNavigationTarget(url: url, calendar: calendar))
        #expect(route.itemID == id)
        let day = try #require(route.day)
        #expect(calendar.component(.day, from: day) == 25)
        #expect(calendar.component(.hour, from: day) == 0)
        #expect(PlannerNavigationTarget(url: try #require(URL(string: "https://planner?day=2026-10-25"))) == nil)
        #expect(PlannerNavigationTarget(url: try #require(URL(string: "gradey://planner?day=2026-02-31"))) == nil)
    }

    @Test func unknownNotificationsCannotReplaceAnUnconsumedSchoolRoute() throws {
        let router = SchoolNotificationRouter()
        let url = try #require(URL(string: "gradey://planner?day=2026-09-12"))
        #expect(router.enqueue(userInfo: ["url": url.absoluteString]))
        #expect(!router.enqueue(userInfo: ["intercom": ["conversation": "support"]]))
        #expect(!router.enqueue(userInfo: ["url": "https://support.example/conversation"]))
        #expect(router.pendingURL == url)
        #expect(router.takePendingURL(ifReady: false) == nil)
        #expect(router.pendingURL == url)
        #expect(router.takePendingURL(ifReady: true) == url)
        #expect(router.pendingURL == nil)
    }

    @Test func existingGradePushLinksRemainSupportedWithoutRewritingTheirDestination() throws {
        for link in ["gradey://marks?event=grade-1", "gradey://marks?summary=summary-1", "gradely://subjects", "gradely://timetable"] {
            #expect(SchoolNotificationRouting.url(from: ["url": link]) == URL(string: link))
        }
        #expect(SchoolNotificationRouting.url(from: [:]) == nil)
        #expect(SchoolNotificationRouting.url(from: ["url": "gradey://planner?day=2026-02-31"]) == nil)
    }

    @Test func existingAppleCalendarItemLinksOpenTheOriginalPlannerItem() throws {
        let item = PlannerItem()
        #expect(try #require(PlannerNavigationTarget(url: item.calendarURL)).itemID == item.id)
        #expect(PlannerNavigationTarget(url: try #require(URL(string: "gradey://planner?item=malformed"))) == nil)
    }

    @Test func dateOnlyPlannerDaysSurviveTravelWhileTimedItemsUseTheDeviceDay() throws {
        var authored = Calendar(identifier: .gregorian)
        authored.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var device = Calendar(identifier: .gregorian)
        device.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var item = PlannerItem()
        item.timeZoneIdentifier = authored.timeZone.identifier
        item.dueDate = authored.date(from: DateComponents(year: 2026, month: 9, day: 12))
        item.dueHasTime = false
        let authoredDay = try #require(PlannerDayProjection.day(for: item, calendar: device))
        #expect(device.component(.day, from: authoredDay) == 12)
        item.dueHasTime = true
        let timedDay = try #require(PlannerDayProjection.day(for: item, calendar: device))
        #expect(device.component(.day, from: timedDay) == 11)
    }

    @Test func eventDateTextHonorsCzechLocaleAndTheAuthoredAllDayDate() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-11T12:00:00Z"))
        let deviceZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        func event(timed: Bool) -> SchoolEvent {
            SchoolEvent(id: UUID(), scope: nil, subjectID: nil, subjectName: nil, title: "Test", kind: .test,
                date: date, hasTime: timed, timeZoneIdentifier: "Pacific/Auckland", updatedAt: date)
        }
        func normalized(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        let czech = SchoolDateFormatting.eventDate(event(timed: false), locale: Locale(identifier: "cs_CZ"), deviceTimeZone: deviceZone)
        let english = SchoolDateFormatting.eventDate(event(timed: false), locale: Locale(identifier: "en_US"), deviceTimeZone: deviceZone)
        #expect(normalized(czech) == "12. 9. 2026")
        #expect(english == "Sep 12, 2026")
        let timed = SchoolDateFormatting.eventDate(event(timed: true), locale: Locale(identifier: "cs_CZ"), deviceTimeZone: deviceZone, includeTime: false)
        #expect(normalized(timed) == "11. 9. 2026")
    }

    @Test func notificationPrivacyChangesInvalidateTheObservedPreferenceRead() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = MarkNotificationSettingsStore(userDefaults: defaults)
        let probe = NotificationPreferenceObservationProbe()
        withObservationTracking { _ = store.preferences } onChange: {
            Task { @MainActor in probe.changed = true }
        }
        var preferences = store.preferences
        preferences.lockScreenDetail = .privateSummary
        preferences.quietHoursEnabled.toggle()
        store.preferences = preferences
        for _ in 0..<100 where !probe.changed { await Task.yield() }
        #expect(probe.changed)
        #expect(store.preferences == preferences)
    }

    @Test func linkedEduPageChildrenHaveSeparateExactScopesAndDoNotInheritOldPlannerLinks() {
        var session = StoredSession(accessToken: "session", refreshToken: "", tokenType: "Cookie", expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.edupage.org")!, provider: .eduPage,
            eduPage: EduPageSessionData(sessionID: "session", username: "parent", password: "", gsecHash: "", userID: "parent",
                schoolName: nil, activeStudent: SchoolStudentProfile(id: "Child A", fullName: "Child", classID: nil, className: nil),
                linkedStudents: [], subjects: []), linkedAccountID: "linked-account")
        let first = SchoolDataScope(session: session)
        session.eduPage?.activeStudent = SchoolStudentProfile(id: "child-a", fullName: "Same display name", classID: nil, className: nil)
        let second = SchoolDataScope(session: session)
        let legacy = SchoolDataScope(rawValue: "linked-linked-account")
        #expect(first != second)
        #expect(first != legacy)
        #expect(second != legacy)
        var item = PlannerItem()
        item.title = "Personal test"
        item.dueDate = Date().addingTimeInterval(86_400)
        item.subject = PlannerSubjectReference(scope: first, id: "math", name: "Math", abbreviation: "M")
        #expect(PlannerEventProjection.events(from: [item], scope: first).count == 1)
        #expect(PlannerEventProjection.events(from: [item], scope: second).isEmpty)
        item.subject = PlannerSubjectReference(scope: legacy, id: "math", name: "Math", abbreviation: "M")
        #expect(PlannerEventProjection.events(from: [item], scope: second).isEmpty)
        session.provider = .bakalari
        #expect(SchoolDataScope(session: session) == legacy)
    }
}

@MainActor private final class NotificationPreferenceObservationProbe {
    var changed = false
}
