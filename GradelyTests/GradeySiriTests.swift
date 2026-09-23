import AppIntents
import Foundation
import Testing
@testable import Gradely

@MainActor struct GradeySiriTests {
    @Test func subjectQueriesKeepAmbiguityAndDistinguishOfficialFromCalculatedAverage() async throws {
        let subjects = [makeSubject("math-a", name: "Matematika", abbreviation: "MAT", official: "1,75"),
                        makeSubject("math-b", name: "Matematika seminář", abbreviation: "MATS", official: "2,20")]
        let fixture = fixture(subjects: subjects)
        let matches = try await fixture.service.subjects(matching: "mat", refresh: false)
        #expect(matches.count == 2)
        #expect(Set(matches.map(\.id)).count == 2)
        #expect(matches.first?.officialAverage == "1,75")
        #expect(matches.first?.calculatedAverage == GradeMath.formattedAverage(2))
        #expect(try await fixture.service.subjects(matching: "seminar", refresh: false).count == 1)
    }

    @Test func gradesPreserveProviderDisplayTextAndExcludePrivateMetadata() async throws {
        let mark = Mark(markDate: "2026-09-16", caption: "private-caption", theme: "private-theme", markText: "8",
            teacherID: "secret-teacher", type: "points", typeNote: "private-note", weight: 1, subjectID: "math", isNew: false,
            isPoints: true, id: "mark-1", pointsText: "8", maxPoints: 10)
        let subject = Subject(marks: [mark], subjectInfo: .init(id: "math", abbrev: "MAT", name: "Matematika"), averageText: nil,
                              subjectNote: "private-subject-note", pointsOnly: true)
        let fixture = fixture(subjects: [subject])
        let selected = try #require(try await fixture.service.subjects(refresh: false).first)
        let grades = try await fixture.service.grades(subjectID: selected.id, refresh: false)
        #expect(grades.first?.value == "8/10")
        #expect(selected.calculatedAverage == nil)
        let exposed = String(reflecting: try await fixture.service.discoverySnapshot())
        for secret in ["private-caption", "private-theme", "secret-teacher", "private-note", "private-subject-note", "mock-access"] {
            #expect(!exposed.contains(secret))
        }
    }

    @Test func offlineGradesKeepOriginalTimestampAndReportStaleness() async throws {
        let old = Date().addingTimeInterval(-3600)
        let fixture = fixture(cachedAt: old)
        let subjects = try await fixture.service.subjects()
        #expect(!subjects.isEmpty)
        #expect(subjects.allSatisfy { $0.isStale && $0.updatedAt == old })
    }

    @Test func noCacheIsUnavailableWhileAnEmptySuccessfulCacheIsEmpty() async throws {
        let missing = fixture(hasMarks: false)
        await #expect(throws: GradeySiriError.unavailable) { try await missing.service.subjects() }
        let empty = fixture(subjects: [])
        #expect(try await empty.service.subjects(refresh: false).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func timedOutWaitReturnsCacheWithoutWaitingForTheProvider() async throws {
        let client = SiriSuspendedClient()
        let fixture = fixture(cachedAt: Date().addingTimeInterval(-3600), client: client, timeout: .milliseconds(30))
        let result = try await fixture.service.subjects()
        #expect(result.first?.isStale == true)
        // The request returned while the provider is still suspended. Avoid a wall-clock
        // assertion: other MainActor tests can delay this continuation under a full run.
        #expect(client.continuation != nil)
        client.finish()
        await Task.yield()
    }

    @Test func accountSwitchDuringRefreshCannotReturnOldSchoolData() async throws {
        let client = SiriSuspendedClient()
        let fixture = fixture(cachedAt: Date().addingTimeInterval(-3600), client: client)
        let request = Task { try await fixture.service.subjects() }
        while client.continuation == nil { await Task.yield() }
        var changed = PreviewData.expiredSession
        changed.baseURL = URL(string: "https://other-school.example")!
        try fixture.sessionStore.save(session: changed)
        client.finish()
        await #expect(throws: GradeySiriError.changedAccount) { try await request.value }
    }

