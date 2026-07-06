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

    /// The id of the day currently selected in the week strip.
    private(set) var selectedDayID: String?
    /// Any date inside the week currently on screen.
    private(set) var weekAnchor: Date

    private let repository: SchoolRepository
    private let today: Date
    private var hasLoaded = false

    init(repository: SchoolRepository, today: Date = Date()) {
        self.repository = repository
        self.today = today
        weekAnchor = today
    }

    // MARK: - Derived state

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
        TimetableTodaySummaryBuilder.make(for: selectedDay)
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

        if let cached = repository.loadCachedTimetable(weekContaining: weekAnchor) {
            apply(cached, preserveSelection: false)
        }

        await refresh()

        if user == nil {
            user = await repository.loadUser()
        }
    }

    func refresh() async {
        errorMessage = nil
        if week == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let loaded = try await repository.loadTimetable(weekContaining: weekAnchor)
            apply(loaded, preserveSelection: true)
        } catch {
            if week == nil {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    // MARK: - Navigation

    func goToPreviousWeek() async {
        await move(byWeeks: -1)
    }

    func goToNextWeek() async {
        await move(byWeeks: 1)
    }

    func goToToday() async {
        guard !isViewingCurrentWeek else { return }
        weekAnchor = today
        await loadCurrentAnchor()
    }

    func select(dayID: String) {
        selectedDayID = dayID
    }

    // MARK: - Private

    private func move(byWeeks count: Int) async {
        weekAnchor = TimetableDates.addingWeeks(count, to: weekAnchor)
        await loadCurrentAnchor()
    }

    /// Loads the week for the current anchor, resetting selection so it lands on today / the first day.
    private func loadCurrentAnchor() async {
        selectedDayID = nil
        if let cached = repository.loadCachedTimetable(weekContaining: weekAnchor) {
            apply(cached, preserveSelection: false)
        } else {
            week = nil
        }
        await refresh()
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
