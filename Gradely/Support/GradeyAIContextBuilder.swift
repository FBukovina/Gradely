import Foundation

enum GradeyAIContextError: LocalizedError, Equatable {
    case noSchoolAccount
    case noContextAvailable

    var errorDescription: String? {
        switch self {
        case .noSchoolAccount:
            return AppL10n.string("error.notLoggedIn")
        case .noContextAvailable:
            return AppL10n.string("gradey.ai.error.noContext")
        }
    }
}

protocol GradeyAIContextBuilding {
    func currentSchoolScope() throws -> String
    func cachedContext() throws -> GradeyAIContextSnapshot?
    func refreshContext() async throws -> GradeyAIContextSnapshot
    func cachedContext(for selection: GradeyAIContextSelection) throws -> GradeyAIContextSnapshot?
    func availableEvents() -> [GradeyAIEventContext]
    func availableSubjects() -> [GradeyAISubjectContext]
    func refreshContext(for selection: GradeyAIContextSelection) async throws -> GradeyAIContextSnapshot
}

extension GradeyAIContextBuilding {
    func availableSubjects() -> [GradeyAISubjectContext] { (try? cachedContext())?.subjects ?? [] }
    func availableEvents() -> [GradeyAIEventContext] { (try? cachedContext())?.events ?? [] }
    func cachedContext(for selection: GradeyAIContextSelection) throws -> GradeyAIContextSnapshot? {
        let scope = try currentSchoolScope()
        if selection.action == .reply { return GradeyAIContextBuilder.emptyContext(schoolScope: scope, now: Date()) }
        return try cachedContext().map { GradeyAIContextBuilder.select($0, for: selection, now: Date()) }
    }
    func refreshContext(for selection: GradeyAIContextSelection) async throws -> GradeyAIContextSnapshot {
        let scope = try currentSchoolScope()
        if selection.action == .reply { return GradeyAIContextBuilder.emptyContext(schoolScope: scope, now: Date()) }
        let snapshot = try await refreshContext()
        guard try currentSchoolScope() == scope, snapshot.schoolScope == scope else { throw CancellationError() }
        return GradeyAIContextBuilder.select(snapshot, for: selection, now: Date())
    }
}

final class GradeyAIContextBuilder: GradeyAIContextBuilding {
    static let maximumMarksPerSubject = 5
    static let maximumTotalMarks = 80
    static let maximumTrends = 20
    static let maximumLessons = 120

    private let repository: SchoolRepository
    private let historyRepository: GradeyHistoryRepository
    private let schoolScopeHasher: any GradeyAISchoolScopeHashing
    private let dateProvider: () -> Date
    private let snapshotStore: SchoolSnapshotStore?

    init(
        repository: SchoolRepository,
        historyRepository: GradeyHistoryRepository,
        schoolScopeHasher: any GradeyAISchoolScopeHashing = GradeyAISchoolScopeHasher(),
        dateProvider: @escaping () -> Date = Date.init,
        snapshotStore: SchoolSnapshotStore? = nil
    ) {
        self.repository = repository
        self.historyRepository = historyRepository
        self.schoolScopeHasher = schoolScopeHasher
        self.dateProvider = dateProvider
        self.snapshotStore = snapshotStore
    }

