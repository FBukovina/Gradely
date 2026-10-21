import Foundation
import Observation

/// Where a timetable comes from: your school account, or a friend's.
struct TimetableSource {
    var supportsPermanentTimetable: @MainActor () -> Bool
    /// Your school's scope; nil for a friend, which turns off Planner links.
    var schoolScope: @MainActor () -> SchoolDataScope?
    var cachedWeek: @MainActor (Date, TimetableKind) -> TimetableWeek?
    var loadWeek: @MainActor (Date, TimetableKind) async throws -> TimetableWeek
    var loadUser: @MainActor () async -> UserResponse?

    static func school(_ repository: SchoolRepository) -> TimetableSource {
        TimetableSource(
            supportsPermanentTimetable: { repository.supportsPermanentTimetable },
            schoolScope: { (try? repository.currentStoredSession()).map(SchoolDataScope.init(session:)) },
            cachedWeek: { date, kind in repository.loadCachedTimetable(weekContaining: date, kind: kind) },
            loadWeek: { date, kind in try await repository.loadTimetable(weekContaining: date, kind: kind) },
            loadUser: { await repository.loadUser() }
        )
    }
}

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

    private let source: TimetableSource
    private let today: Date
    private var hasLoaded = false
    private var activeRequestID = UUID()

    convenience init(repository: SchoolRepository, today: Date = Date()) {
        self.init(source: .school(repository), today: today)
    }

    init(source: TimetableSource, today: Date = Date()) {
        self.source = source
        self.today = today
        weekAnchor = today
    }

    // MARK: - Derived state

    var supportsPermanentTimetable: Bool { source.supportsPermanentTimetable() }

    var schoolScope: SchoolDataScope? { source.schoolScope() }

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

    /// Whether the displayed week is the one containing today (used to gate the "Today" button).
    var isViewingCurrentWeek: Bool {
        TimetableDates.apiDateString(TimetableDates.monday(of: weekAnchor))
            == TimetableDates.apiDateString(TimetableDates.monday(of: today))
    }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = source.cachedWeek(weekAnchor, kind) {
            apply(cached, preserveSelection: false)
        }

        await refresh()

        if user == nil {
            user = await source.loadUser()
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
            let loaded = try await source.loadWeek(requestedAnchor, requestedKind)
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
        if let cached = source.cachedWeek(weekAnchor, kind) {
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
