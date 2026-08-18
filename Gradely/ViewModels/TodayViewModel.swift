import Foundation
import Observation

struct TodayNewMark: Equatable, Identifiable {
    let id: String
    let markText: String
    let subjectName: String
    let detectedAt: Date?

    init(event: NewMarkEvent) {
        id = "history-\(event.id)"
        markText = event.markText
        subjectName = event.subjectAbbrev ?? event.subjectName ?? "school"
        detectedAt = event.createdAt
    }

    init(mark: Mark, subject: Subject) {
        id = "mark-\(mark.id)"
        markText = mark.displayText
        subjectName = subject.trimmedAbbrev.isEmpty ? subject.trimmedName : subject.trimmedAbbrev
        detectedAt = MarkDateFormatter.date(from: mark.markDate)
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
        GradeMath.overallAverage(for: subjects)
    }

    var totalMarks: Int {
        subjects.reduce(0) { $0 + $1.marks.count }
    }

    var topTrends: [SubjectGradeTrend] {
        gradeHistory.trends.filter { ($0.averageDelta ?? 0) != 0 }.prefix(4).map { $0 }
    }

    /// The school API's `IsNew` flag is available before the cloud polling
    /// service has enough snapshots to produce new-mark events or trends.
    var newMarks: [TodayNewMark] {
        let cloudMarks = gradeHistory.recentNewMarkEvents.map(TodayNewMark.init(event:))
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
    private var hasLoaded = false

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository,
        accountSettingsClient: (any GradeyAccountSettingsClient)? = nil,
        gradeyAuthClient: (any GradeyAuthClient)? = nil
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.linkedAccountRepository = linkedAccountRepository
        self.historyRepository = historyRepository
        self.accountSettingsClient = accountSettingsClient
        self.gradeyAuthClient = gradeyAuthClient
    }

    var accountRequiringReconnect: LinkedAccount? {
        guard hasCheckedLinkedAccountStatus else { return nil }
        let candidates = snapshot.linkedSchoolAccounts.filter {
            $0.status == .actionRequired || $0.status == .failed
        }
        return candidates.first(where: { $0.id == snapshot.activeAccount?.id })
            ?? candidates.first
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadCachedSnapshot()
        await refresh(forceRefresh: false)
    }

    func refresh(forceRefresh: Bool = true) async {
        errorMessage = nil
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
            _ = try repository.activateLinkedSchoolAccount(activation)
            snapshot = .empty
            loadCachedSnapshot()
            await refresh(forceRefresh: false)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func reconnect(_ account: LinkedAccount) async -> Bool {
        errorMessage = nil

        do {
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

        if let cached = try? repository.loadCachedMarks() {
            snapshot.subjects = cached.marksResponse.subjects
            snapshot.refreshedAt = cached.cachedAt
        }

        if let week = repository.loadCachedTimetable(weekContaining: Date()) {
            snapshot.timetableSummary = TimetableTodaySummaryBuilder.make(for: week.days.first(where: \.isToday))
        }

        if let cachedAbsence = try? repository.loadCachedAbsence() {
            snapshot.absenceRisk = AbsenceRiskSummary.make(
                response: cachedAbsence.response,
                subjects: cachedAbsence.response.absencesPerSubject
            )
        }

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
            snapshot.timetableSummary = TimetableTodaySummaryBuilder.make(for: week.days.first(where: \.isToday))
        } catch {
            if snapshot.timetableSummary == nil {
                snapshot.timetableSummary = nil
            }
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
        } catch {
            // Account recovery should still work from the last cached status
            // while the Gradey account service is temporarily unavailable.
        }
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
