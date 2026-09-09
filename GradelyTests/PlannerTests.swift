import Foundation
import Testing
@testable import Gradely

@MainActor
struct PlannerTests {
    private let scope = SchoolDataScope(rawValue: "planner-school")
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Prague")!
        return value
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func week(_ days: [TimetableDayDTO], hours: [TimetableHour]? = nil, kind: TimetableKind = .weekly) -> TimetableWeek {
        TimetableMapper.makeWeek(from: TimetableResponse(
            hours: hours ?? [
                TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
                TimetableHour(id: 2, caption: "2", beginTime: "9:00", endTime: "9:45")
            ], days: days,
            subjects: [TimetableEntity(id: " M", abbrev: "Math", name: "Mathematics"),
                       TimetableEntity(id: "M", abbrev: "Math", name: "Mathematics")]
        ), weekStart: date(7), calendar: calendar, kind: kind)
    }

    private func day(_ day: Int, atoms: [TimetableAtom], type: String = "WorkDay") -> TimetableDayDTO {
        TimetableDayDTO(atoms: atoms, dayOfWeek: 1, date: "2026-09-\(String(format: "%02d", day))T00:00:00+02:00", dayType: type)
    }

    private func linkedItem() throws -> PlannerItem {
        let timetable = week([day(7, atoms: [TimetableAtom(hourID: 1, groupIDs: ["g1"], subjectID: " M")])])
        let day = try #require(timetable.days.first)
        let lesson = try #require(day.lessons.first)
        var item = PlannerItem.linked(to: lesson, on: day, scope: scope)
        item.lesson = PlannerLessonReference(lesson: lesson, day: day, scope: scope, calendar: calendar)
        item.title = "Read chapter 4"
        item.timeZoneIdentifier = calendar.timeZone.identifier
        return item
    }

