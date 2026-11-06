import Foundation
import Observation

/// Gradey Recap: which recaps are out, what Today points at, and the full
/// recap behind each. The live semester comes from the shared snapshot,
/// earlier ones from the repository's archive.
@MainActor @Observable
final class RecapStore {
    static let hiddenKey = "gradey.recap.hidden.v1"
    /// Opening the story waits at most this long for timetable weeks.
    static let timetableTimeout: Duration = .seconds(10)

    let now: () -> Date
    private(set) var hiddenIDs: Set<String>
    private let repository: SchoolRepository
    private let defaults: UserDefaults
    @ObservationIgnored private weak var snapshot: SchoolSnapshotStore?
    @ObservationIgnored private var summaries: [String: Recap] = [:]
    @ObservationIgnored private var semesters: [RecapSemester]?
    @ObservationIgnored private var reportCards: [ReportCardTerm]?
    @ObservationIgnored private var cacheRevision: Int?
    @ObservationIgnored private var cacheDay: Date?

    init(repository: SchoolRepository, now: (() -> Date)? = nil, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.now = now ?? Self.launchNow()
        self.defaults = defaults
        hiddenIDs = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    func attach(_ snapshot: SchoolSnapshotStore) {
        self.snapshot = snapshot
    }

    /// Recaps that are out and have something in them, newest first.
    var periods: [RecapPeriod] {
        RecapCalendar.listed(at: now()).filter { summary(for: $0).hasContent }
    }

    /// The recap the Today row offers, until it's opened or hidden.
    var featured: RecapPeriod? {
        RecapCalendar.featured(at: now()).first { !hiddenIDs.contains($0.id) && summary(for: $0).hasContent }
    }

    func hide(_ period: RecapPeriod) {
        guard hiddenIDs.insert(period.id).inserted else { return }
        defaults.set(hiddenIDs.sorted(), forKey: Self.hiddenKey)
    }

    /// Marks and absence only; cheap enough for list rows.
    func summary(for period: RecapPeriod) -> Recap {
        resetCacheIfStale()
        if let cached = summaries[period.id] { return cached }
        let reportCards = reportCards ?? cachedReportCards()
        self.reportCards = reportCards
        let recap = RecapBuilder.build(period, input: input(reportCards: reportCards))
        summaries[period.id] = recap
        return recap
    }

    /// New school data or a new day starts the summaries over.
    private func resetCacheIfStale() {
        let revision = snapshot?.revision
        let day = RecapCalendar.calendar.startOfDay(for: now())
        guard revision != cacheRevision || day != cacheDay else { return }
        summaries = [:]
        semesters = nil
        reportCards = nil
        cacheRevision = revision
        cacheDay = day
    }

    /// Everything, including the period's timetable weeks and the subjects
    /// behind each day of absence.
    func recap(for period: RecapPeriod) async -> Recap {
        let reportCards = await loadReportCards()
        var input = input(reportCards: reportCards)
        let schoolYearStart = RecapCalendar.date(ReportCardPeriod(containing: now()).startYear, 9, 1)
        let tomorrow = RecapCalendar.calendar.date(byAdding: .day, value: 1, to: RecapCalendar.calendar.startOfDay(for: now())) ?? now()
        // Earlier school years' timetables are usually gone from Bakaláři.
        let start = max(period.start, schoolYearStart), end = min(period.end, tomorrow)
        let user = snapshot?.user
        // A whole semester reads Bakaláři's own per-subject absence instead.
        let absence = snapshot?.absence.flatMap { data in
            RecapArchive.semester(ofAbsence: data.response).map { period.semesters.contains($0) } == true
                && period.kind != .semester ? data : nil
        }
        let repository = repository

        async let weeks = Self.withTimeout { () -> [TimetableWeek]? in
            start < end ? await repository.loadTimetableWeeks(from: start, to: end) : nil
        }
        async let lessons = Self.withTimeout { () -> [String: AbsenceDayLessons]? in
            guard let absence else { return nil }
            return await repository.loadAbsenceDayLessons(for: absence, user: user)
        }
        input.timetableWeeks = await weeks ?? nil
        input.absenceLessons = await lessons ?? nil
        return RecapBuilder.build(period, input: input)
    }

    // MARK: - Input

    private func input(reportCards: [ReportCardTerm]) -> RecapInput {
        resetCacheIfStale()
        if semesters == nil { semesters = loadSemesters() }
        return RecapInput(semesters: semesters ?? [], reportCards: reportCards, now: now())
    }

    /// The archive plus the live snapshot, each semester's averages prepared once.
    private func loadSemesters() -> [RecapSemester] {
        let archive = repository.loadRecapArchive()
        var subjects: [ReportCardPeriod: [Subject]] = [:]
        var absences: [ReportCardPeriod: AbsenceResponse] = [:]
        for (key, response) in archive.marks {
            if let period = RecapArchive.period(forKey: key) { subjects[period] = response.subjects }
        }
        for (key, response) in archive.absence {
            if let period = RecapArchive.period(forKey: key) { absences[period] = response }
        }
        // The snapshot has the newest marks and the user's absence edits.
        if let live = snapshot?.subjects, let period = RecapArchive.semester(ofMarks: live) {
            subjects[period] = live
        }
        if let live = snapshot?.absence?.response, let period = RecapArchive.semester(ofAbsence: live) {
            absences[period] = live
        }
        let livePrepared = snapshot?.preparedCalculations ?? [:]
        let liveIDs = Set(snapshot?.subjects.map(\.id) ?? [])
        return Set(subjects.keys).union(absences.keys).map { period in
            let semesterSubjects = subjects[period] ?? []
            var prepared: [String: PreparedGradeCalculation] = [:]
            for subject in semesterSubjects {
                let live = liveIDs.contains(subject.id) ? livePrepared[subject.id] : nil
                prepared[subject.id] = live.flatMap { $0.revision == GradeMath.revision(for: subject) ? $0 : nil }
                    ?? GradeMath.prepare(subject)
            }
            return RecapSemester(period: period, subjects: semesterSubjects, absence: absences[period], prepared: prepared)
        }
    }

    private func cachedReportCards() -> [ReportCardTerm] {
        repository.loadCachedFinalMarks().map { $0.value.terms.map(ReportCardTerm.init) } ?? []
    }

    private func loadReportCards() async -> [ReportCardTerm] {
        guard repository.supportsReportCards, let response = try? await repository.loadFinalMarks() else {
            return cachedReportCards()
        }
        return response.terms.map(ReportCardTerm.init)
    }

    /// Nil when the work outlasts `timetableTimeout`; the slide is then left out.
    private static func withTimeout<Value: Sendable>(_ work: @escaping @Sendable () async -> Value) async -> Value? {
        let timeout = timetableTimeout
        return await withTaskGroup(of: Value?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Demo clock

    /// `-uiTestingRecapNow 2026-11-12` moves demo builds to that day, keeping the time of day.
    static func launchNow(arguments: [String] = ProcessInfo.processInfo.arguments) -> () -> Date {
        guard arguments.contains("-uiTestingMockAPI"),
              let index = arguments.firstIndex(of: "-uiTestingRecapNow"), arguments.indices.contains(index + 1),
              let day = Homework.schoolDate(arguments[index + 1]) else { return Date.init }
        let offset = day.timeIntervalSince(RecapCalendar.calendar.startOfDay(for: Date()))
        return { Date().addingTimeInterval(offset) }
    }
}
