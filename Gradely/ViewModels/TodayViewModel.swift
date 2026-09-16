import Foundation
import Observation

struct TodayNewMark: Equatable, Identifiable {
    let id: String
    let markText: String
    /// Short subject label (abbreviation first) for compact copy.
    let subjectName: String
    /// Full subject name for row titles, falling back to the abbreviation.
    let subjectTitle: String
    let subjectID: String
    let detectedAt: Date?
    let band: GradeBand
    let caption: String?
    let isNew: Bool

    init(event: NewMarkEvent) {
        id = "history-\(event.id)"
        markText = event.markText
        subjectName = event.subjectAbbrev ?? event.subjectName ?? "school"
        subjectTitle = event.subjectName ?? event.subjectAbbrev ?? "school"
        subjectID = event.subjectID
        detectedAt = event.createdAt
        band = .neutral
        caption = nil
        isNew = true
    }

    init(mark: Mark, subject: Subject) {
        id = "mark-\(subject.id)-\(mark.id)"
        markText = mark.displayText
        subjectName = subject.trimmedAbbrev.isEmpty ? subject.trimmedName : subject.trimmedAbbrev
        subjectTitle = subject.trimmedName.isEmpty ? subject.trimmedAbbrev : subject.trimmedName
        subjectID = subject.id
        detectedAt = MarkDateFormatter.date(from: mark.markDate)
        band = GradeMath.band(for: mark)
        let trimmedCaption = (mark.caption ?? mark.theme ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        caption = trimmedCaption.isEmpty ? nil : trimmedCaption
        isNew = mark.isNew
    }
}

struct TodaySnapshot: Equatable {
    var activeAccount: LinkedAccount?
    var linkedSchoolAccounts: [LinkedAccount]
    var user: UserResponse?
    var subjects: [Subject]
    var timetableSummary: TimetableTodaySummary?
    var absenceRisk: AbsenceRiskSummary?
    var stravaSession: StravaCZStoredSession?
    var orderedMeal: StravaCZMeal?
    var gradeHistory: GradeHistoryResponse
    var refreshedAt: Date?
    var usesPreparedAverages = false
    var preparedOverallAverage: Double?
    /// Every timed lesson in today's timetable, in chronological order.
    var todayLessons: [ScheduledLesson] = []
    /// Elapsed fraction (0…1) of the lesson that is running right now.
    var currentLessonProgress: Double?

    static let empty = TodaySnapshot(
        activeAccount: nil,
        linkedSchoolAccounts: [],
        user: nil,
        subjects: [],
        timetableSummary: nil,
        absenceRisk: nil,
        stravaSession: nil,
        orderedMeal: nil,
        gradeHistory: GradeHistoryResponse(events: [], recentNewMarkEvents: []),
        refreshedAt: nil
    )

    var overallAverage: Double? {
        usesPreparedAverages ? preparedOverallAverage : GradeMath.overallAverage(for: subjects)
    }

    var totalMarks: Int {
        subjects.reduce(0) { $0 + $1.marks.count }
    }

    /// Lessons that still take place today (cancelled periods are excluded).
    var activeLessonCount: Int {
        todayLessons.filter { !$0.isCanceled }.count
    }

    var cancelledLessonCount: Int {
        todayLessons.filter(\.isCanceled).count
    }