    @Test func schedulePreservesCancellationsAndNextLessonSkipsThem() async throws {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let response = timetable(on: tomorrow, atoms: [
            TimetableAtom(hourID: 1, subjectID: "math", change: .init(changeType: "Canceled")),
            TimetableAtom(hourID: 2, subjectID: "math", roomID: "room")
        ])
        let fixture = fixture(timetable: response, timetableDate: tomorrow)
        let schedule = try await fixture.service.schedule(on: tomorrow, refresh: false)
        #expect(schedule.count == 2)
        #expect(schedule.first?.isCanceled == true)
        #expect(schedule.last?.room == "204")
        let next = try await fixture.service.nextLessons()
        #expect(next.first?.isCanceled == false)
        #expect(next.first?.id == schedule.last?.id)
    }

    @Test func missingTimetableIsNotReportedAsNoLessons() async throws {
        let missing = fixture()
        await #expect(throws: GradeySiriError.unavailable) { try await missing.service.schedule(on: Date()) }
        let empty = fixture(timetable: timetable(on: Date(), atoms: []))
        #expect(try await empty.service.schedule(on: Date(), refresh: false).isEmpty)
    }

    @Test func lessonIdentitySurvivesProviderAtomReorderingAndRoomChanges() throws {
        let fixture = fixture()
        let expected = try fixture.service.access()
        let date = Date(), day = ScheduledDay(id: "day", date: date, dayOfWeek: 1, dayType: .workDay, dayDescription: "", lessons: [], isToday: false)
        func lesson(_ id: String, room: String) -> ScheduledLesson {
            ScheduledLesson(id: id, hour: .init(id: 1, caption: "1", beginTime: "08:00", endTime: "08:45"),
                subjectName: "Math", subjectAbbrev: "MAT", teacherName: nil, teacherAbbrev: nil, roomAbbrev: room, roomName: nil,
                groups: [], theme: nil, hasHomework: false, change: nil, changeKind: .none, subjectID: "math", groupIDs: ["g1"])
        }
        #expect(fixture.service.lessonKey(lesson("offset-1", room: "101"), day: day) == fixture.service.lessonKey(lesson("offset-9", room: "202"), day: day))
        let id = fixture.service.id(.lesson, source: fixture.service.lessonKey(lesson("offset-1", room: "101"), day: day), access: expected)
        let parsed = try #require(GradeySiriID(id))
        #expect(calendarDay(fixture.service.lessonDate(parsed)) == calendarDay(date))
    }

    @Test func plannerFiltersIncompleteItemsAndIncludesUndatedPersonalTasks() async throws {
        let fixture = fixture()
        let scope = try fixture.service.access().scope
        var personal = PlannerItem(); personal.title = "Read"
        var own = personal; own.id = UUID(); own.title = "Math homework"; own.subject = .init(scope: scope, id: "math", name: "Math", abbreviation: "MAT")
        var foreign = own; foreign.id = UUID(); foreign.subject = .init(scope: .init(rawValue: "other-school"), id: "math", name: "Math", abbreviation: "MAT")
        var completed = personal; completed.id = UUID(); completed.isCompleted = true
        for item in [personal, own, foreign, completed] { try await fixture.planner.save(item) }
        #expect(try fixture.service.plannerItems().count == 2)
        #expect(try fixture.service.plannerItems(on: Date()).isEmpty)
        #expect(try fixture.service.plannerItems(matching: "homework").count == 1)
        let subject = try #require(try await fixture.service.subjects(refresh: false).first)
        #expect(try fixture.service.plannerItems(subjectID: subject.id).count == 1)
    }

    @Test func conflictingPlannerReferencesAreNeverExposed() throws {
        let fixture = fixture()
        let scope = try fixture.service.access().scope
        var item = PlannerItem(); item.title = "Other student"; item.subject = .init(scope: .init(rawValue: "foreign"), id: "math", name: "Math", abbreviation: nil)
        #expect(!GradeyIntentService.isVisible(item, scope: scope))
    }

