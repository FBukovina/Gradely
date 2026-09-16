import Foundation
import Testing
@testable import Gradely

@MainActor
struct TodaySnapshotTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    // MARK: Greeting

    @Test func greetingNameStripsTheClassReportedBySchool() {
        var snapshot = TodaySnapshot.empty
        snapshot.user = user(fullName: "Bukovina Filip, T2.C", classAbbrev: "T2.C")

        #expect(snapshot.greetingName == "Bukovina Filip")
    }

    @Test func greetingNameStripsClassLikeSuffixWithoutClassMetadata() {
        #expect(TodaySnapshot.nameWithoutClass("Novák Jan, 3.A", classAbbrev: nil) == "Novák Jan")
        #expect(TodaySnapshot.nameWithoutClass("Bukovina Filip, T2.C", classAbbrev: nil) == "Bukovina Filip")
        #expect(TodaySnapshot.nameWithoutClass("Alex Novak", classAbbrev: nil) == "Alex Novak")
        // Suffixes that do not look like a class are kept.
        #expect(TodaySnapshot.nameWithoutClass("Smith, Jr.", classAbbrev: nil) == "Smith, Jr.")
        #expect(TodaySnapshot.nameWithoutClass("Novák Jan, ředitel školy", classAbbrev: nil) == "Novák Jan, ředitel školy")
    }

    @Test func greetingNameFallsBackToLinkedAccount() {
        var snapshot = TodaySnapshot.empty
        var account = PreviewData.linkedSchoolAccount
        account.displayName = "Bukovina Filip, T2.C"
        snapshot.activeAccount = account

        #expect(snapshot.greetingName == "Bukovina Filip")
        #expect(TodaySnapshot.empty.greetingName == nil)
    }

    // MARK: Account chip

    @Test func accountChipPrefersClassForASingleAccount() {
        var snapshot = TodaySnapshot.empty
        snapshot.user = user(fullName: "Bukovina Filip, T2.C", classAbbrev: "T2.C")
        snapshot.activeAccount = PreviewData.linkedSchoolAccount
        snapshot.linkedSchoolAccounts = [PreviewData.linkedSchoolAccount]

        #expect(snapshot.accountChipLabel == "T2.C")
    }

    @Test func accountChipIdentifiesTheStudentWhenSeveralAccountsAreLinked() {
        var snapshot = TodaySnapshot.empty
        snapshot.user = user(fullName: "Bukovina Filip, T2.C", classAbbrev: "T2.C")
        var first = PreviewData.linkedSchoolAccount
        first.displayName = "Bukovina Filip, T2.C"
        var second = PreviewData.linkedSchoolAccount
        second.id = "sibling"
        second.displayName = "Bukovina Anna, 1.B"
        snapshot.activeAccount = first
        snapshot.linkedSchoolAccounts = [first, second]

        #expect(snapshot.accountChipLabel == "Bukovina Filip")
    }

    // MARK: Recent marks

    @Test func recentMarksAreNewestFirstUniqueAndLimited() {
        var snapshot = TodaySnapshot.empty
        snapshot.subjects = PreviewData.subjects

        let marks = snapshot.recentMarks(limit: 3)

        #expect(marks.count == 3)
        #expect(marks.first?.id == "mark-math-math-1")
        #expect(Set(marks.map(\.id)).count == marks.count)
        let dates = marks.map { $0.detectedAt ?? .distantPast }
        #expect(dates == dates.sorted(by: >))
        #expect(snapshot.recentMarks(limit: 1).count == 1)
        #expect(snapshot.recentMarks(limit: 0).isEmpty)
    }

    @Test func recentMarkCarriesBandCaptionAndNewFlag() {
        var snapshot = TodaySnapshot.empty
        snapshot.subjects = PreviewData.subjects

        let newest = snapshot.recentMarks(limit: 1).first

        #expect(newest?.markText == "1-")
        #expect(newest?.band == .excellent)
        #expect(newest?.caption == "Písemná práce")
        #expect(newest?.subjectTitle == "Matematika")
        #expect(newest?.subjectName == "M")
        #expect(newest?.isNew == true)
    }

    // MARK: Lessons

    @Test func orderedLessonsFollowBeginTimesNotStringOrder() {
        let lessons = [
            lesson(id: "late", begin: "10:00", end: "10:45", hourID: 3),
            lesson(id: "first", begin: "8:00", end: "8:45", hourID: 1),
            lesson(id: "second", begin: "8:55", end: "9:40", hourID: 2),
            lesson(id: "untimed", begin: "", end: "", hourID: 0),
        ]

        #expect(TodaySnapshot.orderedLessons(lessons).map(\.id) == ["first", "second", "late", "untimed"])
    }

    @Test func lessonCountsSeparateCancelledPeriods() {
        var snapshot = TodaySnapshot.empty
        snapshot.todayLessons = [
            lesson(id: "a", begin: "8:00", end: "8:45", hourID: 1),
            lesson(id: "b", begin: "8:55", end: "9:40", hourID: 2, changeKind: .canceled),
            lesson(id: "c", begin: "9:50", end: "10:35", hourID: 3),
        ]

        #expect(snapshot.activeLessonCount == 2)
        #expect(snapshot.cancelledLessonCount == 1)
    }

    @Test func lessonProgressIsClampedToTheRunningLesson() throws {
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let math = lesson(id: "math", begin: "8:00", end: "8:45", hourID: 1)

        func now(_ hour: Int, _ minute: Int, _ second: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: hour, minute: minute, second: second)))
        }

        #expect(TodaySnapshot.lessonProgress(for: math, on: day, now: try now(8, 0), calendar: calendar) == 0)
        let halfway = try #require(TodaySnapshot.lessonProgress(for: math, on: day, now: try now(8, 22, 30), calendar: calendar))
        #expect(abs(halfway - 0.5) < 0.0001)
        #expect(TodaySnapshot.lessonProgress(for: math, on: day, now: try now(8, 45), calendar: calendar) == nil)
        #expect(TodaySnapshot.lessonProgress(for: math, on: day, now: try now(7, 59), calendar: calendar) == nil)

        let untimed = lesson(id: "untimed", begin: "", end: "", hourID: 0)
        #expect(TodaySnapshot.lessonProgress(for: untimed, on: day, now: try now(8, 10), calendar: calendar) == nil)
    }

    // MARK: Fixtures

    private func user(fullName: String, classAbbrev: String?) -> UserResponse {
        UserResponse(
            userUID: "student-1",
            fullName: fullName,
            userClass: classAbbrev.map { ClassInfo(id: "class-1", abbrev: $0, name: $0) },
            schoolName: "Demo Gymnázium",
            userType: "student",
            userTypeText: "Student",
            studyYear: nil
        )
    }

    private func lesson(id: String, begin: String, end: String, hourID: Int,
                        changeKind: LessonChangeKind = .none) -> ScheduledLesson {
        ScheduledLesson(
            id: id,
            hour: TimetableHour(id: hourID, caption: "\(hourID)", beginTime: begin, endTime: end),
            subjectName: "Subject \(id)",
            subjectAbbrev: id.prefix(3).uppercased(),
            teacherName: nil,
            teacherAbbrev: nil,
            roomAbbrev: nil,
            roomName: nil,
            groups: [],
            theme: nil,
            hasHomework: false,
            change: changeKind == .none ? nil : TimetableChange(changeType: "Canceled"),
            changeKind: changeKind
        )
    }
}
