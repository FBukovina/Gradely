import Foundation

enum GradeyAIContextError: LocalizedError, Equatable {
    case noSchoolAccount
    case noContextAvailable

    var errorDescription: String? {
        switch self {
        case .noSchoolAccount:
            return String(localized: "error.notLoggedIn")
        case .noContextAvailable:
            return String(localized: "gradey.ai.error.noContext")
        }
    }
}

protocol GradeyAIContextBuilding {
    func currentSchoolScope() throws -> String
    func cachedContext() throws -> GradeyAIContextSnapshot?
    func refreshContext() async throws -> GradeyAIContextSnapshot
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

    init(
        repository: SchoolRepository,
        historyRepository: GradeyHistoryRepository,
        schoolScopeHasher: any GradeyAISchoolScopeHashing = GradeyAISchoolScopeHasher(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.historyRepository = historyRepository
        self.schoolScopeHasher = schoolScopeHasher
        self.dateProvider = dateProvider
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
            guard let linkedAccountID = try repository.currentStoredSession()?.linkedAccountID,
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

    static func makeSubjects(from subjects: [Subject]) -> [GradeyAISubjectContext] {
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
        for candidate in candidates where total < maximumTotalMarks {
            guard selectedBySubject[candidate.subjectIndex, default: []].count < maximumMarksPerSubject else {
                continue
            }
            selectedBySubject[candidate.subjectIndex, default: []].append(candidate.mark)
            total += 1
        }

        return subjects.enumerated().map { index, subject in
            let name = trimmed(subject.trimmedName, maximumLength: 120)
                ?? trimmed(subject.trimmedAbbrev, maximumLength: 32)
                ?? subject.id
            return GradeyAISubjectContext(
                id: String(subject.id.prefix(128)),
                name: name,
                abbreviation: trimmed(subject.trimmedAbbrev, maximumLength: 32),
                average: GradeMath.subjectAverage(subject),
                pointsOnly: subject.pointsOnly,
                totalMarkCount: subject.marks.count,
                recentMarks: (selectedBySubject[index] ?? []).map(makeMark)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func makeTrends(from trends: [SubjectGradeTrend]) -> [GradeyAITrendContext] {
        Array(trends.prefix(maximumTrends)).map { trend in
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

    static func makeLessons(from weeks: [TimetableWeek]) -> [GradeyAILessonContext] {
        let orderedWeeks = weeks.sorted { $0.weekStart < $1.weekStart }
        var seenIDs: Set<String> = []
        var lessons: [GradeyAILessonContext] = []

        for week in orderedWeeks {
            for day in week.days.sorted(by: dayComesBefore) {
                guard let date = day.date else { continue }
                let dateString = TimetableDates.apiDateString(date)
                for lesson in day.lessons {
                    guard lessons.count < maximumLessons else { return lessons }
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
        [.marks, .trends, .timetable].filter { sections.contains($0) }
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