    @Test func confirmationCancellationAndAccountSwitchPreventSaving() async throws {
        let fixture = fixture()
        let prepared = try fixture.service.prepareCreation(title: "Read chapter 4", type: .homework, due: nil, hasTime: false, subjectID: nil, notes: nil)
        await #expect(throws: CancellationError.self) {
            try await fixture.service.create(prepared) { throw CancellationError() }
        }
        #expect(fixture.planner.items.isEmpty)
        await #expect(throws: GradeySiriError.changedAccount) {
            try await fixture.service.create(prepared) {
                var other = PreviewData.expiredSession; other.baseURL = URL(string: "https://new-school.example")!
                try fixture.sessionStore.save(session: other)
            }
        }
        #expect(fixture.planner.items.isEmpty)
    }

    @Test func confirmedExecutionIsIdempotentAndDoesNotRequestCalendarPermission() async throws {
        let fixture = fixture()
        let prepared = try fixture.service.prepareCreation(title: " Test ", type: .test, due: Date(), hasTime: false, subjectID: nil, notes: "private-notes")
        var confirmations = 0
        let result = try await fixture.service.create(prepared) { confirmations += 1 }
        _ = try await fixture.service.create(prepared) { confirmations += 1 }
        #expect(confirmations == 2)
        #expect(fixture.planner.items.count == 1)
        #expect(result.calendarPending)
        #expect(fixture.calendar.requests == 0)
        #expect(fixture.calendar.exports == 0)
        #expect(fixture.planner.items.first?.notes == "private-notes")
        #expect(!String(reflecting: try await fixture.service.discoverySnapshot()).contains("private-notes"))
    }

    @Test func authorizedCalendarExportAndExportFailureBothKeepDurableLocalSave() async throws {
        for fail in [false, true] {
            let fixture = fixture(); fixture.calendar.hasAccess = true; fixture.calendar.failExport = fail
            let prepared = try fixture.service.prepareCreation(title: "Exam", type: .test, due: Date(), hasTime: true, subjectID: nil, notes: nil)
            let result = try await fixture.service.create(prepared) { }
            #expect(fixture.calendar.requests == 0)
            #expect(fixture.calendar.exports == 1)
            #expect(fixture.planner.items.count == 1)
            #expect(result.calendarPending == fail)
        }
    }

    @Test func localPersistenceFailureNeverExportsToCalendar() async throws {
        let persistence = SiriFailingPersistence()
        let fixture = fixture(persistence: persistence); fixture.calendar.hasAccess = true
        let prepared = try fixture.service.prepareCreation(title: "Exam", type: .test, due: Date(), hasTime: true, subjectID: nil, notes: nil)
        await #expect(throws: PlannerError.self) { try await fixture.service.create(prepared) { } }
        #expect(fixture.planner.items.isEmpty)
        #expect(fixture.calendar.exports == 0)
    }

    @Test func invalidTitleOrTimeWithoutDateCannotReachConfirmation() throws {
        let fixture = fixture()
        #expect(throws: PlannerError.self) { try fixture.service.prepareCreation(title: " ", type: .task, due: nil, hasTime: false, subjectID: nil, notes: nil) }
        #expect(throws: GradeySiriError.invalidDate) { try fixture.service.prepareCreation(title: "Exam", type: .test, due: nil, hasTime: true, subjectID: nil, notes: nil) }
    }

    @Test func allDayPlannerQueriesPreserveAuthoredDateAfterTravel() async throws {
        let fixture = fixture()
        var authored = Calendar(identifier: .gregorian); authored.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        var item = PlannerItem(); item.title = "All day"; item.calendarSyncEnabled = false
        item.dueDate = authored.date(from: DateComponents(year: 2026, month: 10, day: 25))
        item.timeZoneIdentifier = authored.timeZone.identifier
        try await fixture.planner.save(item)
        let deviceDate = fixture.service.calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        #expect(try fixture.service.plannerItems(on: deviceDate).count == 1)
    }

    @Test func siriURLIsScopedAndRetainedUntilColdLaunchIsReady() async throws {
        let fixture = fixture()
        let subject = try #require(try await fixture.service.subjects(refresh: false).first)
        let id = try #require(GradeySiriID(subject.id)), router = SchoolNotificationRouter()
        #expect(router.enqueue(userInfo: ["url": id.url.absoluteString]))
        #expect(router.takePendingURL(ifReady: false) == nil)
        #expect(router.pendingURL == id.url)
        let destination = try await fixture.service.resolveDestination(subject.id)
        #expect(destination.subjectID == "math")
        try fixture.service.validateDestination(destination)
        var other = PreviewData.expiredSession; other.baseURL = URL(string: "https://other.example")!
        try fixture.sessionStore.save(session: other)
        #expect(throws: GradeySiriError.changedAccount) { try fixture.service.validateDestination(destination) }
        await #expect(throws: GradeySiriError.missingItem) { try await fixture.service.resolveDestination(subject.id) }
        #expect(GradeySiriID.from(url: URL(string: "https://siri/\(subject.id)")!) == nil)
        #expect(GradeySiriID.from(url: URL(string: "gradey://siri/\(subject.id)?scope=other")!) == nil)
    }

    @Test func setupGateAndSignOutBlockReadAndWriteActions() async throws {
        let fixture = fixture()
        let gated = GradeyIntentService(environment: fixture.service.environment, setupAllowed: { false })
        await #expect(throws: GradeySiriError.setup) { try await gated.subjects() }
        #expect(throws: GradeySiriError.setup) { try gated.plannerItems() }
        try fixture.sessionStore.clearSession()
        #expect(throws: GradeySiriError.setup) { try fixture.service.prepareCreation(title: "Exam", type: .test, due: nil, hasTime: false, subjectID: nil, notes: nil) }
    }

    @Test func discoveryIsOptInAndPurgesOnDisableDeletionSignOutAndScopeChange() async throws {
        let fixture = fixture(), defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = GradeySiriDiscoverySettings(defaults: defaults), index = SiriRecordingIndex()
        let coordinator = GradeySiriDiscoveryCoordinator(service: fixture.service, settings: settings, index: index)
        #expect(!settings.isEnabled)
        await coordinator.reconcileNow()
        #expect(index.current == nil)
        settings.setEnabled(true)
        await coordinator.reconcileNow()
        #expect(index.current?.subjects.count == 1)
        let prepared = try fixture.service.prepareCreation(title: "Homework", type: .homework, due: nil, hasTime: false, subjectID: nil, notes: nil)
        _ = try await fixture.service.create(prepared) { }
        await coordinator.reconcileNow()
        #expect(index.current?.planner.count == 1)
        try await fixture.planner.delete(id: prepared.draft.id)
        await coordinator.reconcileNow()
        #expect(index.current?.planner.isEmpty == true)
        settings.setEnabled(false)
        await coordinator.reconcileNow()
        #expect(index.current == nil)
        settings.setEnabled(true)
        try fixture.sessionStore.clearSession()
        await coordinator.reconcileNow()
        #expect(index.current == nil)
    }

    @Test func lateIndexCompletionCannotUndoOptOut() async throws {
        let fixture = fixture(), settings = GradeySiriDiscoverySettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setEnabled(true)
        let index = SiriRecordingIndex(); index.suspendReplace = true
        let coordinator = GradeySiriDiscoveryCoordinator(service: fixture.service, settings: settings, index: index)
        coordinator.requestReconcile()
        while index.continuation == nil { await Task.yield() }
        settings.setEnabled(false); coordinator.requestReconcile()
        index.continuation?.resume(); index.continuation = nil
        await coordinator.reconcileNow()
        #expect(index.current == nil)
        #expect(index.clears >= 2)
    }

    @Test func summaryLimitsSpokenItemsButRetainsTotalCount() {
        let text = GradeyIntentService.summary(["First", "Second", "Third", "Never spoken"])
        #expect(text.contains("4"))
        #expect(text.contains("Third"))
        #expect(!text.contains("Never spoken"))
    }

    @Test func nativeReminderDatesPreserveTimeZoneAndRejectIncompleteOrDSTGapDates() throws {
        let service = fixture().service
        let zone = TimeZone(identifier: "Europe/Prague")!
        let day = DateComponents(timeZone: zone, year: 2026, month: 10, day: 25)
        let resolved = try service.resolveDueDate(day)
        #expect(!resolved.hasTime)
        #expect(resolved.timeZone == zone)
        let prepared = try service.prepareCreation(title: "Exam", type: .task, due: resolved.date,
            hasTime: resolved.hasTime, subjectID: nil, notes: nil, timeZone: resolved.timeZone)
        #expect(prepared.draft.timeZoneIdentifier == zone.identifier)
        #expect(try service.resolveDueDate(DateComponents(timeZone: zone, year: 2026, month: 10, day: 25, hour: 15, minute: 30)).hasTime)
        for invalid in [DateComponents(hour: 15), DateComponents(year: 2026, month: 2, day: 30),
                        DateComponents(timeZone: zone, year: 2026, month: 3, day: 29, hour: 2, minute: 30)] {
            #expect(throws: GradeySiriError.invalidDate) { try service.resolveDueDate(invalid) }
        }
    }

    @Test func savedLessonIDsResolveOutsideDiscoveryWeeks() async throws {
        let date = TimetableDates.addingWeeks(4, to: Date())
        let fixture = fixture(timetable: timetable(on: date, atoms: [.init(hourID: 1, subjectID: "math")]), timetableDate: date)
        let lesson = try #require(try await fixture.service.schedule(on: date, refresh: false).first)
        #expect(try await fixture.service.discoverySnapshot().lessons.isEmpty)
        #expect(try await fixture.service.resolveLessons(identifiers: [lesson.id]).first?.id == lesson.id)
    }

    @Test func linkedEduPageChildrenHaveDifferentSiriIdentityAndPlannerVisibility() async throws {
        let fixture = fixture()
        let first = SchoolStudentProfile(id: "child-a", fullName: "First child", classID: nil, className: nil)
        let second = SchoolStudentProfile(id: "child-b", fullName: "Second child", classID: nil, className: nil)
        var session = PreviewData.expiredSession
        session.provider = .eduPage; session.linkedAccountID = "same-parent-account"
        session.eduPage = EduPageSessionData(sessionID: "session", username: "parent", password: "",
            gsecHash: "", userID: "parent", activeStudent: first, linkedStudents: [first, second], subjects: [])
        try fixture.sessionStore.save(session: session)
        let original = try fixture.service.access()
        var item = PlannerItem(); item.title = "First child's task"; item.calendarSyncEnabled = false
        item.subject = .init(scope: original.scope, id: "math", name: "Math", abbreviation: "MAT")
        try await fixture.planner.save(item)
        let prepared = try fixture.service.prepareCreation(title: "Unconfirmed", type: .task, due: nil, hasTime: false, subjectID: nil, notes: nil)
        session.eduPage?.activeStudent = second
        try fixture.sessionStore.save(session: session)
        #expect(try fixture.service.access().token != original.token)
        #expect(try fixture.service.plannerItems().isEmpty)
        await #expect(throws: GradeySiriError.changedAccount) { try await fixture.service.create(prepared) { } }
    }

    @available(iOS 27, macOS 27, *)
    @Test func nativeReminderRejectsUnsupportedFieldsBeforeAccessOrConfirmation() async throws {
        var intent = GradeyCreateReminderIntent()
        intent.title = "Unsupported reminder"
        intent.images = []; intent.urls = []
        intent.tags = ["unsupported"]
        await #expect(throws: GradeySiriError.unsupported) { try await intent.perform() }
    }

    private func makeSubject(_ id: String, name: String = "Matematika", abbreviation: String = "MAT", official: String? = "1,75") -> Subject {
        Subject(marks: [Mark(markDate: "2026-09-16", caption: nil, theme: nil, markText: "2", teacherID: nil, type: "1", typeNote: nil,
            weight: 1, subjectID: id, isNew: false, isPoints: false, id: "mark-1")],
            subjectInfo: .init(id: id, abbrev: abbreviation, name: name), averageText: official)
    }
    private func timetable(on date: Date, atoms: [TimetableAtom]) -> TimetableResponse {
        TimetableResponse(hours: [.init(id: 1, caption: "1", beginTime: "08:00", endTime: "08:45"), .init(id: 2, caption: "2", beginTime: "09:00", endTime: "09:45")],
            days: [.init(atoms: atoms, dayOfWeek: 1, date: TimetableDates.apiDateString(date) + "T00:00:00", dayType: "WorkDay")],
            subjects: [.init(id: "math", abbrev: "MAT", name: "Matematika")], rooms: [.init(id: "room", abbrev: "204", name: "Room 204")])
    }
    private func calendarDay(_ date: Date?) -> String? { date.map(TimetableDates.apiDateString) }
    private func fixture(subjects: [Subject]? = nil, hasMarks: Bool = true, cachedAt: Date = Date(),
                         timetable: TimetableResponse? = nil, timetableDate: Date = Date(), client: (any BakalariClient)? = nil,
                         timeout: Duration = .seconds(8), persistence: (any PlannerPersisting)? = nil) -> SiriFixture {
        var session = PreviewData.expiredSession; session.expiresAt = .distantFuture
        let sessionStore = InMemorySessionStore(session: session), calendar = SiriCalendar()
        let planner = PlannerStore(persistence: persistence ?? InMemoryPlannerPersistence(), calendarService: calendar)
        let repository = SchoolRepository(client: client ?? MockBakalariClient(marksError: URLError(.notConnectedToInternet), timetableError: URLError(.notConnectedToInternet)),
            sessionStore: sessionStore,
            marksCache: InMemoryMarksCache(cachedMarks: hasMarks ? .init(marksResponse: MarksResponse(subjects: subjects ?? [makeSubject("math")]), cachedAt: cachedAt) : nil),
            timetableCache: InMemoryTimetableCache(cached: timetable.map { .init(response: $0, weekStart: TimetableDates.monday(of: timetableDate), cachedAt: cachedAt) }))
        let environment = AppEnvironment(repository: repository, schoolDirectoryProvider: MockSchoolDirectoryProvider(), makePlannerStore: { planner })
        return SiriFixture(service: GradeyIntentService(environment: environment, refreshTimeout: timeout, setupAllowed: { true }), sessionStore: sessionStore, planner: planner, calendar: calendar)
    }
}