    func availableSubjects() -> [GradeyAISubjectContext] {
        guard let snapshotStore else { return (try? cachedContext())?.subjects ?? [] }
        snapshotStore.activateCurrentScope()
        return snapshotStore.subjects.map { subject in
            GradeyAISubjectContext(id: subject.id, name: subject.trimmedName, abbreviation: subject.trimmedAbbrev,
                average: snapshotStore.preparedCalculations[subject.id]?.displayAverage, pointsOnly: subject.pointsOnly,
                totalMarkCount: subject.marks.count, recentMarks: [])
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func availableEvents() -> [GradeyAIEventContext] {
        guard let snapshotStore else { return [] }
        snapshotStore.activateCurrentScope()
        return snapshotStore.events.filter { $0.isAssessment && $0.expiresAt > dateProvider() }.prefix(30).map { event in
            GradeyAIEventContext(id: event.id.uuidString, title: String(event.title.prefix(200)), type: event.kind.rawValue,
                                subjectID: event.subjectID, subjectName: event.subjectName, date: event.date.ISO8601Format(),
                                hasTime: event.hasTime, notes: nil)
        }
    }

    func cachedContext(for selection: GradeyAIContextSelection) throws -> GradeyAIContextSnapshot? {
        let scope = try currentSchoolScope(), now = dateProvider()
        if selection.action == .reply { return Self.emptyContext(schoolScope: scope, now: now) }
        if let snapshotStore {
            snapshotStore.activateCurrentScope()
            return selectedStoreContext(snapshotStore, selection: selection, schoolScope: scope, now: now)
        }
        return try cachedContext().map { Self.select($0, for: selection, now: now) }
    }

    func refreshContext(for selection: GradeyAIContextSelection) async throws -> GradeyAIContextSnapshot {
        let scope = try currentSchoolScope(), now = dateProvider()
        if selection.action == .reply { return Self.emptyContext(schoolScope: scope, now: now) }
        guard let snapshotStore else {
            let snapshot = try await refreshContext()
            guard try currentSchoolScope() == scope else { throw CancellationError() }
            return Self.select(snapshot, for: selection, now: now)
        }
        var requirements: SchoolRefreshRequirements = []
        switch selection.action {
        case .reply: break
        case .tomorrow: requirements = [.timetable]
        case .weekSummary: requirements = []
        case .studyPriorities: requirements = [.marks, .history]
        case .subjectHelp, .testPreparation: requirements = [.marks, .history]
        }
        await snapshotStore.refresh(requirements: requirements)
        if selection.action == .tomorrow || selection.action == .weekSummary {
            let lastDate = selection.action == .weekSummary ? Self.weekStart(containing: selection.weekStart ?? now) : (Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            await snapshotStore.refreshTimetable(containing: lastDate)
        }
        guard try currentSchoolScope() == scope else { throw CancellationError() }
        return selectedStoreContext(snapshotStore, selection: selection, schoolScope: scope, now: now)
    }

    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func emptyContext(schoolScope: String, now: Date) -> GradeyAIContextSnapshot {
        GradeyAIContextSnapshot(schoolScope: schoolScope, generatedAt: now, isStale: false,
                                unavailableSections: [], subjects: [], trends: [], timetable: [])
    }

    private func selectedStoreContext(_ store: SchoolSnapshotStore, selection: GradeyAIContextSelection, schoolScope: String, now: Date) -> GradeyAIContextSnapshot {
        let sourceFreshness: [GradeyAISourceFreshness] = ["marks", "trends", "timetable", "events", "insights"].map { section in
            if section == "events" { return GradeyAISourceFreshness(section: section, fetchedAt: now.timeIntervalSince1970 * 1_000, isStale: false) }
            let key = section == "trends" ? "history" : (section == "insights" ? "marks" : section)
            let selectedDate = selection.action == .weekSummary ? (selection.weekStart ?? now) : (Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            let timetableKey = "timetable-" + TimetableDates.apiDateString(TimetableDates.monday(of: selectedDate))
            let state = store.sourceState(section == "timetable" ? timetableKey : key)
            return GradeyAISourceFreshness(section: section, fetchedAt: state.lastSuccessAt.map { $0.timeIntervalSince1970 * 1_000 }, isStale: state.isStale(at: now, interval: section == "marks" ? 300 : 900))
        }
        var base = GradeyAIContextSnapshot(
            schoolScope: schoolScope, generatedAt: now, isStale: false,
            unavailableSections: sourceFreshness.compactMap { $0.fetchedAt == nil ? GradeyAIContextSection(rawValue: $0.section) : nil },
            subjects: Self.makeSubjects(from: store.subjects, preparedCalculations: store.preparedCalculations, maximumTotalMarkCount: .max), trends: Self.makeTrends(from: store.history.trends, maximumTrendCount: .max),
            timetable: Self.makeLessons(from: Array(store.timetableWeeks.values), maximumLessonCount: .max)
        )
        base.events = store.events.map { event in
            let notes = selection.includeNotes && event.id == selection.eventID
                ? store.plannerStore.items.first(where: { $0.id == event.id })?.notes : nil
            return GradeyAIEventContext(id: event.id.uuidString, title: String(event.title.prefix(200)), type: event.kind.rawValue,
                                       subjectID: event.subjectID, subjectName: event.subjectName,
                                       date: event.date.ISO8601Format(), hasTime: event.hasTime,
                                       notes: notes.map { String($0.prefix(1_000)) })
        }
        base.insights = Self.makeInsights(observations: store.observations, summaries: store.subjectInsights, preparedCalculations: store.preparedCalculations)
        base.sourceFreshness = sourceFreshness
        return Self.select(base, for: selection, now: now)
    }

    /// Only explicit action selection determines school-data disclosure; prose is
    /// never inspected to automatically add unrelated subjects or Planner notes.
    static func select(_ source: GradeyAIContextSnapshot, for selection: GradeyAIContextSelection, now: Date, calendar: Calendar = .current) -> GradeyAIContextSnapshot {
        if selection.action == .reply { return emptyContext(schoolScope: source.schoolScope, now: now) }
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let endTomorrow = calendar.date(byAdding: .day, value: 2, to: day) ?? tomorrow
        let weekStart = Self.weekStart(containing: selection.weekStart ?? now, calendar: calendar)
        let selectedWeekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        let selectedEvent = source.events?.first { $0.id == selection.eventID?.uuidString }
        let selectedSubject = selection.action == .testPreparation ? selectedEvent?.subjectID : selection.subjectID
        var subjectIDs = Set<String>()
        var required: Set<GradeyAIContextSection> = []
        var events: [GradeyAIEventContext] = []
        var lessons: [GradeyAILessonContext] = []
        func eventDate(_ event: GradeyAIEventContext) -> Date? { MarkDateFormatter.date(from: event.date) }
        func lessonDate(_ lesson: GradeyAILessonContext) -> Date? {
            let pieces = lesson.date.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard pieces.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
        }
        switch selection.action {
        case .reply: break
        case .tomorrow:
            required = [.timetable, .events]
            lessons = source.timetable.filter { lessonDate($0).map { $0 >= tomorrow && $0 < endTomorrow } == true }
            events = (source.events ?? []).filter { eventDate($0).map { $0 >= tomorrow && $0 < endTomorrow } == true }
        case .weekSummary:
            required = [.timetable, .events, .insights]
            lessons = source.timetable.filter { lessonDate($0).map { $0 >= weekStart && $0 < selectedWeekEnd } == true }
            events = (source.events ?? []).filter { eventDate($0).map { $0 >= weekStart && $0 < selectedWeekEnd } == true }
        case .studyPriorities:
            required = [.marks, .trends, .events, .insights]
            events = (source.events ?? []).filter { eventDate($0).map { $0 >= day && $0 < weekEnd } == true }
            let relevant = (source.insights ?? []).compactMap(\.subjectID) + events.compactMap(\.subjectID)
                + source.subjects.sorted { ($0.average ?? 0) > ($1.average ?? 0) }.map(\.id)
            let currentIDs = Set(source.subjects.map(\.id))
            for id in relevant where currentIDs.contains(id) && subjectIDs.count < 3 { subjectIDs.insert(id) }
        case .subjectHelp:
            required = [.marks, .trends, .events, .insights]
            if let selectedSubject { subjectIDs.insert(selectedSubject) }
            events = (source.events ?? []).filter { $0.subjectID == selectedSubject && selectedSubject != nil && eventDate($0).map { $0 >= day && $0 < weekEnd } == true }
        case .testPreparation:
            required = [.marks, .events]
            if let selectedSubject { subjectIDs.insert(selectedSubject) }
            if let selectedEvent { events = [selectedEvent] }
        }
        var unavailable = source.unavailableSections.filter { required.contains($0) }
        let subjects = source.subjects.filter { subjectIDs.contains($0.id) }.map { subject in
            GradeyAISubjectContext(id: subject.id, name: subject.name, abbreviation: subject.abbreviation,
                                  average: subject.average, pointsOnly: subject.pointsOnly, totalMarkCount: subject.totalMarkCount,
                                  recentMarks: selection.action == .studyPriorities ? [] : Array(subject.recentMarks.prefix(5)),
                                  calculation: subject.calculation)
        }
        if (selection.action == .subjectHelp || selection.action == .testPreparation) && subjects.isEmpty { unavailable.append(.marks) }
        if selection.action == .testPreparation && selectedEvent == nil { unavailable.append(.events) }
        let freshness = source.sourceFreshness?.filter { required.contains(GradeyAIContextSection(rawValue: $0.section) ?? .marks) }
        let isStale = !unavailable.isEmpty || (freshness?.contains(where: \.isStale) ?? source.isStale)
        var output = GradeyAIContextSnapshot(
            schoolScope: source.schoolScope, generatedAt: source.generatedAt, isStale: isStale,
            unavailableSections: orderedSections(Array(Set(unavailable))), subjects: subjects,
            trends: required.contains(.trends) ? source.trends.filter { subjectIDs.contains($0.subjectID) } : [],
            timetable: Array(lessons.prefix(60)).map { lesson in
                GradeyAILessonContext(id: lesson.id, date: lesson.date, subject: lesson.subject, subjectAbbreviation: lesson.subjectAbbreviation,
                                      beginsAt: lesson.beginsAt, endsAt: lesson.endsAt, teacher: nil, room: lesson.room, groups: [],
                                      changeKind: lesson.changeKind, changeDescription: nil)
            }
        )
        output.events = Array(events.prefix(30)).map { event in
            GradeyAIEventContext(id: event.id, title: event.title, type: event.type, subjectID: event.subjectID,
                                subjectName: event.subjectName, date: event.date, hasTime: event.hasTime,
                                notes: selection.includeNotes && event.id == selection.eventID?.uuidString ? event.notes : nil)
        }
        output.insights = required.contains(.insights) ? Array((source.insights ?? []).filter { insight in
            if selection.action == .weekSummary {
                guard insight.kind == "observed_grade_change", let observedAt = insight.observedAt else { return false }
                let date = Date(timeIntervalSince1970: observedAt / 1_000)
                return date >= weekStart && date < selectedWeekEnd
            }
            return insight.subjectID.map { subjectIDs.contains($0) } ?? false
        }.prefix(5)) : []
        output.sourceFreshness = freshness
        return output
    }

    func currentSchoolScope() throws -> String {
        guard let session = try repository.currentStoredSession() else {
            throw GradeyAIContextError.noSchoolAccount
        }
        return schoolScopeHasher.schoolScope(for: session)
    }

    func cachedContext() throws -> GradeyAIContextSnapshot? {
        let schoolScope = try currentSchoolScope()
        let now = dateProvider()
        let cachedMarks = try? repository.loadCachedMarks()
        let currentWeek = repository.loadCachedTimetable(weekContaining: now)
        let nextWeekDate = TimetableDates.addingWeeks(1, to: now)
        let nextWeek = repository.loadCachedTimetable(weekContaining: nextWeekDate)

        guard cachedMarks != nil || currentWeek != nil || nextWeek != nil else {
            return nil
        }

        var unavailable: [GradeyAIContextSection] = [.trends]
        if cachedMarks == nil { unavailable.append(.marks) }
        if currentWeek == nil || nextWeek == nil { unavailable.append(.timetable) }

        return GradeyAIContextSnapshot(
            schoolScope: schoolScope,
            generatedAt: cachedMarks?.cachedAt ?? now,
            isStale: true,
            unavailableSections: Self.orderedSections(unavailable),
            subjects: Self.makeSubjects(from: cachedMarks?.marksResponse.subjects ?? []),
            trends: [],
            timetable: Self.makeLessons(from: [currentWeek, nextWeek].compactMap { $0 })
        )
    }

    func refreshContext() async throws -> GradeyAIContextSnapshot {
        let schoolScope = try currentSchoolScope()
        let now = dateProvider()
        let nextWeekDate = TimetableDates.addingWeeks(1, to: now)
        let cached = try? cachedContext()

        async let dashboardAttempt = loadDashboardAttempt()
        async let historyAttempt = loadHistoryAttempt()
        async let currentTimetableAttempt = loadTimetableAttempt(weekContaining: now)
        async let nextTimetableAttempt = loadTimetableAttempt(weekContaining: nextWeekDate)

        let (dashboardResult, historyResult, currentWeekResult, nextWeekResult) = await (
            dashboardAttempt,
            historyAttempt,
            currentTimetableAttempt,
            nextTimetableAttempt
        )
        try Task.checkCancellation()
        guard try currentSchoolScope() == schoolScope else { throw CancellationError() }

        var unavailable: [GradeyAIContextSection] = []
        let subjects: [GradeyAISubjectContext]
        switch dashboardResult {
        case .success(let dashboard):
            subjects = Self.makeSubjects(from: dashboard.marksResponse.subjects)
        case .failure:
            unavailable.append(.marks)
            subjects = cached?.subjects ?? []
        }

        let trends: [GradeyAITrendContext]
        switch historyResult {
        case .success(let history):
            trends = Self.makeTrends(from: history.trends)
        case .failure:
            unavailable.append(.trends)
            trends = cached?.trends ?? []
        }

        var weeks: [TimetableWeek] = []
        var timetableWasUnavailable = false
        switch currentWeekResult {
        case .success(let week):
            weeks.append(week)
        case .failure:
            timetableWasUnavailable = true
            if let week = repository.loadCachedTimetable(weekContaining: now) {
                weeks.append(week)
            }
        }
        switch nextWeekResult {
        case .success(let week):
            weeks.append(week)
        case .failure:
            timetableWasUnavailable = true
            if let week = repository.loadCachedTimetable(weekContaining: nextWeekDate) {
                weeks.append(week)
            }
        }
        if timetableWasUnavailable { unavailable.append(.timetable) }

        let orderedUnavailable = Self.orderedSections(unavailable)
        let lessons = Self.makeLessons(from: weeks)
        guard orderedUnavailable.count < GradeyAIContextSection.allCasesCount
            || !subjects.isEmpty
            || !trends.isEmpty
            || !lessons.isEmpty
        else {
            throw GradeyAIContextError.noContextAvailable
        }

        return GradeyAIContextSnapshot(
            schoolScope: schoolScope,
            generatedAt: now,
            isStale: !orderedUnavailable.isEmpty,
            unavailableSections: orderedUnavailable,
            subjects: subjects,
            trends: trends,
            timetable: lessons
        )
    }

    private func loadDashboardAttempt() async -> Result<DashboardData, Error> {
        do {
            return .success(try await repository.loadDashboard(forceRefresh: false))
        } catch {
            return .failure(error)
        }
    }

    private func loadHistoryAttempt() async -> Result<GradeHistoryResponse, Error> {
        do {
            let session = try repository.currentStoredSession()
            // Cloud history has no EduPage child identifier, so it cannot be
            // attributed to the active student in either the iPhone or Watch path.
            guard session?.provider != .eduPage else { return .failure(GradeyAIContextError.noContextAvailable) }
            guard let linkedAccountID = session?.linkedAccountID,
                  !linkedAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .success(GradeHistoryResponse(events: [], recentNewMarkEvents: []))
            }
            return .success(try await historyRepository.loadGradeHistory(linkedAccountID: linkedAccountID, days: 90))
        } catch {
            return .failure(error)
        }
    }

    private func loadTimetableAttempt(weekContaining date: Date) async -> Result<TimetableWeek, Error> {
        do {
            return .success(try await repository.loadTimetable(weekContaining: date))
        } catch {
            return .failure(error)
        }
    }

    /// Share observed changes independently of Today ranking and seen state.
    /// Apply action/date/subject caps after this projection so a selected subject
    /// or older week is never displaced by unrelated earlier source records.
    static func makeInsights(observations: [SchoolGradeObservation], summaries: [SubjectInsightSummary], preparedCalculations: [String: PreparedGradeCalculation]) -> [GradeyAIInsightContext] {
        let changes = observations.sorted { $0.observedAt > $1.observedAt }.map { observation in
            var description = "Observed \(observation.addedMarkIDs.count) added and \(observation.editedMarkIDs.count) edited grades."
            if let previous = observation.previousAverage, let average = observation.average {
                description += " Recorded average: \(previous) to \(average)."
            }
            return GradeyAIInsightContext(id: String(observation.id.prefix(160)), subjectID: observation.subjectID,
                kind: "observed_grade_change", summary: String(description.prefix(400)),
                observedAt: observation.observedAt.timeIntervalSince1970 * 1_000,
                isEstimated: preparedCalculations[observation.subjectID]?.confidence != .exact)
        }
        let facts = summaries.map { summary in
            var description = "Subject: \(summary.subjectName)."
            if let average = summary.currentAverage { description += " Current recorded average: \(average)." }
            if let delta = summary.trendDelta { description += " Comparable observed trend change: \(delta)." }
            else { description += " Not enough comparable observations for a trend." }
            return GradeyAIInsightContext(id: "subject-summary-" + String(summary.subjectID.prefix(128)), subjectID: summary.subjectID,
                kind: "subject_summary", summary: String(description.prefix(400)), observedAt: nil,
                isEstimated: preparedCalculations[summary.subjectID]?.confidence != .exact)
        }
        return changes + facts
    }

    static func makeSubjects(from subjects: [Subject], preparedCalculations: [String: PreparedGradeCalculation] = [:], maximumTotalMarkCount: Int = maximumTotalMarks) -> [GradeyAISubjectContext] {
        struct Candidate {
            let subjectIndex: Int
            let mark: Mark
            let date: Date
            let originalIndex: Int
        }

        let candidates = subjects.enumerated()
            .flatMap { subjectIndex, subject in
                subject.marks.enumerated().map { markIndex, mark in
                    Candidate(
                        subjectIndex: subjectIndex,
                        mark: mark,
                        date: MarkDateFormatter.date(from: mark.markDate) ?? .distantPast,
                        originalIndex: markIndex
                    )
                }
            }
            .sorted { first, second in
                if first.date != second.date { return first.date > second.date }
                if first.subjectIndex != second.subjectIndex { return first.subjectIndex < second.subjectIndex }
                return first.originalIndex < second.originalIndex
            }

        var selectedBySubject: [Int: [Mark]] = [:]
        var total = 0
        for candidate in candidates where total < maximumTotalMarkCount {
            guard selectedBySubject[candidate.subjectIndex, default: []].count < maximumMarksPerSubject else {
                continue
            }
            selectedBySubject[candidate.subjectIndex, default: []].append(candidate.mark)
            total += 1
        }

        return subjects.enumerated().map { index, subject in
            let calculation = preparedCalculations[subject.id] ?? GradeMath.prepare(subject)
            let name = trimmed(subject.trimmedName, maximumLength: 120)
                ?? trimmed(subject.trimmedAbbrev, maximumLength: 32)
                ?? subject.id
            return GradeyAISubjectContext(
                id: String(subject.id.prefix(128)),
                name: name,
                abbreviation: trimmed(subject.trimmedAbbrev, maximumLength: 32),
                average: calculation.displayAverage,
                pointsOnly: subject.pointsOnly,
                totalMarkCount: subject.marks.count,
                recentMarks: (selectedBySubject[index] ?? []).map(makeMark),
                calculation: GradeyAIGradeCalculationContext(prepared: calculation)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func makeTrends(from trends: [SubjectGradeTrend], maximumTrendCount: Int = maximumTrends) -> [GradeyAITrendContext] {
        Array(trends.prefix(maximumTrendCount)).map { trend in
            GradeyAITrendContext(
                subjectID: String(trend.subjectID.prefix(128)),
                subjectName: trimmed(trend.subjectName, maximumLength: 120)
                    ?? trimmed(trend.subjectAbbrev, maximumLength: 32)
                    ?? String(trend.subjectID.prefix(128)),
                subjectAbbreviation: trimmed(trend.subjectAbbrev, maximumLength: 32),
                firstAverage: trend.firstAverage,
                latestAverage: trend.latestAverage,
                averageDelta: trend.averageDelta,
                firstMarkCount: trend.firstMarkCount,
                latestMarkCount: trend.latestMarkCount
            )
        }
    }

    static func makeLessons(from weeks: [TimetableWeek], maximumLessonCount: Int = maximumLessons) -> [GradeyAILessonContext] {
        let orderedWeeks = weeks.sorted { $0.weekStart < $1.weekStart }
        var seenIDs: Set<String> = []
        var lessons: [GradeyAILessonContext] = []

        for week in orderedWeeks {
            for day in week.days.sorted(by: dayComesBefore) {
                guard let date = day.date else { continue }
                let dateString = TimetableDates.apiDateString(date)
                for lesson in day.lessons {
                    guard lessons.count < maximumLessonCount else { return lessons }
                    let identifier = "\(dateString)#\(lesson.id)"
                    guard seenIDs.insert(identifier).inserted else { continue }
                    guard let subject = trimmed(lesson.subjectName, maximumLength: 120)
                        ?? trimmed(lesson.subjectAbbrev, maximumLength: 32)
                    else {
                        continue
                    }
                    lessons.append(GradeyAILessonContext(
                        id: String(identifier.prefix(180)),
                        date: dateString,
                        subject: subject,
                        subjectAbbreviation: trimmed(lesson.subjectAbbrev, maximumLength: 32),
                        beginsAt: String(lesson.hour.beginTime.prefix(16)),
                        endsAt: String(lesson.hour.endTime.prefix(16)),
                        teacher: trimmed(lesson.teacherName, maximumLength: 120)
                            ?? trimmed(lesson.teacherAbbrev, maximumLength: 32),
                        room: trimmed(lesson.roomName, maximumLength: 120)
                            ?? trimmed(lesson.roomAbbrev, maximumLength: 32),
                        groups: lesson.groups.compactMap { trimmed($0, maximumLength: 64) }.prefix(12).map { $0 },
                        changeKind: makeChangeKind(lesson.changeKind),
                        changeDescription: trimmed(lesson.change?.description, maximumLength: 300)
                    ))
                }
            }
        }
        return lessons
    }

    nonisolated private static func makeMark(_ mark: Mark) -> GradeyAIMarkContext {
        GradeyAIMarkContext(
            value: String(mark.displayText.prefix(64)),
            date: String(mark.markDate.split(separator: "T").first ?? Substring(mark.markDate)).prefix(32).description,
            weight: mark.weight,
            title: trimmed(mark.displayCaption, maximumLength: 200),
            isPoints: mark.isPoints,
            pointsText: trimmed(mark.pointsText, maximumLength: 64),
            maxPoints: mark.maxPoints
        )
    }

    private static func makeChangeKind(_ kind: LessonChangeKind) -> GradeyAILessonChangeKind {
        switch kind {
        case .none: .none
        case .canceled: .cancelled
        case .substitution: .substitution
        case .roomChanged: .roomChanged
        case .added: .added
        }
    }

    nonisolated private static func dayComesBefore(_ first: ScheduledDay, _ second: ScheduledDay) -> Bool {
        switch (first.date, second.date) {
        case let (firstDate?, secondDate?): firstDate < secondDate
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): first.dayOfWeek < second.dayOfWeek
        }
    }

    private static func orderedSections(_ sections: [GradeyAIContextSection]) -> [GradeyAIContextSection] {
        [.marks, .trends, .timetable, .events, .insights].filter { sections.contains($0) }
    }

    private static func trimmed(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        return String(trimmedValue.prefix(maximumLength))
    }
}

final class MockGradeyAIContextBuilder: GradeyAIContextBuilding {
    var snapshot: GradeyAIContextSnapshot?
    var refreshSnapshot: GradeyAIContextSnapshot?
    var error: Error?

    init(snapshot: GradeyAIContextSnapshot? = nil, refreshSnapshot: GradeyAIContextSnapshot? = nil) {
        self.snapshot = snapshot
        self.refreshSnapshot = refreshSnapshot
    }

    func currentSchoolScope() throws -> String {
        if let error { throw error }
        guard let schoolScope = (refreshSnapshot ?? snapshot)?.schoolScope else {
            throw GradeyAIContextError.noSchoolAccount
        }
        return schoolScope
    }

    func cachedContext() throws -> GradeyAIContextSnapshot? {
        if let error { throw error }
        return snapshot
    }

    func refreshContext() async throws -> GradeyAIContextSnapshot {
        if let error { throw error }
        guard let refreshed = refreshSnapshot ?? snapshot else {
            throw GradeyAIContextError.noContextAvailable
        }
        snapshot = refreshed
        return refreshed
    }
}

private extension GradeyAIContextSection {
    static let allCasesCount = 3
}
