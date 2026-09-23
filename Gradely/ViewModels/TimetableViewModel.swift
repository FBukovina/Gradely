import Foundation
import Observation

@MainActor
@Observable
final class TimetableViewModel {
    var isLoading = false
    var isRefreshing = false
    var week: TimetableWeek?
    var user: UserResponse?
    var errorMessage: String?
    private(set) var kind: TimetableKind = .weekly

    /// The id of the day currently selected in the week strip.
    private(set) var selectedDayID: String?
    /// Any date inside the week currently on screen.
    private(set) var weekAnchor: Date

    private let repository: SchoolRepository
    private let today: Date
    private var hasLoaded = false
    private var activeRequestID = UUID()

    init(repository: SchoolRepository, today: Date = Date()) {
        self.repository = repository
        self.today = today
        weekAnchor = today
    }

    // MARK: - Derived state

    var supportsPermanentTimetable: Bool { repository.supportsPermanentTimetable }

    var schoolScope: SchoolDataScope? {
        (try? repository.currentStoredSession()).map(SchoolDataScope.init(session:))
    }

    var days: [ScheduledDay] { week?.days ?? [] }

    var selectedDay: ScheduledDay? {
        guard let week else { return nil }
        if let selectedDayID, let match = week.days.first(where: { $0.id == selectedDayID }) {
            return match
        }
        return week.days.first
    }

    var weekTitle: String {
        TimetableDates.weekRangeTitle(weekStart: TimetableDates.monday(of: weekAnchor))
    }

    var todaySummary: TimetableTodaySummary? {
        guard kind == .weekly else { return nil }
        return TimetableTodaySummaryBuilder.make(for: selectedDay)
    }

    /// Whether the displayed week is the one containing today (used to gate the "Today" button).
    var isViewingCurrentWeek: Bool {
        TimetableDates.apiDateString(TimetableDates.monday(of: weekAnchor))
            == TimetableDates.apiDateString(TimetableDates.monday(of: today))
    }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = repository.loadCachedTimetable(weekContaining: weekAnchor, kind: kind) {
            apply(cached, preserveSelection: false)
        }

        await refresh()

        if user == nil {
            user = await repository.loadUser()
        }
    }

    func refresh() async {
        let requestID = UUID()
        activeRequestID = requestID
        let requestedKind = kind
        let requestedAnchor = weekAnchor
        errorMessage = nil
        if week == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            if activeRequestID == requestID {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let loaded = try await repository.loadTimetable(weekContaining: requestedAnchor, kind: requestedKind)
            guard activeRequestID == requestID else { return }
            apply(loaded, preserveSelection: true)
        } catch {
            guard activeRequestID == requestID, !(error is CancellationError) else { return }
            if week == nil {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    /// Picker bindings must update synchronously before starting a network request.
    @discardableResult
    func setKind(_ newKind: TimetableKind) -> Bool {
        guard newKind != kind, newKind == .weekly || supportsPermanentTimetable else { return false }
        kind = newKind
        prepareCurrentAnchor()
        return true
    }

    func selectKind(_ newKind: TimetableKind) async {
        guard setKind(newKind) else { return }
        await refresh()
    }

    // MARK: - Navigation

    func goToPreviousWeek() async {
        await move(byWeeks: -1)
    }

    func goToNextWeek() async {
        await move(byWeeks: 1)
    }

    func goToToday() async {
        guard kind == .weekly, !isViewingCurrentWeek else { return }
        weekAnchor = today
        await loadCurrentAnchor()
    }

    func showSiriDay(_ date: Date) async {
        _ = setKind(.weekly)
        weekAnchor = date
        await loadCurrentAnchor()
        selectedDayID = days.first { $0.date.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }?.id
    }

    func select(dayID: String) {
        selectedDayID = dayID
    }

    // MARK: - Private

    private func move(byWeeks count: Int) async {
        guard kind == .weekly else { return }
        weekAnchor = TimetableDates.addingWeeks(count, to: weekAnchor)
        await loadCurrentAnchor()
    }

    /// Loads the week for the current anchor, resetting selection so it lands on today / the first day.
    private func loadCurrentAnchor() async {
        prepareCurrentAnchor()
        await refresh()
    }

    private func prepareCurrentAnchor() {
        activeRequestID = UUID()
        isLoading = false
        isRefreshing = false
        errorMessage = nil
        selectedDayID = nil
        if let cached = repository.loadCachedTimetable(weekContaining: weekAnchor, kind: kind) {
            apply(cached, preserveSelection: false)
        } else {
            week = nil
        }
    }

    private func apply(_ loaded: TimetableWeek, preserveSelection: Bool) {
        week = loaded

        if preserveSelection,
           let selectedDayID,
           loaded.days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        if let todayDay = loaded.days.first(where: { $0.isToday }) {
            selectedDayID = todayDay.id
        } else {
            selectedDayID = (loaded.days.first(where: { $0.dayType.isSchoolDay }) ?? loaded.days.first)?.id
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
