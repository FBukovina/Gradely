import Foundation
import Observation

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
}

@MainActor
@Observable
final class TodayViewModel {
    var snapshot: TodaySnapshot = .empty
    var isLoading = false
    var isRefreshing = false
    var isActivatingAccountID: String?
    var errorMessage: String?

    private let repository: SchoolRepository
    private let stravaCZRepository: StravaCZRepository
    private let linkedAccountRepository: LinkedAccountRepository
    private let historyRepository: GradeyHistoryRepository
    private var hasLoaded = false

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.linkedAccountRepository = linkedAccountRepository
        self.historyRepository = historyRepository
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
            snapshot.orderedMeal = preferredMeal(from: menu)
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
            snapshot.orderedMeal = preferredMeal(from: data.menu)
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

    private func preferredMeal(from menu: StravaCZMenu) -> StravaCZMeal? {
        menu.days.first(where: \.ordered)?.orderedMainMeal ?? menu.orderedMeals.first
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