    @Test func nextLessonUsesRawSubjectIDsAndEarliestStrictlyLaterTime() throws {
        let item = try linkedItem()
        let timetable = week([
            day(8, atoms: [TimetableAtom(hourID: 1, subjectID: " M")]),
            day(7, atoms: [TimetableAtom(hourID: 2, subjectID: " M"), TimetableAtom(hourID: 1, subjectID: " M")])
        ])
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [timetable], calendar: calendar) == date(7, hour: 9))
        let lookalike = week([day(8, atoms: [TimetableAtom(hourID: 1, subjectID: "M")])])
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [lookalike], calendar: calendar) == nil)
    }

    @Test func nextLessonSkipsCancellationHolidaysAndOtherGroups() throws {
        let item = try linkedItem()
        let timetable = week([
            day(8, atoms: [TimetableAtom(hourID: 1, subjectID: " M", change: TimetableChange(changeType: "Canceled"))]),
            day(9, atoms: [TimetableAtom(hourID: 1, subjectID: " M")], type: "Holiday"),
            day(10, atoms: [TimetableAtom(hourID: 1, groupIDs: ["g2"], subjectID: " M")]),
            day(11, atoms: [TimetableAtom(hourID: 2, groupIDs: ["g1"], subjectID: " M")])
        ])
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [timetable], calendar: calendar) == date(11, hour: 9))
    }

    @Test func permanentAndMalformedTimesNeverInventDueDates() throws {
        let item = try linkedItem()
        let days = [day(8, atoms: [TimetableAtom(hourID: 1, subjectID: " M")])]
        let permanent = week(days, kind: .permanent)
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [permanent], calendar: calendar) == nil)
        let malformed = week(days, hours: [TimetableHour(id: 1, caption: "1", beginTime: "25:80", endTime: "")])
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [malformed], calendar: calendar) == nil)
        let permanentDay = try #require(permanent.days.first)
        let draft = PlannerItem.linked(to: try #require(permanentDay.lessons.first), on: permanentDay, scope: scope)
        #expect(draft.linkedDate == nil)
        #expect(draft.lesson?.start == nil)
        #expect(!draft.hasCalendarDate)
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func unknownSubjectCannotProduceANextLesson(subjectID: String?) throws {
        let timetable = week([
            day(7, atoms: [TimetableAtom(hourID: 1, subjectID: subjectID)]),
            day(8, atoms: [TimetableAtom(hourID: 1, subjectID: subjectID)])
        ])
        let day = try #require(timetable.days.first)
        let lesson = try #require(day.lessons.first)
        let item = PlannerItem.linked(to: lesson, on: day, scope: scope)
        #expect(item.subject == nil)
        #expect(PlannerNextLessonSelector.nextDate(after: try #require(item.lesson), in: [timetable], calendar: calendar) == nil)
    }

    @Test func attachmentSurvivesAtomReorderingButNotAnAccountOrGroupChange() throws {
        let item = try linkedItem()
        let reordered = week([day(7, atoms: [
            TimetableAtom(hourID: 1, groupIDs: ["g2"], subjectID: " M"),
            TimetableAtom(hourID: 1, groupIDs: ["g1"], subjectID: " M", roomID: "new-room")
        ])])
        let day = try #require(reordered.days.first)
        let reference = try #require(item.lesson)
        #expect(reference.lessonID != day.lessons[1].id)
        #expect(reference.matches(lesson: day.lessons[1], day: day, scope: scope))
        #expect(!reference.matches(lesson: day.lessons[0], day: day, scope: scope))
        #expect(!reference.matches(lesson: day.lessons[1], day: day, scope: SchoolDataScope(rawValue: "other-school")))
    }

    @Test func resolverCrossesWeekBoundaryAndUsesOfflineCache() async throws {
        let item = try linkedItem()
        let future = week([day(14, atoms: [TimetableAtom(hourID: 2, subjectID: " M")])])
        var requests: [Date] = []
        let resolver = PlannerLessonResolver(loadWeek: { anchor in
            requests.append(anchor)
            throw URLError(.notConnectedToInternet)
        }, cachedWeek: { _ in future }, currentScope: { scope })
        let initial = week([day(7, atoms: [TimetableAtom(hourID: 1, subjectID: " M")])])
        #expect(try await resolver.nextDate(after: item, displayedWeek: initial) == date(14, hour: 9))
        #expect(requests.count == 1)
    }

    @Test func resolverStopsAtUnavailableWeekAndChecksScopeAfterAwait() async throws {
        let item = try linkedItem()
        var requests = 0
        let missing = PlannerLessonResolver(loadWeek: { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }, cachedWeek: { _ in nil }, currentScope: { scope })
        await #expect(throws: PlannerError.self) { try await missing.nextDate(after: item) }
        #expect(requests == 1)

        var activeScope = scope
        let changed = PlannerLessonResolver(loadWeek: { _ in
            activeScope = SchoolDataScope(rawValue: "another-school")
            return week([day(8, atoms: [TimetableAtom(hourID: 1, subjectID: " M")])])
        }, cachedWeek: { _ in nil }, currentScope: { activeScope })
        await #expect(throws: PlannerError.self) { try await changed.nextDate(after: item) }
    }

    @Test func resolverBoundsSearchAndPreservesNoResult() async throws {
        var count = 0
        let resolver = PlannerLessonResolver(loadWeek: { _ in
            count += 1
            return week([])
        }, cachedWeek: { _ in nil }, currentScope: { scope })
        #expect(try await resolver.nextDate(after: linkedItem()) == nil)
        #expect(count == 5)
        #expect(try await resolver.nextDate(after: PlannerItem()) == nil)
        #expect(count == 5)
    }

    @Test func calendarMappingUsesTimedDueDateAndIncludesUserContent() throws {
        var item = try linkedItem()
        item.dueDate = date(8, hour: 9)
        item.dueHasTime = true
        item.notes = "Bring a ruler"
        let event = try PlannerCalendarEventData.make(from: item)
        #expect(event.start == item.dueDate)
        #expect(event.end == date(8, hour: 9, minute: 45))
        #expect(!event.isAllDay)
        #expect(event.title.contains("Math"))
        #expect(event.title.contains(item.title))
        #expect(event.notes == item.notes)
        #expect(event.url == item.calendarURL)
        item.isCompleted = true
        #expect(try PlannerCalendarEventData.make(from: item).title != event.title)
    }

    @Test func calendarFallsBackToLessonTimingThenDateOnlyAndRejectsUndated() throws {
        var item = try linkedItem()
        #expect(try PlannerCalendarEventData.make(from: item).start == date(7, hour: 8))
        item.lesson = nil
        let event = try PlannerCalendarEventData.make(from: item)
        #expect(event.isAllDay)
        #expect(event.start == date(7))
        #expect(event.end == date(8))
        item.linkedDate = nil
        #expect(throws: PlannerError.self) { try PlannerCalendarEventData.make(from: item) }
    }

    @Test(arguments: [(3, 29, 23.0), (10, 25, 25.0)])
    func allDayEndUsesCalendarDaysAcrossDST(month: Int, day: Int, hours: Double) throws {
        var item = PlannerItem()
        item.title = "DST day"
        item.timeZoneIdentifier = "Europe/Prague"
        item.dueDate = date(day, hour: 12, month: month)
        let event = try PlannerCalendarEventData.make(from: item)
        #expect(event.isAllDay)
        #expect(event.end.timeIntervalSince(event.start) == hours * 3600)
    }

    @Test func plannerPersistsAllFieldsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PlannerPersistence(directory: directory)
        #expect(try persistence.load().isEmpty)
        var item = try linkedItem()
        item.notes = "Personal notes"
        item.type = .test
        item.dueDate = date(8, hour: 9)
        item.dueHasTime = true
        item.calendarSyncEnabled = true
        let store = PlannerStore(persistence: persistence, calendarService: TestPlannerCalendar(), now: { date(6, hour: 10) })
        try await store.save(item)
        let reopened = PlannerStore(persistence: PlannerPersistence(directory: directory), calendarService: TestPlannerCalendar())
        reopened.loadIfNeeded()
        #expect(reopened.items == store.items)
        #expect(reopened.items.first?.calendarEventIdentifier != nil)
        #expect(reopened.items.first?.createdAt == date(6, hour: 10))
    }

    @Test func corruptedPersonalDataIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "personal-planner.json")
        let original = Data("not valid json".utf8)
        try original.write(to: url)
        let store = PlannerStore(persistence: PlannerPersistence(directory: directory), calendarService: TestPlannerCalendar())
        store.loadIfNeeded()
        #expect(!store.isLoaded)
        #expect(store.storageError != nil)
        await #expect(throws: PlannerError.self) { try await store.save(linkedItem()) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func deniedPermissionKeepsLocalItemAndRetrySurvivesRestart() async throws {
        let persistence = InMemoryPlannerPersistence()
        let service = TestPlannerCalendar()
        service.hasAccess = false
        let store = PlannerStore(persistence: persistence, calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        #expect(store.items.count == 1)
        #expect(store.pendingCalendarCount == 1)
        #expect(store.calendarError != nil)
        #expect(service.events.isEmpty)
        service.hasAccess = true
        let reopened = PlannerStore(persistence: persistence, calendarService: service)
        await reopened.activate()
        #expect(reopened.pendingCalendarCount == 0)
        #expect(reopened.items.first?.calendarEventIdentifier != nil)
        #expect(service.events.count == 1)
        #expect(service.permissionRequests == 1) // Activation never prompts.
    }

    @Test func localOnlyItemsNeverRequestPermissionAndEditsPreserveCreationTime() async throws {
        let service = TestPlannerCalendar()
        var now = date(6)
        let store = PlannerStore(persistence: InMemoryPlannerPersistence(), calendarService: service, now: { now })
        var item = try linkedItem()
        item.title = "  My task  "
        item.calendarSyncEnabled = false
        try await store.save(item)
        item = try #require(store.items.first)
        #expect(item.title == "My task")
        now = date(7)
        try await store.setCompleted(true, id: item.id)
        #expect(store.items.first?.createdAt == date(6))
        #expect(store.items.first?.updatedAt == date(7))
        #expect(store.items.first?.isCompleted == true)
        #expect(service.permissionRequests == 0)
    }

    @Test(arguments: [false, true])
    func deniedExportCanBeDisabledOrDeletedWithoutRequestingCleanup(deleting: Bool) async throws {
        let service = TestPlannerCalendar()
        service.hasAccess = false
        let store = PlannerStore(persistence: InMemoryPlannerPersistence(), calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        #expect(store.pendingCalendarCount == 1)
        if deleting {
            try await store.delete(id: item.id)
            #expect(store.items.isEmpty)
        } else {
            item.calendarSyncEnabled = false
            try await store.save(item)
            #expect(store.items.first?.calendarSyncEnabled == false)
        }
        #expect(store.pendingCalendarCount == 0)
        #expect(service.permissionRequests == 1)
        #expect(service.events.isEmpty)
    }

    @Test func syncedEditsUpdateExistingEventAndMissingEventIsRecreated() async throws {
        let service = TestPlannerCalendar()
        let store = PlannerStore(persistence: InMemoryPlannerPersistence(), calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        let identifier = store.items.first?.calendarEventIdentifier
        item.title = "Changed title"
        try await store.save(item)
        #expect(service.events.count == 1)
        #expect(store.items.first?.calendarEventIdentifier == identifier)
        #expect(service.events[item.id]?.data.title.contains("Changed title") == true)
        service.events.removeAll() // Simulates manual deletion in Calendar.
        try await store.save(item)
        #expect(service.events.count == 1)
        #expect(store.items.first?.calendarEventIdentifier != identifier)
    }

    @Test func disablingAndDeletingRemoveGeneratedEvents() async throws {
        let service = TestPlannerCalendar()
        let store = PlannerStore(persistence: InMemoryPlannerPersistence(), calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        item.calendarSyncEnabled = false
        try await store.save(item)
        #expect(service.events.isEmpty)
        #expect(store.items.first?.calendarEventIdentifier == nil)
        item.calendarSyncEnabled = true
        try await store.save(item)
        try await store.delete(id: item.id)
        #expect(service.events.isEmpty)
        #expect(store.items.isEmpty)
        #expect(store.pendingCalendarCount == 0)
    }

    @Test func deletionRetainsPendingCleanupAcrossRestartWhenPermissionIsRevoked() async throws {
        let service = TestPlannerCalendar()
        let persistence = InMemoryPlannerPersistence()
        let store = PlannerStore(persistence: persistence, calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        service.hasAccess = false
        try await store.delete(id: item.id)
        #expect(store.items.isEmpty)
        #expect(service.events.count == 1)
        #expect(persistence.items.first?.notes == nil)
        #expect(persistence.items.first?.deletedAt != nil)
        service.hasAccess = true
        let reopened = PlannerStore(persistence: persistence, calendarService: service)
        await reopened.activate()
        #expect(service.events.isEmpty)
        #expect(persistence.items.isEmpty)
    }

    @Test func localWriteFailureDoesNotMutateCalendarOrPublishedItems() async throws {
        let service = TestPlannerCalendar()
        let persistence = FailingPlannerPersistence()
        let store = PlannerStore(persistence: persistence, calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        await #expect(throws: PlannerError.self) { try await store.save(item) }
        #expect(store.items.isEmpty)
        #expect(service.events.isEmpty)
        #expect(service.permissionRequests == 0)
    }

    @Test func interruptedIdentifierSaveCanRetryWithoutCreatingDuplicateEvent() async throws {
        let service = TestPlannerCalendar()
        let persistence = FailingPlannerPersistence()
        persistence.savesBeforeFailure = 2
        let store = PlannerStore(persistence: persistence, calendarService: service)
        var item = try linkedItem()
        item.calendarSyncEnabled = true
        try await store.save(item)
        #expect(store.pendingCalendarCount == 1)
        #expect(service.events.count == 1)
        persistence.savesBeforeFailure = 10
        let reopened = PlannerStore(persistence: persistence, calendarService: service)
        await reopened.activate()
        #expect(service.events.count == 1)
        #expect(reopened.pendingCalendarCount == 0)
    }
}

@MainActor
private final class TestPlannerCalendar: PlannerCalendarSyncing {
    struct Event { let identifier: String; let data: PlannerCalendarEventData }
    var hasAccess = true
    var permissionRequests = 0
    var events: [UUID: Event] = [:]

    func requestAccess() async throws {
        permissionRequests += 1
        guard hasAccess else { throw PlannerError.calendarPermission }
    }
    func upsert(_ item: PlannerItem) throws -> String {
        let identifier = events[item.id]?.identifier ?? UUID().uuidString
        events[item.id] = Event(identifier: identifier, data: try PlannerCalendarEventData.make(from: item))
        return identifier
    }
    func remove(_ item: PlannerItem) throws { events.removeValue(forKey: item.id) }
}

private final class FailingPlannerPersistence: PlannerPersisting {
    var items: [PlannerItem] = []
    var savesBeforeFailure = 0
    func load() throws -> [PlannerItem] { items }
    func save(_ items: [PlannerItem]) throws {
        guard savesBeforeFailure > 0 else { throw CocoaError(.fileWriteOutOfSpace) }
        savesBeforeFailure -= 1
        self.items = items
    }
}
