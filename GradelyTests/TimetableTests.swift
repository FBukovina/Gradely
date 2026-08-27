import Foundation
import Testing
@testable import Gradely

struct TimetableTests {
    /// Mirrors the official `timetable/actual` example: entity ids carry spaces, atoms arrive out of
    /// hour order, one lesson is cancelled, and one day is a holiday with no atoms.
    private let fixture = """
    {
      "Hours": [
        { "Id": 1, "Caption": "1", "BeginTime": "8:00", "EndTime": "8:45" },
        { "Id": 2, "Caption": "2", "BeginTime": "8:55", "EndTime": "9:40" }
      ],
      "Days": [
        {
          "Atoms": [
            { "HourId": 2, "GroupIds": ["0C"], "SubjectId": " 6", "TeacherId": "U  12", "RoomId": "0X", "CycleIds": ["1"], "Change": null, "HomeworkIds": ["hw1"], "Theme": "Translace" },
            { "HourId": 1, "GroupIds": [], "SubjectId": "M", "TeacherId": "U  99", "RoomId": "0Y", "CycleIds": [], "Change": { "ChangeType": "Canceled", "Description": "Odpadá", "Hours": "1. hod" }, "HomeworkIds": [], "Theme": null }
          ],
          "DayOfWeek": 1,
          "Date": "2024-09-02T00:00:00+02:00",
          "DayDescription": "",
          "DayType": "WorkDay"
        },
        {
          "Atoms": [],
          "DayOfWeek": 2,
          "Date": "2024-09-03T00:00:00+02:00",
          "DayDescription": "Státní svátek",
          "DayType": "Holiday"
        }
      ],
      "Classes": [ { "Id": "XL", "Abbrev": "X.a", "Name": " X. a" } ],
      "Groups": [ { "ClassId": "XL", "Id": "0C", "Abbrev": "X.a", "Name": " X. a" } ],
      "Subjects": [
        { "Id": " 6", "Abbrev": "B", "Name": "Biologie" },
        { "Id": "M", "Abbrev": "M", "Name": "Matematika" }
      ],
      "Teachers": [
        { "Id": "U  12", "Abbrev": "Ha", "Name": "Hájková" },
        { "Id": "U  99", "Abbrev": "No", "Name": "Novák" }
      ],
      "Rooms": [
        { "Id": "0X", "Abbrev": "B", "Name": "Biologie" },
        { "Id": "0Y", "Abbrev": "12", "Name": "" }
      ],
      "Cycles": [ { "Id": "1", "Abbrev": "L", "Name": "Lichý" } ]
    }
    """

    private func decodeFixture() throws -> TimetableResponse {
        let data = try #require(fixture.data(using: .utf8))
        return try JSONDecoder().decode(TimetableResponse.self, from: data)
    }

    private var pragueCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func decodesTimetableFixture() throws {
        let response = try decodeFixture()

        #expect(response.hours.count == 2)
        #expect(response.days.count == 2)
        #expect(response.subjects.count == 2)
        // Ids keep their spaces verbatim so atom lookups match.
        #expect(response.subjects.contains { $0.id == " 6" })
        #expect(response.teachers.contains { $0.id == "U  12" })
    }

    @Test func mapperResolvesEntitiesAndSortsByHour() throws {
        let response = try decodeFixture()
        let today = pragueCalendar.date(from: DateComponents(year: 2024, month: 9, day: 2, hour: 12))!

        let week = TimetableMapper.makeWeek(from: response, weekStart: today, today: today, calendar: pragueCalendar)

        #expect(week.days.count == 2)
        let monday = week.days[0]
        #expect(monday.lessons.count == 2)

        // Atoms were given out of order (hour 2 then hour 1); sorting restores hour order.
        #expect(monday.lessons[0].hour.id == 1)
        #expect(monday.lessons[1].hour.id == 2)

        // Spaced ids resolve, and display strings are trimmed.
        let biology = monday.lessons[1]
        #expect(biology.subjectName == "Biologie")
        #expect(biology.subjectAbbrev == "B")
        #expect(biology.teacherName == "Hájková")
        #expect(biology.roomAbbrev == "B")
        #expect(biology.theme == "Translace")
        #expect(biology.hasHomework)
        #expect(biology.changeKind == .none)
    }

    @Test func mapperDetectsCancellationAndToday() throws {
        let response = try decodeFixture()
        let today = pragueCalendar.date(from: DateComponents(year: 2024, month: 9, day: 2, hour: 12))!

        let week = TimetableMapper.makeWeek(from: response, weekStart: today, today: today, calendar: pragueCalendar)

        let canceled = week.days[0].lessons[0]
        #expect(canceled.changeKind == .canceled)
        #expect(canceled.isCanceled)
        #expect(week.days[0].isToday)
        #expect(week.days[0].hasChanges)
        #expect(!week.days[1].isToday)
    }

    @Test func mapperHandlesHolidayDay() throws {
        let response = try decodeFixture()
        let today = pragueCalendar.date(from: DateComponents(year: 2024, month: 9, day: 2, hour: 12))!

        let week = TimetableMapper.makeWeek(from: response, weekStart: today, today: today, calendar: pragueCalendar)

        let holiday = week.days[1]
        #expect(holiday.dayType == .holiday)
        #expect(holiday.lessons.isEmpty)
        #expect(holiday.dayDescription == "Státní svátek")
        #expect(!holiday.dayType.isSchoolDay)
    }

    @Test func repositoryLoadsRebasedDemoWeek() async throws {
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache()
        )

        let week = try await repository.loadTimetable(weekContaining: Date())

        #expect(week.days.count == 5)
        let lessons = week.days.flatMap(\.lessons)
        #expect(lessons.contains { $0.isCanceled })
        #expect(lessons.contains { $0.changeKind == .roomChanged })
        // The fixture week is rebased onto the requested week's Monday.
        #expect(week.weekStart == TimetableDates.monday(of: Date()))
    }
}

struct TimetableDateFormattingTests {
    private var pragueCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func weekRangeTitleFollowsLocale() throws {
        let monday = try #require(
            pragueCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 12))
        )

        let english = TimetableDates.weekRangeTitle(weekStart: monday, locale: Locale(identifier: "en_US"))
        #expect(english.localizedCaseInsensitiveContains("Aug"))

        let czech = TimetableDates.weekRangeTitle(weekStart: monday, locale: Locale(identifier: "cs_CZ"))
        #expect(!czech.localizedCaseInsensitiveContains("Aug"))
        #expect(czech.localizedCaseInsensitiveContains("srp") || czech.contains("8"))
    }

    @Test func weekdayAbbreviationFollowsLocale() throws {
        let monday = try #require(
            pragueCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 12))
        )

        let english = TimetableDates.weekdayAbbreviation(monday, locale: Locale(identifier: "en_US"))
        #expect(english.localizedCaseInsensitiveContains("mon"))

        let czech = TimetableDates.weekdayAbbreviation(monday, locale: Locale(identifier: "cs_CZ"))
        #expect(czech.localizedCaseInsensitiveContains("po"))
        #expect(!czech.localizedCaseInsensitiveContains("mon"))
    }
}
