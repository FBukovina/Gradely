import Foundation
import Testing
@testable import Gradely

@MainActor
struct SchoolInsightEngineTests {
    private let scope = SchoolDataScope(rawValue: "insight-school")
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Prague")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    private func subject(_ values: [(String, String)], average: String? = nil) -> Subject {
        Subject(marks: values.map { id, value in
            Mark(markDate: "2026-09-01", markText: value, type: "grade", weight: 1, subjectID: " M", id: id)
        }, subjectInfo: SubjectInfo(id: " M", abbrev: "M", name: "Mathematics"), averageText: average)
    }
    private func store() -> SchoolInsightStateStore {
        SchoolInsightStateStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func firstHydrationAndRepeatDigestNeverCreateEvents() {
        let store = store()
        let first = subject([("a", "2")])
        #expect(store.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1)).isEmpty)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(2)).isEmpty)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(3)).isEmpty)
    }

    @Test func newAndEditedMarksAreDistinctAndSeenRequiresExplicitAction() throws {
        let store = store()
        let first = subject([("a", "2")])
        store.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        let second = subject([("a", "2"), ("b", "4")])
        let new = try #require(store.observe(subjects: [second], scope: scope, fetchedAt: date(2)).first)
        #expect(new.addedMarkIDs == ["b"])
        #expect(new.editedMarkIDs.isEmpty)
        #expect(new.seenAt == nil)
        store.markSeen([new.id], scope: scope, at: date(2, hour: 13))
        #expect(store.observations(scope: scope, now: date(2, hour: 14)).first?.seenAt != nil)
        let edited = subject([("a", "2"), ("b", "3")])
        let changes = store.observe(subjects: [edited], scope: scope, fetchedAt: date(3))
        let edit = try #require(changes.first { $0.observedAt == date(3) })
        #expect(edit.addedMarkIDs.isEmpty)
        #expect(edit.editedMarkIDs == ["b"])
    }

    @Test func disappearancesAndCacheMismatchResetContinuityQuietly() {
        let store = store()
        let first = subject([("a", "2")])
        let second = subject([("a", "2"), ("b", "4")])
        store.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        #expect(store.observe(subjects: [second], scope: scope, fetchedAt: date(2)).count == 1)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(3)).isEmpty)
        #expect(store.observe(subjects: [], scope: scope, fetchedAt: date(4)).isEmpty)
        #expect(store.observe(subjects: [second], scope: scope, fetchedAt: date(5)).isEmpty)
        #expect(store.activate(subjects: [first], scope: scope, fetchedAt: date(6), now: date(6)).isEmpty)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(7)).isEmpty)
    }

    @Test func olderResponseCannotEraseNewerContinuityAndRetentionIsBounded() {
        let store = store()
        let first = subject([("a", "2")])
        store.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        var latest: [SchoolGradeObservation] = []
        for index in 1...105 {
            latest = store.observe(subjects: [subject([("a", index.isMultiple(of: 2) ? "2" : "3")])],
                scope: scope, fetchedAt: date(1).addingTimeInterval(Double(index) * 60))
        }
        #expect(latest.count == 100)
        #expect(store.observe(subjects: [], scope: scope, fetchedAt: date(1)).count == 100)
        #expect(store.observations(scope: scope, now: date(1).addingTimeInterval(31 * 24 * 60 * 60)).isEmpty)
    }

    @Test func ambiguousMarkIDsAndDuplicateSubjectsSuppressAllAttribution() {
        let store = store()
        let first = subject([("a", "2")])
        store.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        let ambiguous = subject([("a", "1"), ("a", "5")], average: "4.5")
        #expect(store.observe(subjects: [ambiguous], scope: scope, fetchedAt: date(2)).isEmpty)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(3)).isEmpty)
        #expect(store.observe(subjects: [first, subject([("b", "5")])], scope: scope, fetchedAt: date(4)).isEmpty)
        #expect(store.observe(subjects: [first], scope: scope, fetchedAt: date(5)).isEmpty)
    }

    @Test func officialVersusReconstructedAveragesNeverFormAChangeComparison() {
        let store = store()
        let official = subject([("a", "2")], average: "2.5")
        let reconstructed = subject([("a", "2")])
        store.activate(subjects: [official], scope: scope, fetchedAt: date(1), now: date(1))
        #expect(store.observe(subjects: [reconstructed], scope: scope, fetchedAt: date(2)).isEmpty)
        #expect(store.observe(subjects: [official], scope: scope, fetchedAt: date(3)).isEmpty)
    }

    @Test func readFlagOnlyDuplicatesDoNotBreakContinuityOrBecomeNewGrades() throws {
        let store = store()
        let original = Mark(markDate: "2026-09-01", markText: "2", type: "grade", weight: 1, subjectID: " M", id: "a")
        let unread = Mark(markDate: "2026-09-01", markText: "2", type: "grade", weight: 1, subjectID: " M", isNew: true, id: "a")
        let info = SubjectInfo(id: " M", abbrev: "M", name: "Mathematics")
        store.activate(subjects: [Subject(marks: [original], subjectInfo: info, averageText: nil)], scope: scope, fetchedAt: date(1), now: date(1))
        #expect(store.observe(subjects: [Subject(marks: [original, unread], subjectInfo: info, averageText: nil)], scope: scope, fetchedAt: date(2)).isEmpty)
        #expect(store.observe(subjects: [Subject(marks: [unread], subjectInfo: info, averageText: nil)], scope: scope, fetchedAt: date(3)).isEmpty)
        let addition = subject([("a", "2"), ("b", "4")])
        let observed = try #require(store.observe(subjects: [addition], scope: scope, fetchedAt: date(4)).first)
        #expect(observed.addedMarkIDs == ["b"])
        #expect(observed.editedMarkIDs.isEmpty)
    }

    @Test func changedHiddenWeightAssumptionsResetButExplicitWeightEditsAreObserved() throws {
        func weightedSubject(hidden: Bool, secondWeight: Double, average: String) -> Subject {
            Subject(marks: [
                Mark(markDate: "2026-09-01", markText: "1", type: "grade", weight: 1, subjectID: " M", id: "a"),
                Mark(markDate: "2026-09-02", markText: "5", type: "grade", typeNote: "Test", weight: hidden ? nil : secondWeight, subjectID: " M", id: "b")
            ], subjectInfo: SubjectInfo(id: " M", abbrev: "M", name: "Math"), averageText: average)
        }
        let hiddenStore = store()
        let first = weightedSubject(hidden: true, secondWeight: 2, average: "3.67")
        let second = weightedSubject(hidden: true, secondWeight: 4, average: "4.20")
        #expect(GradeMath.prepare(first).resolvedWeights["b"]?.value == 2)
        #expect(GradeMath.prepare(second).resolvedWeights["b"]?.value == 4)
        hiddenStore.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        #expect(hiddenStore.observe(subjects: [second], scope: scope, fetchedAt: date(2)).isEmpty)
        let explicitStore = store()
        explicitStore.activate(subjects: [weightedSubject(hidden: false, secondWeight: 2, average: "3.67")], scope: scope, fetchedAt: date(1), now: date(1))
        let event = try #require(explicitStore.observe(subjects: [weightedSubject(hidden: false, secondWeight: 4, average: "4.20")], scope: scope, fetchedAt: date(2)).first)
        #expect(event.editedMarkIDs == ["b"])
        #expect(event.addedMarkIDs.isEmpty)
    }

    @Test func clearAllPreservesOtherSchoolCachesAndPersonalPlanner() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SchoolInsightStateStore(directory: directory)
        store.activate(subjects: [subject([("a", "2")])], scope: scope, fetchedAt: date(1), now: date(1))
        let plannerURL = directory.appending(path: "personal-planner.json")
        let historyURL = directory.appending(path: "grade-history-cache-school.json")
        try Data("personal".utf8).write(to: plannerURL)
        try Data("cache".utf8).write(to: historyURL)
        store.clearAll()
        #expect(try Data(contentsOf: plannerURL) == Data("personal".utf8))
        #expect(try Data(contentsOf: historyURL) == Data("cache".utf8))
        #expect(store.observations(scope: scope, now: date(2)).isEmpty)
    }

    @Test func statePersistsAndScopesDoNotShareSeenFlags() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let firstStore = SchoolInsightStateStore(directory: directory)
        let first = subject([("a", "2")])
        let second = subject([("a", "2"), ("b", "4")])
        firstStore.activate(subjects: [first], scope: scope, fetchedAt: date(1), now: date(1))
        let event = try #require(firstStore.observe(subjects: [second], scope: scope, fetchedAt: date(2)).first)
        let restored = SchoolInsightStateStore(directory: directory)
        #expect(restored.activate(subjects: [second], scope: scope, fetchedAt: date(2), now: date(2)).count == 1)
        restored.markSeen([event.id], scope: SchoolDataScope(rawValue: "other"), at: date(2))
        #expect(restored.observations(scope: scope, now: date(2)).first?.seenAt == nil)
    }

    @Test func trendRequiresThreeComparablePointsAcrossSevenDays() {
        let first = observation("one", from: 2, to: 2.1, previous: date(1), now: date(4))
        let second = observation("two", from: 2.1, to: 2.3, previous: date(4), now: date(8))
        #expect(SubjectInsightEngine.trendDelta(observations: [first], now: date(8)) == nil)
        #expect(abs((SubjectInsightEngine.trendDelta(observations: [first, second], now: date(8)) ?? 0) - 0.3) < 0.00001)
        #expect(SubjectInsightEngine.trendDelta(observations: [first, second], now: date(8).addingTimeInterval(31 * 24 * 60 * 60)) == nil)
    }

    @Test func rankingCapsDeduplicatesAndExpiresWithoutDependingOnInputOrder() {
        let now = date(11)
        let events = (0..<3).map { offset in event(date: date(12 + offset, hour: 8), kind: .test) }
        let change = observation("change", from: 2.3, to: 2.6, previous: date(10), now: now)
        let summary = SubjectInsightSummary(subjectID: " M", subjectName: "Math", currentAverage: 2.6,
            observations: [change], trendDelta: 0.3, upcomingEvents: events)
        let output = TodayInsightEngine.make(subjectInsights: [summary], events: events, marksFetchedAt: now, now: now, calendar: calendar)
        #expect(output.count <= 3)
        #expect(output.first?.priority == 100)
        #expect(!output.contains { $0.kind == .busyTests })
        #expect(output.filter { $0.eventIDs.isEmpty && $0.subjectID == " M" }.count == 1)
        #expect(TodayInsightEngine.rank(output.reversed(), now: now) == output)
        #expect(TodayInsightEngine.rank(output, now: date(20)).isEmpty)
        #expect(TodayInsightEngine.make(subjectInsights: [summary], events: [], marksFetchedAt: now, now: now, schoolDataIsStale: true).isEmpty)
    }

    @Test func halfPointMarkersRequireMeaningfulMovement() {
        #expect(TodayInsightEngine.isMeaningfulAverageChange(from: 2.44, to: 2.55))
        #expect(!TodayInsightEngine.isMeaningfulAverageChange(from: 2.49, to: 2.51))
        #expect(TodayInsightEngine.isMeaningfulAverageChange(from: 2.2, to: 2.4))
        #expect(!TodayInsightEngine.isMeaningfulAverageChange(from: nil, to: 2.4))
    }

    @Test func busyWindowRemainsIdenticalWhenPlannerInputOrderChanges() {
        let now = date(11)
        let events = [event(date: date(13), kind: .test), event(date: date(14), kind: .test), event(date: date(15), kind: .test)]
        let first = TodayInsightEngine.make(subjectInsights: [], events: events, marksFetchedAt: nil, now: now, calendar: calendar)
        let second = TodayInsightEngine.make(subjectInsights: [], events: events.reversed(), marksFetchedAt: nil, now: now, calendar: calendar)
        #expect(first.count == 1)
        #expect(first.first?.kind == .busyTests)
        #expect(first == second)
        #expect(first.first?.relevantAt == date(13))
    }

    private func observation(_ id: String, from: Double, to: Double, previous: Date, now: Date) -> SchoolGradeObservation {
        SchoolGradeObservation(id: id, scope: scope, subjectID: " M", observedAt: now, previousObservedAt: previous,
            previousAverage: from, average: to, addedMarkIDs: [id], editedMarkIDs: [], digest: id, seenAt: nil)
    }
    private func event(date: Date, kind: SchoolEvent.Kind) -> SchoolEvent {
        SchoolEvent(id: UUID(), scope: scope, subjectID: " M", subjectName: "Math", title: "Assessment", kind: kind,
            date: date, hasTime: true, timeZoneIdentifier: calendar.timeZone.identifier, updatedAt: self.date(10))
    }
}