    /// The student's name for the greeting. Bakaláři appends the class to
    /// `FullName` ("Novák Jan, 3.A"), which reads oddly in a greeting.
    var greetingName: String? {
        let classAbbrev = user?.userClass?.abbrev
        if let user {
            let name = Self.nameWithoutClass(user.fullName, classAbbrev: classAbbrev)
            if !name.isEmpty { return name }
        }
        if let activeAccount {
            let name = Self.nameWithoutClass(activeAccount.displayName, classAbbrev: classAbbrev)
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Short label for the account chip. With several linked students the name
    /// identifies who is shown; otherwise the class is enough context.
    var accountChipLabel: String? {
        if linkedSchoolAccounts.count > 1, let activeAccount {
            let name = Self.nameWithoutClass(activeAccount.displayName, classAbbrev: user?.userClass?.abbrev)
            if !name.isEmpty { return name }
        }
        if let abbrev = user?.userClass?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines), !abbrev.isEmpty {
            return abbrev
        }
        if let name = activeAccount?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return nil
    }

    /// The newest recorded marks across all subjects, one entry per mark.
    func recentMarks(limit: Int = 3) -> [TodayNewMark] {
        guard limit > 0 else { return [] }
        let marks = subjects
            .flatMap { subject in subject.marks.map { TodayNewMark(mark: $0, subject: subject) } }
            .sorted { lhs, rhs in
                if lhs.detectedAt != rhs.detectedAt {
                    return (lhs.detectedAt ?? .distantPast) > (rhs.detectedAt ?? .distantPast)
                }
                return lhs.id < rhs.id
            }
        var seen: Set<String> = []
        var output: [TodayNewMark] = []
        for mark in marks where seen.insert(mark.id).inserted {
            output.append(mark)
            if output.count == limit { break }
        }
        return output
    }

    static func nameWithoutClass(_ fullName: String, classAbbrev: String?) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let classAbbrev = classAbbrev?.trimmingCharacters(in: .whitespacesAndNewlines), !classAbbrev.isEmpty {
            let suffix = "," + classAbbrev
            let compact = trimmed.replacingOccurrences(of: ", ", with: ",")
            if compact.hasSuffix(suffix), compact.count > suffix.count {
                let cut = trimmed.range(of: ",", options: .backwards).map { trimmed[..<$0.lowerBound] } ?? Substring(trimmed)
                return cut.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Without class metadata, only strip a short class-like token ("3.A", "T2.C").
        guard let comma = trimmed.range(of: ",", options: .backwards) else { return trimmed }
        let candidate = trimmed[comma.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeClass = !candidate.isEmpty && candidate.count <= 6
            && candidate.contains(where: \.isNumber) && !candidate.contains(" ")
        guard looksLikeClass else { return trimmed }
        let name = trimmed[..<comma.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : name
    }

    /// Chronological order for today's lessons. Provider hour IDs are ordinal,
    /// but begin times are the source of truth when both are available.
    static func orderedLessons(_ lessons: [ScheduledLesson]) -> [ScheduledLesson] {
        lessons.sorted { lhs, rhs in
            let lhsStart = minutes(lhs.hour.beginTime) ?? Int.max
            let rhsStart = minutes(rhs.hour.beginTime) ?? Int.max
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            if lhs.hour.id != rhs.hour.id { return lhs.hour.id < rhs.hour.id }
            return lhs.id < rhs.id
        }
    }

    /// Elapsed fraction of `lesson` at `now`, clamped to 0…1. `nil` when the
    /// hour has no usable times or the lesson is not running.
    static func lessonProgress(for lesson: ScheduledLesson, on day: Date, now: Date,
                               calendar: Calendar = .current) -> Double? {
        guard let start = TimetableLessonTiming.date(lesson.hour.beginTime, on: day, calendar: calendar),
              let end = TimetableLessonTiming.date(lesson.hour.endTime, on: day, calendar: calendar),
              end > start, now >= start, now < end
        else { return nil }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return min(max(fraction, 0), 1)
    }

    private static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    var topTrends: [SubjectGradeTrend] {
        gradeHistory.trends.filter { ($0.averageDelta ?? 0) != 0 }.prefix(4).map { $0 }
    }

    /// The school API's `IsNew` flag is available before the cloud polling
    /// service has enough snapshots to produce new-mark events or trends.
    var newMarks: [TodayNewMark] {
        let cloudMarks = gradeHistory.recentNewMarkEvents.map { TodayNewMark(event: $0) }
        guard cloudMarks.isEmpty else { return cloudMarks }

        return subjects
            .flatMap { subject in
                subject.marks
                    .filter(\.isNew)
                    .map { TodayNewMark(mark: $0, subject: subject) }
            }
            .sorted { ($0.detectedAt ?? .distantPast) > ($1.detectedAt ?? .distantPast) }
    }
}

@MainActor
@Observable
final class TodayViewModel {
    var snapshot: TodaySnapshot = .empty
    var isLoading = false
    var isRefreshing = false
    var isActivatingAccountID: String?
    var errorMessage: String?
    private(set) var hasCheckedLinkedAccountStatus = false

    private let repository: SchoolRepository
    private let stravaCZRepository: StravaCZRepository
    private let linkedAccountRepository: LinkedAccountRepository
    private let historyRepository: GradeyHistoryRepository
    private let accountSettingsClient: (any GradeyAccountSettingsClient)?
    private let gradeyAuthClient: (any GradeyAuthClient)?
    private let snapshotStore: SchoolSnapshotStore?
    private var hasLoaded = false
    private var timetableWeek: TimetableWeek?

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository,
        accountSettingsClient: (any GradeyAccountSettingsClient)? = nil,
        gradeyAuthClient: (any GradeyAuthClient)? = nil,
        snapshotStore: SchoolSnapshotStore? = nil
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.linkedAccountRepository = linkedAccountRepository
        self.historyRepository = historyRepository
        self.accountSettingsClient = accountSettingsClient
        self.gradeyAuthClient = gradeyAuthClient
        self.snapshotStore = snapshotStore
    }

    var accountRequiringReconnect: LinkedAccount? {
        if let accountRequiringDeviceSignIn { return accountRequiringDeviceSignIn }
        guard hasCheckedLinkedAccountStatus else { return nil }
        let candidates = snapshot.linkedSchoolAccounts.filter {
            $0.status == .actionRequired || $0.status == .failed
        }
        return candidates.first(where: { $0.id == snapshot.activeAccount?.id })
            ?? candidates.first
    }

    private var accountRequiringDeviceSignIn: LinkedAccount?

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadCachedSnapshot()
        await refresh(forceRefresh: false)
    }

    func refresh(forceRefresh: Bool = true) async {
        errorMessage = nil
        snapshotStore?.activateCurrentScope()
        applySharedSnapshot()
        if snapshot.subjects.isEmpty && snapshot.timetableSummary == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        await refreshLinkedAccountStatus()
        snapshot.linkedSchoolAccounts = linkedSchoolAccounts()
        snapshot.activeAccount = activeLinkedAccount()

        if let snapshotStore {
            // Account recovery may have replaced the provider session. Hydrate that scope first.
            snapshotStore.activateCurrentScope()
            applySharedSnapshot()
            async let school: Void = snapshotStore.refresh(requirements: .today, force: forceRefresh)
            async let meals: Void = refreshStrava()
            _ = await (school, meals)
            applySharedSnapshot()
            return
        }

        do {
            let dashboard = try await repository.loadDashboard(forceRefresh: forceRefresh)
            snapshot.subjects = dashboard.marksResponse.subjects
            snapshot.user = dashboard.user
        } catch {
            if snapshot.subjects.isEmpty {
                errorMessage = userFacingMessage(for: error)
            }
        }

        await refreshTimetable()
        await refreshAbsenceRisk(forceRefresh: forceRefresh)
        await refreshStrava()
        await refreshHistory()
        snapshot.refreshedAt = Date()
    }

    func activateAccount(_ account: LinkedAccount) async {
        guard account.provider.isSchoolProvider else { return }
        isActivatingAccountID = account.id
        errorMessage = nil
        defer { isActivatingAccountID = nil }

        do {
            let activation = try await linkedAccountRepository.activateSchoolAccount(id: account.id)
            _ = try await repository.activateLinkedSchoolAccount(activation)
            accountRequiringDeviceSignIn = nil
            snapshot = .empty
            loadCachedSnapshot()
            await refresh(forceRefresh: false)
        } catch SchoolAuthenticationError.deviceSignInRequired {
            accountRequiringDeviceSignIn = account
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func reconnect(_ account: LinkedAccount) async -> Bool {
        errorMessage = nil

        do {
            try await restoreSchoolConnection(account)
            accountRequiringDeviceSignIn = nil
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func loginPrefill(for account: LinkedAccount) -> SchoolLoginPrefill? {
        guard let session = try? repository.currentStoredSession() else {
            return nil
        }
        return SchoolLoginPrefill(
            session: session,
            account: account,
            allowsUnscopedSession: snapshot.linkedSchoolAccounts.count == 1
        )
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadCachedSnapshot() {
        snapshot.linkedSchoolAccounts = linkedSchoolAccounts()
        snapshot.activeAccount = activeLinkedAccount()

        if let snapshotStore {
            snapshotStore.activateCurrentScope()
            applySharedSnapshot()
            loadCachedMeals()
            return
        }

        if let cached = try? repository.loadCachedMarks() {
            snapshot.subjects = cached.marksResponse.subjects
            snapshot.refreshedAt = cached.cachedAt
        }

        if let week = repository.loadCachedTimetable(weekContaining: Date()) {
            timetableWeek = week
            refreshTime()
        }

        if let cachedAbsence = try? repository.loadCachedAbsence() {
            snapshot.absenceRisk = AbsenceRiskSummary.make(
                response: cachedAbsence.response,
                subjects: cachedAbsence.response.absencesPerSubject
            )
        }

        loadCachedMeals()
    }

    private func loadCachedMeals() {
        if let session = try? stravaCZRepository.bootstrapSession() {
            snapshot.stravaSession = session
        }
        if let menu = try? stravaCZRepository.loadCachedMenu()?.menu {
            snapshot.orderedMeal = Self.preferredMeal(from: menu)
        }
    }

    private func refreshTimetable() async {
        do {
            let week = try await repository.loadTimetable(weekContaining: Date())
            timetableWeek = week
            refreshTime()
        } catch {
            if snapshot.timetableSummary == nil {
                snapshot.timetableSummary = nil
            }
        }
    }

    func applySharedSnapshot(at now: Date = Date()) {
        guard let snapshotStore else { return }
        snapshot.subjects = snapshotStore.subjects
        let averages = snapshotStore.preparedCalculations.values.compactMap(\.displayAverage)
        snapshot.usesPreparedAverages = true
        snapshot.preparedOverallAverage = averages.isEmpty ? nil : averages.reduce(0, +) / Double(averages.count)
        snapshot.user = snapshotStore.user
        snapshot.gradeHistory = snapshotStore.history
        snapshot.refreshedAt = snapshotStore.marksFetchedAt
        if let absence = snapshotStore.absence {
            let subjects = absence.absencesPerSubject.isEmpty ? absence.response.absencesPerSubject : absence.absencesPerSubject
            snapshot.absenceRisk = AbsenceRiskSummary.make(response: absence.response, subjects: subjects)
        } else { snapshot.absenceRisk = nil }
        timetableWeek = snapshotStore.cachedWeek(containing: now)
        refreshTime(at: now)
    }

    func refreshTime(at now: Date = Date()) {
        if let snapshotStore { timetableWeek = snapshotStore.cachedWeek(containing: now) }
        guard let day = timetableWeek?.days.first(where: { day in
            day.date.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
        }) else {
            snapshot.timetableSummary = nil
            snapshot.todayLessons = []
            snapshot.currentLessonProgress = nil
            return
        }
        // `isToday` was calculated when the week was mapped; rebuild this flag after midnight.
        let today = ScheduledDay(id: day.id, date: day.date, dayOfWeek: day.dayOfWeek,
            dayType: day.dayType, dayDescription: day.dayDescription, lessons: day.lessons, isToday: true)
        let summary = TimetableTodaySummaryBuilder.make(for: today, now: now)
        snapshot.timetableSummary = summary
        snapshot.todayLessons = TodaySnapshot.orderedLessons(day.lessons)
        snapshot.currentLessonProgress = summary?.currentLesson.flatMap {
            TodaySnapshot.lessonProgress(for: $0, on: day.date ?? now, now: now)
        }
    }

    private func refreshAbsenceRisk(forceRefresh: Bool) async {
        do {
            let absence = try await repository.loadAbsence(forceRefresh: forceRefresh)
            let subjects = absence.absencesPerSubject.isEmpty ? absence.response.absencesPerSubject : absence.absencesPerSubject
            snapshot.absenceRisk = AbsenceRiskSummary.make(response: absence.response, subjects: subjects)
        } catch {
            if snapshot.absenceRisk == nil {
                snapshot.absenceRisk = nil
            }
        }
    }

    private func refreshStrava() async {
        do {
            let data = try await stravaCZRepository.loadMenu(forceRefresh: false)
            snapshot.stravaSession = data.session
            snapshot.orderedMeal = Self.preferredMeal(from: data.menu)
        } catch {
            if let session = try? stravaCZRepository.bootstrapSession() {
                snapshot.stravaSession = session
            }
        }
    }

    private func refreshHistory() async {
        do {
            snapshot.gradeHistory = try await historyRepository.loadGradeHistory(
                linkedAccountID: snapshot.activeAccount?.id,
                days: 400
            )
        } catch {
            snapshot.gradeHistory = GradeHistoryResponse(events: [], recentNewMarkEvents: [])
        }
    }

    private func refreshLinkedAccountStatus() async {
        defer { hasCheckedLinkedAccountStatus = true }
        guard let accountSettingsClient, let gradeyAuthClient else { return }

        do {
            let gradeySession = try await gradeyAuthClient.validSession()
            let settings = try await accountSettingsClient.fetchAccountSettings(
                gradeySession: gradeySession
            )
            linkedAccountRepository.replaceLocalAccounts(settings.linkedAccounts)
            await recoverSchoolConnectionIfNeeded()
        } catch {
            // Account recovery should still work from the last cached status
            // while the Gradey account service is temporarily unavailable.
            await recoverSchoolConnectionIfNeeded()
        }
    }

    private func recoverSchoolConnectionIfNeeded() async {
        guard allowsAutomaticSchoolRecovery else { return }
        let accounts = linkedSchoolAccounts().filter {
            $0.status == .actionRequired || $0.status == .failed
        }
        guard let account = accounts.first(where: { $0.id == activeLinkedAccount()?.id })
                ?? accounts.first,
              canSilentlyRecover(account)
        else { return }

        do {
            try await restoreSchoolConnection(account)
        } catch {
            // Leave the account in its cloud status so the reconnect banner
            // can still be shown when a silent restore is not possible.
        }
    }

    private func restoreSchoolConnection(_ account: LinkedAccount) async throws {
        let session = try await repository.validSession()
        let user = await repository.loadUser()
        let reconnectedAccount = try await linkedAccountRepository.reconnectSchoolAccount(
            id: account.id,
            session: session,
            user: user
        )
        try repository.associateCurrentSession(with: reconnectedAccount)
        snapshot.linkedSchoolAccounts = linkedSchoolAccounts()
        snapshot.activeAccount = activeLinkedAccount()
    }

    private func canSilentlyRecover(_ account: LinkedAccount) -> Bool {
        guard account.provider.isSchoolProvider else { return false }
        guard let session = try? repository.currentStoredSession() else { return false }
        guard LinkedAccountProvider(schoolProvider: session.provider) == account.provider else {
            return false
        }
        if let linkedAccountID = session.linkedAccountID, linkedAccountID != account.id {
            return linkedSchoolAccounts().count == 1
        }
        return true
    }

    private var allowsAutomaticSchoolRecovery: Bool {
        !ProcessInfo.processInfo.arguments.contains("-uiTestingLinkedAccountActionRequired")
    }

    private func linkedSchoolAccounts() -> [LinkedAccount] {
        linkedAccountRepository.loadAccounts()
            .filter { $0.provider.isSchoolProvider }
            .sorted { $0.displayName < $1.displayName }
    }

    private func activeLinkedAccount() -> LinkedAccount? {
        let accounts = linkedSchoolAccounts()
        if let linkedAccountID = try? repository.currentStoredSession()?.linkedAccountID,
           let active = accounts.first(where: { $0.id == linkedAccountID }) {
            return active
        }
        return accounts.first
    }

    static func preferredMeal(from menu: StravaCZMenu, on date: Date = Date()) -> StravaCZMeal? {
        let todayKey = TimetableDates.apiDateString(date)
        return menu.days.first(where: { $0.dateKey == todayKey })?.orderedMainMeal
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
