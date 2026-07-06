import Foundation
import Testing
@testable import Gradely

struct TimetableTodaySummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func selectsCurrentAndNextLesson() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 8, minute: 20)))
        let day = ScheduledDay(
            id: "today",
            date: date,
            dayOfWeek: 2,
            dayType: .workDay,
            dayDescription: "",
            lessons: [
                lesson(id: "math", subject: "Math", begin: "8:00", end: "8:45", hourID: 1),
                lesson(id: "czech", subject: "Czech", begin: "8:55", end: "9:40", hourID: 2),
            ],
            isToday: true
        )

        let summary = try #require(TimetableTodaySummaryBuilder.make(for: day, now: now, calendar: calendar))

        #expect(summary.state == .current)
        #expect(summary.currentLesson?.id == "math")
        #expect(summary.nextLesson?.id == "czech")
        #expect(summary.minutesRemainingInCurrent == 25)
    }

    @Test func selectsUpcomingLessonBeforeSchool() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 7, minute: 50)))
        let day = ScheduledDay(
            id: "today",
            date: date,
            dayOfWeek: 2,
            dayType: .workDay,
            dayDescription: "",
            lessons: [
                lesson(id: "math", subject: "Math", begin: "8:00", end: "8:45", hourID: 1),
            ],
            isToday: true
        )

        let summary = try #require(TimetableTodaySummaryBuilder.make(for: day, now: now, calendar: calendar))

        #expect(summary.state == .beforeSchool)
        #expect(summary.nextLesson?.id == "math")
        #expect(summary.minutesUntilNext == 10)
    }

    @Test func summarizesChangedLessons() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let day = ScheduledDay(
            id: "today",
            date: date,
            dayOfWeek: 2,
            dayType: .workDay,
            dayDescription: "",
            lessons: [
                lesson(id: "canceled", subject: "Physics", begin: "8:00", end: "8:45", hourID: 1, changeKind: .canceled),
                lesson(id: "room", subject: "Math", begin: "8:55", end: "9:40", hourID: 2, changeKind: .roomChanged),
            ],
            isToday: true
        )

        let summary = try #require(TimetableTodaySummaryBuilder.make(for: day, now: now, calendar: calendar))

        #expect(summary.state == .afterSchool)
        #expect(summary.changedLessons.map(\.id) == ["canceled", "room"])
    }

    private func lesson(
        id: String,
        subject: String,
        begin: String,
        end: String,
        hourID: Int,
        changeKind: LessonChangeKind = .none
    ) -> ScheduledLesson {
        ScheduledLesson(
            id: id,
            hour: TimetableHour(id: hourID, caption: "\(hourID)", beginTime: begin, endTime: end),
            subjectName: subject,
            subjectAbbrev: String(subject.prefix(3)).uppercased(),
            teacherName: nil,
            teacherAbbrev: nil,
            roomAbbrev: nil,
            roomName: nil,
            groups: [],
            theme: nil,
            hasHomework: false,
            change: changeKind == .none ? nil : TimetableChange(changeType: changeKind.apiFixtureValue),
            changeKind: changeKind
        )
    }
}

private extension LessonChangeKind {
    var apiFixtureValue: String {
        switch self {
        case .none: ""
        case .canceled: "Canceled"
        case .substitution: "Substitution"
        case .roomChanged: "RoomChanged"
        case .added: "Added"
        }
    }
}
