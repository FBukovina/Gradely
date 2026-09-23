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

    @Test func omitsEndedChangesAfterSchool() throws {
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
        #expect(summary.changedLessons.isEmpty)
        #expect(!summary.hasChanges)
    }

    @Test func keepsCurrentAndUpcomingChangesIncludingCanceledLessons() throws {
        let day = try scheduledDay(lessons: [
            lesson(id: "ended", subject: "Physics", begin: "8:00", end: "8:45", hourID: 1, changeKind: .canceled),
            lesson(id: "current", subject: "Math", begin: "8:55", end: "9:40", hourID: 2, changeKind: .roomChanged),
            lesson(id: "future", subject: "PE", begin: "9:50", end: "10:35", hourID: 3, changeKind: .canceled),
        ])

        let summary = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 9), calendar: calendar
        ))

        #expect(summary.state == .current)
        #expect(summary.changedLessons.map(\.id) == ["current", "future"])
        #expect(summary.nextLesson == nil)
    }

    @Test func expiresChangeExactlyAtLessonEnd() throws {
        let day = try scheduledDay(lessons: [
            lesson(id: "room", subject: "Math", begin: "8:00", end: "8:45", hourID: 1, changeKind: .roomChanged),
        ])
        let beforeEnd = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 8, minute: 44), calendar: calendar
        ))
        let atEnd = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 8, minute: 45), calendar: calendar
        ))

        #expect(beforeEnd.hasChanges)
        #expect(atEnd.state == .afterSchool)
        #expect(!atEnd.hasChanges)
    }

    @Test func deduplicatesRepeatedAtomsWithoutMergingConsecutivePELessons() throws {
        let day = try scheduledDay(lessons: [
            lesson(id: "pe-2", subject: "PE", begin: "8:55", end: "9:40", hourID: 2, changeKind: .substitution),
            lesson(id: "pe-1-copy", subject: "PE", begin: "8:00", end: "8:45", hourID: 1, changeKind: .substitution),
            lesson(id: "pe-1", subject: "PE", begin: "8:00", end: "8:45", hourID: 1, changeKind: .substitution),
        ])
        let summary = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 7), calendar: calendar
        ))

        #expect(summary.changedLessons.map(\.id) == ["pe-1", "pe-2"])
    }

    @Test func preservesDifferentGroupsInSamePeriod() throws {
        var firstGroup = lesson(id: "group-a", subject: "PE", begin: "8:00", end: "8:45", hourID: 1, changeKind: .substitution)
        firstGroup.subjectID = "pe"
        firstGroup.groupIDs = ["group-a"]
        var secondGroup = lesson(id: "group-b", subject: "PE", begin: "8:00", end: "8:45", hourID: 1, changeKind: .substitution)
        secondGroup.subjectID = "pe"
        secondGroup.groupIDs = ["group-b"]
        let day = try scheduledDay(lessons: [firstGroup, secondGroup])
        let summary = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 7), calendar: calendar
        ))

        #expect(summary.changedLessons.map(\.id) == ["group-a", "group-b"])
    }

    @Test func doesNotPresentUntimedOrInvalidChangesAsUpcoming() throws {
        let day = try scheduledDay(lessons: [
            lesson(id: "untimed", subject: "PE", begin: "", end: "", hourID: 1, changeKind: .substitution),
            lesson(id: "reversed", subject: "Math", begin: "9:40", end: "8:55", hourID: 2, changeKind: .roomChanged),
            lesson(id: "zero-length", subject: "Czech", begin: "8:00", end: "8:00", hourID: 3, changeKind: .canceled),
        ])
        let summary = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 7), calendar: calendar
        ))

        #expect(summary.changedLessons.isEmpty)
        #expect(summary.currentLesson == nil)
        #expect(summary.nextLesson == nil)
    }

    @Test func includesAdjacentNextLessonAtExactBoundary() throws {
        let day = try scheduledDay(lessons: [
            lesson(id: "pe-1", subject: "PE", begin: "8:00", end: "8:45", hourID: 1),
            lesson(id: "pe-2", subject: "PE", begin: "8:45", end: "9:30", hourID: 2),
        ])
        let summary = try #require(TimetableTodaySummaryBuilder.make(
            for: day, now: time(hour: 8, minute: 20), calendar: calendar
        ))

        #expect(summary.currentLesson?.id == "pe-1")
        #expect(summary.nextLesson?.id == "pe-2")
    }

    private func scheduledDay(lessons: [ScheduledLesson]) throws -> ScheduledDay {
        ScheduledDay(
            id: "today",
            date: try time(hour: 0),
            dayOfWeek: 2,
            dayType: .workDay,
            dayDescription: "",
            lessons: lessons,
            isToday: true
        )
    }

    private func time(hour: Int, minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 30, hour: hour, minute: minute
        )))
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