@MainActor private struct SiriFixture {
    let service: GradeyIntentService
    let sessionStore: InMemorySessionStore
    let planner: PlannerStore
    let calendar: SiriCalendar
}
@MainActor private final class SiriCalendar: PlannerCalendarSyncing {
    var hasAccess = false
    var requests = 0
    var exports = 0
    var failExport = false
    func requestAccess() async throws { requests += 1; throw PlannerError.calendarPermission }
    func upsert(_ item: PlannerItem) throws -> String {
        exports += 1
        if failExport { throw PlannerError.calendarUnavailable }
        return "event-" + item.id.uuidString
    }
    func remove(_ item: PlannerItem) throws { }
}
@MainActor private final class SiriFailingPersistence: PlannerPersisting {
    func load() throws -> [PlannerItem] { [] }
    func save(_ items: [PlannerItem]) throws { throw PlannerError.storageUnavailable }
}
@MainActor private final class SiriRecordingIndex: GradeySiriIndexing {
    var current: GradeySiriSnapshot?
    var clears = 0
    var suspendReplace = false
    var continuation: CheckedContinuation<Void, Never>?
    func clear() async throws { clears += 1; current = nil }
    func replace(with snapshot: GradeySiriSnapshot) async throws {
        if suspendReplace { await withCheckedContinuation { continuation = $0 } }
        current = snapshot
    }
}
@MainActor private final class SiriSuspendedClient: BakalariClient {
    var continuation: CheckedContinuation<MarksResponse, Error>?
    func finish() { continuation?.resume(returning: PreviewData.marksResponse); continuation = nil }
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse { try await withCheckedThrowingContinuation { continuation = $0 } }
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse { throw AppError.notLoggedIn }
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse { throw AppError.notLoggedIn }
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse { PreviewData.absenceResponse }
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse { PreviewData.userResponse }
    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse { throw URLError(.notConnectedToInternet) }
    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject { subject }
}
