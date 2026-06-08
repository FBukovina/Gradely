import Foundation
import Testing
@testable import Gradely

@MainActor
struct NextLessonWidgetStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func savesAndLoadsSnapshot() throws {
        let fixture = try makeStore()
        let snapshot = NextLessonWidgetSnapshot(
            cachedAt: date(year: 2026, month: 2, day: 2, hour: 7),
            lessons: [lesson(id: "math", day: 2)]
        )

        try fixture.store.save(snapshot: snapshot)
        let loaded = try fixture.store.loadSnapshot()

        #expect(loaded == snapshot)
        try fixture.cleanup()
    }

    @Test func updateLessonsReplacesOnlyMatchingWeek() throws {
        let fixture = try makeStore()
        let weekStart = date(year: 2026, month: 2, day: 2)
        let nextWeekStart = date(year: 2026, month: 2, day: 9)
        let oldThisWeek = lesson(id: "old-math", day: 2)
        let oldNextWeek = lesson(id: "next-week-math", day: 9)
        let newThisWeek = lesson(id: "new-czech", day: 3)

        try fixture.store.save(
            snapshot: NextLessonWidgetSnapshot(
                cachedAt: date(year: 2026, month: 2, day: 2, hour: 7),
                lessons: [oldThisWeek, oldNextWeek]
            )
        )

        try fixture.store.updateLessons(
            [newThisWeek],
            forWeekStarting: weekStart,
            cachedAt: date(year: 2026, month: 2, day: 2, hour: 8)
        )

        let loaded = try #require(try fixture.store.loadSnapshot())
        #expect(loaded.lessons.map(\.id).sorted() == ["new-czech", "next-week-math"])
        #expect(loaded.lessons.allSatisfy { $0.dayStart < nextWeekStart || $0.id == "next-week-math" })
        try fixture.cleanup()
    }

    @Test func clearRemovesSnapshot() throws {
        let fixture = try makeStore()
        try fixture.store.save(
            snapshot: NextLessonWidgetSnapshot(
                cachedAt: date(year: 2026, month: 2, day: 2, hour: 7),
                lessons: [lesson(id: "math", day: 2)]
            )
        )

        try fixture.store.clear()

        let loaded = try fixture.store.loadSnapshot()
        #expect(loaded == nil)
        try fixture.cleanup()
    }

    private func makeStore() throws -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NextLessonWidgetStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "snapshot.json")
        let store = NextLessonWidgetStore(fileURL: fileURL)
        return StoreFixture(store: store, directory: directory)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func lesson(id: String, day: Int) -> NextLessonWidgetLesson {
        let dayStart = date(year: 2026, month: 2, day: day)
        let startDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart)!
        let endDate = calendar.date(bySettingHour: 8, minute: 45, second: 0, of: dayStart)!

        return NextLessonWidgetLesson(
            id: id,
            dayStart: dayStart,
            startDate: startDate,
            endDate: endDate,
            subjectName: id,
            subjectAbbrev: id.prefix(1).uppercased(),
            timeRange: "8:00-8:45",
            room: "12",
            teacher: "Teacher",
            changeKind: .none
        )
    }

    private struct StoreFixture {
        let store: NextLessonWidgetStore
        let directory: URL

        func cleanup() throws {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }
}
