import Foundation
import Testing
@testable import Gradely

@MainActor
struct NextLessonSelectorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func noSnapshotReturnsNoSnapshotState() {
        let selection = NextLessonSelector.select(snapshot: nil, now: date(hour: 8))

        #expect(selection == .noSnapshot)
    }

    @Test func beforeSchoolShowsFirstLesson() {
        let firstLesson = lesson(id: "math", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45)
        let secondLesson = lesson(id: "czech", startHour: 8, startMinute: 55, endHour: 9, endMinute: 40)
        let snapshot = snapshot(lessons: [secondLesson, firstLesson])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 7, minute: 30))

        expectLesson(selection, id: "math", timing: .upcoming)
    }

    @Test func duringSchoolShowsCurrentLesson() {
        let firstLesson = lesson(id: "math", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45)
        let secondLesson = lesson(id: "czech", startHour: 8, startMinute: 55, endHour: 9, endMinute: 40)
        let snapshot = snapshot(lessons: [firstLesson, secondLesson])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 8, minute: 20))

        expectLesson(selection, id: "math", timing: .current)
    }

    @Test func betweenLessonsShowsNextLesson() {
        let firstLesson = lesson(id: "math", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45)
        let secondLesson = lesson(id: "czech", startHour: 8, startMinute: 55, endHour: 9, endMinute: 40)
        let snapshot = snapshot(lessons: [firstLesson, secondLesson])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 8, minute: 50))

        expectLesson(selection, id: "czech", timing: .upcoming)
    }

    @Test func afterSchoolAdvancesToNextAvailableSchoolDay() {
        let todayLesson = lesson(id: "math", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let tomorrowLesson = lesson(
            id: "biology",
            dayStart: tomorrow,
            startHour: 8,
            startMinute: 0,
            endHour: 8,
            endMinute: 45
        )
        let snapshot = snapshot(lessons: [todayLesson, tomorrowLesson])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 16))

        expectLesson(selection, id: "biology", timing: .upcoming)
    }

    @Test func canceledAndChangedLessonsRemainSelectable() {
        let canceled = lesson(
            id: "canceled",
            startHour: 8,
            startMinute: 0,
            endHour: 8,
            endMinute: 45,
            changeKind: .canceled
        )
        let snapshot = snapshot(lessons: [canceled])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 7, minute: 30))

        expectLesson(selection, id: "canceled", timing: .upcoming, changeKind: .canceled)
    }

    @Test func emptySnapshotReturnsNoLessons() {
        let snapshot = snapshot(lessons: [])

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 8))

        #expect(selection == .noLessons)
    }

    @Test func staleSnapshotReturnsStaleState() {
        let oldCacheDate = date(hour: 8).addingTimeInterval(-(8 * 24 * 60 * 60))
        let snapshot = NextLessonWidgetSnapshot(
            cachedAt: oldCacheDate,
            lessons: [lesson(id: "math", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45)]
        )

        let selection = NextLessonSelector.select(snapshot: snapshot, now: date(hour: 8))

        #expect(selection == .stale)
    }

    private var dayStart: Date {
        calendar.date(from: DateComponents(year: 2026, month: 2, day: 2))!
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: hour, minute: minute))!
    }

    private func snapshot(lessons: [NextLessonWidgetLesson]) -> NextLessonWidgetSnapshot {
        NextLessonWidgetSnapshot(cachedAt: date(hour: 7), lessons: lessons)
    }

    private func lesson(
        id: String,
        dayStart: Date? = nil,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        changeKind: NextLessonWidgetChangeKind = .none
    ) -> NextLessonWidgetLesson {
        let dayStart = dayStart ?? self.dayStart
        let startDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart)!
        let endDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart)!

        return NextLessonWidgetLesson(
            id: id,
            dayStart: dayStart,
            startDate: startDate,
            endDate: endDate,
            subjectName: id,
            subjectAbbrev: id.prefix(1).uppercased(),
            timeRange: "\(startHour):\(startMinute)-\(endHour):\(endMinute)",
            room: "12",
            teacher: "Teacher",
            changeKind: changeKind
        )
    }

    private func expectLesson(
        _ selection: NextLessonWidgetSelection,
        id: String,
        timing: NextLessonWidgetTiming,
        changeKind: NextLessonWidgetChangeKind = .none
    ) {
        guard case .lesson(let lesson, let selectedTiming) = selection else {
            Issue.record("Expected lesson selection, got \(selection)")
            return
        }

        #expect(lesson.id == id)
        #expect(selectedTiming == timing)
        #expect(lesson.changeKind == changeKind)
    }
}
