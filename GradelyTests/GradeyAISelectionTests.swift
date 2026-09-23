import Foundation
import Testing
@testable import Gradely

@MainActor
struct GradeyAISelectionTests {
    @Test func generalChatStartsWithEmptyContextWithoutFetchingSchoolData() async throws {
        let builder = SelectionContextBuilder(snapshot: source())
        let cached = try builder.cachedContext(for: GradeyAIContextSelection())
        let refreshed = try await builder.refreshContext(for: GradeyAIContextSelection())
        #expect(cached?.subjects.isEmpty == true)
        #expect(refreshed.subjects.isEmpty && refreshed.trends.isEmpty && refreshed.timetable.isEmpty)
        #expect(refreshed.events?.isEmpty != false)
        #expect(builder.refreshCount == 0)
    }

    @Test func tomorrowSharesOnlySelectedDayAndStripsPeopleAndNotes() {
        let snapshot = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .tomorrow), now: now, calendar: utc)
        #expect(snapshot.subjects.isEmpty && snapshot.trends.isEmpty)
        #expect(snapshot.timetable.map(\.id) == ["tomorrow"])
        #expect(snapshot.events?.map(\.id) == [eventID.uuidString])
        #expect(snapshot.events?.allSatisfy { $0.notes == nil } == true)
        #expect(snapshot.timetable.allSatisfy { $0.teacher == nil && $0.groups.isEmpty && $0.changeDescription == nil })
    }

    @Test func selectedWeekUsesMondayBoundaryAndIncludesOnlyThatWeeksObservations() {
        let selection = GradeyAIContextSelection(action: .weekSummary, weekStart: date("2026-10-14T12:00:00Z"))
        let snapshot = GradeyAIContextBuilder.select(source(), for: selection, now: now, calendar: utc)
        #expect(snapshot.timetable.map(\.id) == ["later-week"])
        #expect(snapshot.events?.isEmpty == true)
        #expect(snapshot.insights?.map(\.id) == ["later-insight"])
        #expect(snapshot.subjects.isEmpty && snapshot.trends.isEmpty)
        #expect(GradeyAIContextBuilder.weekStart(containing: date("2026-10-18T23:00:00Z"), calendar: utc) == date("2026-10-12T00:00:00Z"))
    }

    @Test func prioritiesShareAtMostThreeCurrentSummariesWithoutRawMarks() {
        let snapshot = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .studyPriorities), now: now, calendar: utc)
        #expect(snapshot.subjects.count == 3)
        #expect(snapshot.subjects.allSatisfy { $0.recentMarks.isEmpty })
        #expect(snapshot.timetable.isEmpty)
        #expect(snapshot.insights?.count ?? 0 <= 5)
    }

    @Test func subjectHelpDoesNotShareOtherSubjectsOrPlannerNotes() {
        let snapshot = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .subjectHelp, subjectID: "math"), now: now, calendar: utc)
        #expect(snapshot.subjects.map(\.id) == ["math"])
        #expect(snapshot.subjects.first?.recentMarks.count == 1)
        #expect(snapshot.trends.allSatisfy { $0.subjectID == "math" })
        #expect(snapshot.events?.allSatisfy { $0.subjectID == "math" && $0.notes == nil } == true)
        #expect(snapshot.timetable.isEmpty)
    }

    @Test func testPreparationUsesItsEventSubjectAndNotesRequireSpecificOptIn() {
        let selection = GradeyAIContextSelection(action: .testPreparation, subjectID: "unrelated", eventID: eventID)
        let snapshot = GradeyAIContextBuilder.select(source(), for: selection, now: now, calendar: utc)
        #expect(snapshot.subjects.map(\.id) == ["math"])
        #expect(snapshot.events?.map(\.id) == [eventID.uuidString])
        #expect(snapshot.events?.first?.notes == nil)
        var withNotes = selection
        withNotes.includeNotes = true
        let optedIn = GradeyAIContextBuilder.select(source(), for: withNotes, now: now, calendar: utc)
        #expect(optedIn.events?.first?.notes == "private selected notes")
        #expect(optedIn.events?.count == 1)
        #expect(withNotes.identifier != selection.identifier)
    }

    @Test func missingExplicitSubjectIsReportedWithoutFallingBackToAllMarks() {
        let snapshot = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .subjectHelp, subjectID: "missing"), now: now, calendar: utc)
        #expect(snapshot.subjects.isEmpty)
        #expect(snapshot.unavailableSections.contains(.marks))
        #expect(snapshot.events?.isEmpty == true)
    }

    @Test func computeWirePreservesServerCatalogAndBackwardCompatibility() throws {
        let raw = #"{"enabled":true,"consentRequired":false,"termsVersion":"2.2","dailyLimit":5,"dailyUsed":2,"remaining":2,"compute":{"schemaVersion":1,"catalogVersion":"v1","allowance":5,"used":2,"reserved":1,"remaining":2,"resetAt":1783814400000,"supportTier":"none","actions":[{"id":"reply","cost":1,"available":true},{"id":"subject_help","cost":2,"available":false}]}}"#
        let status = try FirebaseGradeyAIWireContract.decodeStatus(Data(raw.utf8))
        #expect(status.compute?.reserved == 1)
        #expect(status.compute?.actions.last?.available == false)
        #expect(status.compute?.catalogVersion == "v1")
        let legacy = try FirebaseGradeyAIWireContract.decodeStatus(Data(#"{"enabled":true,"consentRequired":false,"dailyLimit":5,"remaining":3}"#.utf8))
        #expect(legacy.compute == nil)
    }

    @Test func contextualActionsRequireAvailableServerCatalog() async {
        let client = SelectionAIClient()
        client.status.compute = nil
        let vm = makeViewModel(client: client)
        await vm.bootstrap()
        #expect(vm.canAffordSelectedAction)
        await vm.selectAction(.subjectHelp, subjectID: "math")
        #expect(!vm.canAffordSelectedAction)
        await vm.send("Help")
        #expect(client.requests.isEmpty)
        client.status.compute = compute(actions: [.init(id: "subject_help", cost: 2, available: true)])
        await vm.refreshStatus()
        #expect(vm.selectedActionCost == 2 && vm.canAffordSelectedAction)
        client.status.remaining = 1
        await vm.refreshStatus()
        #expect(!vm.canAffordSelectedAction)
    }

    @Test func uncertainRetryPreservesRequestAndContextAfterRefresh() async {
        let client = SelectionAIClient(), builder = SelectionContextBuilder(snapshot: source())
        let vm = makeViewModel(client: client, builder: builder)
        await vm.bootstrap()
        await vm.selectAction(.subjectHelp, subjectID: "math")
        await vm.send("Explain my private grade")
        let frozen = client.requests.first
        builder.snapshot = GradeyAIContextBuilder.emptyContext(schoolScope: builder.scope, now: now.addingTimeInterval(500))
        await vm.refreshContext()
        client.recoveryState = "missing"
        await vm.retry()
        #expect(client.requests.count == 2)
        #expect(client.requests.last == frozen)
        #expect(client.requests.last?.payloadHash == frozen?.payloadHash)
    }

    @Test func confirmedFailedRetryGetsNewIdentityAndPreservesCapturedContext() async {
        let client = SelectionAIClient()
        let vm = makeViewModel(client: client)
        await vm.bootstrap()
        await vm.send("Try this question")
        let first = client.requests.first
        client.recoveryState = "failed"
        await vm.retry()
        #expect(client.requests.count == 2)
        #expect(client.requests.last?.clientMessageID != first?.clientMessageID)
        #expect(client.requests.last?.context == first?.context)
    }

    @Test func completedRecoveryWorksAtZeroComputeWithoutStartingAnotherRequest() async {
        let client = SelectionAIClient()
        let vm = makeViewModel(client: client)
        await vm.bootstrap()
        await vm.send("Use the last Compute")
        client.status.remaining = 0
        client.recoveryState = "complete"
        client.recoveryMessage = GradeyAIMessage(id: "persisted", conversationID: vm.currentConversation!.id, clientMessageID: nil,
            role: .assistant, content: "Completed on the server", status: .complete, createdAt: now, contextGeneratedAt: now)
        await vm.refreshStatus()
        #expect(!vm.canSend)
        await vm.retry()
        #expect(client.requests.count == 1)
        #expect(vm.messages.last?.content == "Completed on the server")
        #expect(vm.messages.last?.status == .complete)
        #expect(vm.status?.remaining == 0)
    }

    @Test func sendIsLockedWhileCreatingConversation() async {
        let client = SelectionAIClient()
        client.holdsCreate = true
        let vm = makeViewModel(client: client)
        await vm.bootstrap()
        let send = Task { await vm.send("one") }
        await waitUntil { client.createContinuation != nil }
        await vm.send("two")
        #expect(client.createCount == 1)
        client.releaseCreate()
        await send.value
        #expect(client.requests.map(\.text) == ["one"])
    }

    @Test func changingSchoolDuringCreateCannotSendOldContext() async {
        let client = SelectionAIClient(), builder = SelectionContextBuilder(snapshot: source())
        client.holdsCreate = true
        let vm = makeViewModel(client: client, builder: builder)
        await vm.bootstrap()
        let send = Task { await vm.send("old school") }
        await waitUntil { client.createContinuation != nil }
        builder.scope = "school_other"
        vm.reset()
        client.releaseCreate()
        await send.value
        #expect(client.requests.isEmpty)
        #expect(vm.messages.isEmpty && vm.currentConversation == nil)
        #expect(vm.status == nil)
    }

    @Test func openingNewDraftInvalidatesAReplyStillBeingPrepared() async {
        let client = SelectionAIClient()
        client.holdsCreate = true
        let vm = makeViewModel(client: client)
        await vm.bootstrap()
        let send = Task { await vm.send("abandoned") }
        await waitUntil { client.createContinuation != nil }
        vm.beginDraftChat()
        let newDraft = vm.currentConversation?.id
        client.releaseCreate()
        await send.value
        #expect(client.requests.isEmpty)
        #expect(vm.currentConversation?.id == newDraft && vm.isDraftChat)
    }

    @Test func persistedRecoveryContainsOnlyIDsAndHashAndIsScoped() async throws {
        let defaults = UserDefaults(suiteName: "ai-selection-\(UUID().uuidString)")!
        let client = SelectionAIClient(), builder = SelectionContextBuilder(snapshot: source())
        let vm = GradeyAIViewModel(client: client, contextBuilder: builder, pendingDefaults: defaults)
        await vm.bootstrap()
        await vm.selectAction(.subjectHelp, subjectID: "math")
        await vm.send("Never persist this prompt")
        let data = try #require(defaults.data(forKey: "gradey.ai.pendingRequest.v1"))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("Never persist this prompt"))
        #expect(!json.contains("private selected notes"))
        #expect(!json.contains("recent_marks"))
        #expect(json.contains("payloadHash") && json.contains("clientMessageID"))
        builder.scope = "school_other"
        vm.reset()
        await vm.bootstrap()
        await vm.send("Other school general question")
        #expect(client.requests.count == 2)
        let all = try JSONDecoder().decode([String: GradeyAIPendingRequest].self, from: defaults.data(forKey: "gradey.ai.pendingRequest.v1")!)
        #expect(all.keys.count == 2)
        defaults.removeObject(forKey: "gradey.ai.pendingRequest.v1")
    }

    @Test func tomorrowSelectionProvidesLocalSummaryWithoutCreatingAIRequest() async {
        let client = SelectionAIClient(), builder = SelectionContextBuilder(snapshot: source())
        // The live clock is irrelevant here: the builder supplies a prepared selection.
        builder.selectedOverride = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .tomorrow), now: now, calendar: utc)
        let vm = makeViewModel(client: client, builder: builder)
        await vm.bootstrap()
        await vm.selectAction(.tomorrow)
        #expect(vm.localTomorrowSummary?.contains("Math") == true)
        #expect(client.requests.isEmpty && client.createCount == 0)
    }

    @Test func selectedSubjectRetainsGradesBeyondTheLegacyGlobalMarkCap() {
        var subjects: [Subject] = []
        for index in 0..<25 {
            let id = "subject-\(index)"
            let marks = (0..<5).map { markIndex in Mark(markDate: "2026-09-10", markText: "2", type: "grade", weight: 1, subjectID: id, id: "\(id)-\(markIndex)") }
            subjects.append(Subject(marks: marks, subjectInfo: SubjectInfo(id: id, abbrev: id, name: id), averageText: "2"))
        }
        let all = GradeyAIContextBuilder.makeSubjects(from: subjects, maximumTotalMarkCount: .max)
        var snapshot = source()
        snapshot = GradeyAIContextSnapshot(schoolScope: snapshot.schoolScope, generatedAt: now, isStale: false, unavailableSections: [], subjects: all, trends: [], timetable: [])
        let selected = GradeyAIContextBuilder.select(snapshot, for: GradeyAIContextSelection(action: .subjectHelp, subjectID: "subject-24"), now: now, calendar: utc)
        #expect(selected.subjects.count == 1)
        #expect(selected.subjects.first?.recentMarks.count == 5)
        #expect(GradeyAIContextBuilder.makeSubjects(from: subjects).reduce(0) { $0 + $1.recentMarks.count } == 80)
    }

    @Test func selectedWeekRetainsLessonsBeyondEarlierWeeksLegacyCap() {
        let hour = TimetableHour(id: 1, caption: "1", beginTime: "08:00", endTime: "08:45")
        func lesson(_ id: String) -> ScheduledLesson {
            ScheduledLesson(id: id, hour: hour, subjectName: "Math", subjectAbbrev: "M", teacherName: nil, teacherAbbrev: nil,
                roomAbbrev: nil, roomName: nil, groups: [], theme: nil, hasHomework: false, change: nil, changeKind: .none)
        }
        let earlyDay = ScheduledDay(id: "early", date: date("2026-09-01T12:00:00Z"), dayOfWeek: 2, dayType: .workDay,
            dayDescription: "", lessons: (0..<130).map { lesson("early-\($0)") }, isToday: false)
        let selectedDay = ScheduledDay(id: "selected", date: date("2026-10-14T12:00:00Z"), dayOfWeek: 3, dayType: .workDay,
            dayDescription: "", lessons: [lesson("selected")], isToday: false)
        let weeks = [TimetableWeek(weekStart: earlyDay.date!, days: [earlyDay], hours: [hour]),
            TimetableWeek(weekStart: selectedDay.date!, days: [selectedDay], hours: [hour])]
        let all = GradeyAIContextBuilder.makeLessons(from: weeks, maximumLessonCount: .max)
        let snapshot = GradeyAIContextSnapshot(schoolScope: "school_test", generatedAt: now, isStale: false, unavailableSections: [], subjects: [], trends: [], timetable: all)
        let selected = GradeyAIContextBuilder.select(snapshot, for: GradeyAIContextSelection(action: .weekSummary, weekStart: selectedDay.date), now: now, calendar: utc)
        #expect(all.count == 131)
        #expect(selected.timetable.count == 1)
        #expect(selected.timetable.first?.id.contains("selected") == true)
    }

    @Test func selectedPastWeekKeepsSeenObservationsWithoutTodayAttentionRanking() {
        let observed = date("2026-08-12T12:00:00Z")
        let observation = SchoolGradeObservation(id: "seen-past", scope: SchoolDataScope(rawValue: "school_test"), subjectID: "math",
            observedAt: observed, previousObservedAt: observed.addingTimeInterval(-86_400), previousAverage: 2, average: 2.5,
            addedMarkIDs: ["new"], editedMarkIDs: [], digest: "digest", seenAt: observed.addingTimeInterval(100))
        var snapshot = source()
        snapshot.insights = GradeyAIContextBuilder.makeInsights(observations: [observation], summaries: [], preparedCalculations: [:])
        let selected = GradeyAIContextBuilder.select(snapshot, for: GradeyAIContextSelection(action: .weekSummary, weekStart: observed), now: now, calendar: utc)
        #expect(selected.insights?.map(\.id) == ["seen-past"])
        #expect(selected.insights?.first?.observedAt == observed.timeIntervalSince1970 * 1_000)
    }

    @Test func dateOnlyTimetableUsesSelectedCalendarAcrossNegativeUTCOffset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selected = GradeyAIContextBuilder.select(source(), for: GradeyAIContextSelection(action: .tomorrow),
            now: date("2026-09-11T19:00:00Z"), calendar: calendar)
        #expect(selected.timetable.map(\.id) == ["tomorrow"])
    }

    @Test func calculationWireIncludesFullPreparedBasisBeyondSampledRecentGrades() throws {
        let subject = Subject(marks: [
            Mark(markDate: "2026-09-01", markText: "2", type: "grade", weight: 2, subjectID: "math", id: "a"),
            Mark(markDate: "2026-09-02", markText: "4", type: "grade", weight: 1, subjectID: "math", id: "b")
        ], subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Math"), averageText: "2.67")
        let calculation = GradeyAIGradeCalculationContext(prepared: GradeMath.prepare(subject))
        let summary = GradeyAISubjectContext(id: "math", name: "Math", abbreviation: "M", average: 2.67, pointsOnly: false,
            totalMarkCount: 2, recentMarks: [], calculation: calculation)
        let snapshot = GradeyAIContextSnapshot(schoolScope: "school_test", generatedAt: now, isStale: false,
            unavailableSections: [], subjects: [summary], trends: [], timetable: [])
        let selected = GradeyAIContextBuilder.select(snapshot, for: GradeyAIContextSelection(action: .subjectHelp, subjectID: "math"), now: now, calendar: utc)
        #expect(selected.subjects.first?.calculation?.weightedSum == 8)
        let payload = try FirebaseGradeyAIWireContract.encodeMinimizedContext(selected)
        let json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let subjects = try #require(json["subjects"] as? [[String: Any]])
        let wire = try #require(subjects.first?["calculation"] as? [String: Any])
        #expect(wire["weightedSum"] as? Double == 8)
        #expect(wire["totalWeight"] as? Double == 3)
        #expect(wire["includedCount"] as? Int == 2)
        #expect(wire["excludedCount"] as? Int == 0)
        #expect(wire["providerAverage"] as? Double == 2.67)
        #expect(calculation.localAverage == 8.0 / 3.0)
        #expect(wire["confidence"] as? String == "exact")
        #expect((subjects.first?["recentMarks"] as? [Any])?.isEmpty == true)
    }

    @Test func calculationProvenancePreservesExclusionsAndLegacySubjectsDecodeWithoutIt() throws {
        let subject = Subject(marks: [
            Mark(markDate: "2026-09-01", markText: "2", type: "grade", weight: 1, subjectID: "math", id: "a"),
            Mark(markDate: "2026-09-02", markText: "N", type: "grade", weight: 1, subjectID: "math", id: "b")
        ], subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Math"), averageText: nil)
        let calculation = GradeyAIGradeCalculationContext(prepared: GradeMath.prepare(subject))
        #expect(calculation.includedCount == 1 && calculation.excludedCount == 1)
        #expect(calculation.issues.contains("excludedMarks"))
        #expect(calculation.confidence == "estimated")
        let legacy = Data(#"{"id":"math","name":"Math","average":2,"points_only":false,"total_mark_count":1,"recent_marks":[]}"#.utf8)
        #expect(try JSONDecoder().decode(GradeyAISubjectContext.self, from: legacy).calculation == nil)
    }

    @Test func calculationWireOmitsNonfiniteArithmetic() throws {
        let prepared = PreparedGradeCalculation(subjectID: "math", revision: "invalid", marks: [], weightedSum: .infinity,
            totalWeight: .nan, calculatedAverage: .nan, officialAverage: .infinity, confidence: .unavailable, issues: [.invalidWeights], excludedMarkCount: 1)
        let calculation = GradeyAIGradeCalculationContext(prepared: prepared)
        #expect(calculation.localAverage == nil && calculation.providerAverage == nil)
        #expect(calculation.weightedSum == nil && calculation.totalWeight == nil)
        #expect(try JSONEncoder().encode(calculation).count > 0)
    }

    private var now: Date { date("2026-09-11T12:00:00Z") }
    private var eventID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func source() -> GradeyAIContextSnapshot {
        let mark = GradeyAIMarkContext(value: "2", date: "2026-09-10", weight: 1, title: "Quiz", isPoints: false, pointsText: nil, maxPoints: nil)
        var subjects: [GradeyAISubjectContext] = []
        for index in 0..<7 {
            let id = index == 0 ? "math" : "s\(index)"
            let name = index == 0 ? "Math" : "Subject \(index)"
            subjects.append(GradeyAISubjectContext(id: id, name: name, abbreviation: nil, average: Double(index % 5 + 1),
                pointsOnly: false, totalMarkCount: 1, recentMarks: [mark]))
        }
        let lessons = [lesson(id: "today", day: "2026-09-11"), lesson(id: "tomorrow", day: "2026-09-12"), lesson(id: "later-week", day: "2026-10-14")]
        var snapshot = GradeyAIContextSnapshot(schoolScope: "school_test", generatedAt: now, isStale: false,
            unavailableSections: [], subjects: subjects, trends: [], timetable: lessons)
        snapshot.events = [GradeyAIEventContext(id: eventID.uuidString, title: "Math test", type: "test", subjectID: "math", subjectName: "Math", date: "2026-09-12T10:00:00Z", hasTime: true, notes: "private selected notes")]
        snapshot.insights = [GradeyAIInsightContext(id: "now-insight", subjectID: "math", kind: "grade", summary: "Grade changed", observedAt: now.timeIntervalSince1970 * 1_000, isEstimated: false),
            GradeyAIInsightContext(id: "later-insight", subjectID: "math", kind: "observed_grade_change", summary: "Later grade", observedAt: date("2026-10-14T12:00:00Z").timeIntervalSince1970 * 1_000, isEstimated: false)]
        return snapshot
    }
    private func lesson(id: String, day: String) -> GradeyAILessonContext {
        GradeyAILessonContext(id: id, date: day, subject: "Math", subjectAbbreviation: "M", beginsAt: "08:00", endsAt: "08:45", teacher: "private teacher", room: "1", groups: ["private group"], changeKind: .none, changeDescription: "private notes")
    }
    private func compute(actions: [GradeyComputeAction]) -> GradeyComputeBalance {
        GradeyComputeBalance(schemaVersion: 1, catalogVersion: "v1", allowance: 5, used: 0, reserved: 0, remaining: 5, resetAt: nil, supportTier: "none", actions: actions)
    }
    private func makeViewModel(client: SelectionAIClient, builder: SelectionContextBuilder? = nil) -> GradeyAIViewModel {
        GradeyAIViewModel(client: client, contextBuilder: builder ?? SelectionContextBuilder(snapshot: source()), pendingDefaults: UserDefaults(suiteName: "ai-selection-\(UUID().uuidString)")!)
    }
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 { if predicate() { return }; await Task.yield() }
        #expect(predicate())
    }
}

@MainActor
private final class SelectionContextBuilder: GradeyAIContextBuilding {
    var snapshot: GradeyAIContextSnapshot
    var scope: String
    var refreshCount = 0
    var selectedOverride: GradeyAIContextSnapshot?
    init(snapshot: GradeyAIContextSnapshot) { self.snapshot = snapshot; scope = snapshot.schoolScope }
    func currentSchoolScope() throws -> String { scope }
    func cachedContext() throws -> GradeyAIContextSnapshot? { snapshot }
    func refreshContext() async throws -> GradeyAIContextSnapshot { refreshCount += 1; return snapshot }
    func refreshContext(for selection: GradeyAIContextSelection) async throws -> GradeyAIContextSnapshot {
        if let selectedOverride { return selectedOverride }
        if selection.action == .reply { return GradeyAIContextBuilder.emptyContext(schoolScope: scope, now: Date()) }
        refreshCount += 1
        return GradeyAIContextBuilder.select(snapshot, for: selection, now: Date())
    }
}

@MainActor
private final class SelectionAIClient: GradeyAIClient {
    var status = GradeyAIStatus(enabled: true, consentRequired: false, termsVersion: "2.2", dailyLimit: 5, dailyUsed: 0, remaining: 5, resetAt: nil,
        compute: GradeyComputeBalance(schemaVersion: 1, catalogVersion: "v1", allowance: 5, used: 0, reserved: 0, remaining: 5, resetAt: nil, supportTier: "none",
            actions: GradeyAIAction.allCases.map { .init(id: $0.rawValue, cost: 1, available: true) }))
    var requests: [GradeyAIReplyRequest] = []
    var conversations: [GradeyAIConversation] = []
    var holdsCreate = false
    var createCount = 0
    var createContinuation: CheckedContinuation<Void, Never>?
    var recoveryState = "missing"
    var recoveryMessage: GradeyAIMessage?
    func loadStatus() async throws -> GradeyAIStatus { status }
    func acceptConsent() async throws -> GradeyAIConsent { GradeyAIConsent(consented: true, termsVersion: "2.2") }
    func revokeConsent() async throws {}
    func listConversations(schoolScope: String) async throws -> [GradeyAIConversation] { conversations.filter { $0.schoolScope == schoolScope } }
    func createConversation(schoolScope: String, title: String?) async throws -> GradeyAIConversation {
        createCount += 1
        if holdsCreate { await withCheckedContinuation { createContinuation = $0 } }
        let conversation = GradeyAIConversation(id: UUID().uuidString, schoolScope: schoolScope, title: title ?? "Chat", createdAt: Date(), updatedAt: Date())
        conversations.append(conversation)
        return conversation
    }
    func releaseCreate() { holdsCreate = false; createContinuation?.resume(); createContinuation = nil }
    func loadConversation(id: String) async throws -> GradeyAIConversationDetail {
        GradeyAIConversationDetail(conversation: conversations.first { $0.id == id }!, messages: [])
    }
    func deleteConversation(id: String) async throws {}
    func deleteAllConversations(schoolScope: String) async throws {}
    func recoverRequest(_ pending: GradeyAIPendingRequest) async throws -> GradeyAIGenerationRecovery {
        GradeyAIGenerationRecovery(state: recoveryState, message: recoveryMessage, status: status)
    }
    func streamReply(request: GradeyAIReplyRequest) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.start(assistantMessageID: UUID().uuidString, remaining: status.remaining))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }
    }
    func streamReply(conversationID: String, clientMessageID: String, text: String, context: GradeyAIContextSnapshot) -> AsyncThrowingStream<GradeyAIStreamEvent, Error> {
        streamReply(request: GradeyAIReplyRequest(conversationID: conversationID, clientMessageID: clientMessageID, text: text, context: context,
            actionID: .reply, contextSelectionID: context.schoolScope, catalogVersion: nil, maximumComputeCost: 1))
    }
}
