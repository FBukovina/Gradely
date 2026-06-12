import Foundation
import Testing
@testable import GradelyWatchShared

struct GradelyWatchSharedTests {
    @Test func payloadRoundTripsThroughEnvelope() throws {
        let auth = GradelyWatchAuth(
            baseURL: URL(string: "https://demo.gradely.app")!,
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_800)
        )
        let lesson = GradelyWatchTimetableLesson(
            id: "lesson-1",
            dayStart: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_200),
            endDate: Date(timeIntervalSince1970: 1_500),
            subjectName: "Mathematics",
            subjectAbbrev: "M",
            timeRange: "08:00-08:45",
            room: "12",
            teacher: "Teacher",
            changeKind: .none
        )
        let timetable = GradelyWatchTimetable(
            weekStart: Date(timeIntervalSince1970: 900),
            cachedAt: Date(timeIntervalSince1970: 1_100),
            days: [
                GradelyWatchTimetableDay(
                    id: "day-1",
                    date: Date(timeIntervalSince1970: 1_000),
                    dayStart: Date(timeIntervalSince1970: 1_000),
                    weekdayTitle: "Mon",
                    detailTitle: nil,
                    isToday: true,
                    isSchoolDay: true,
                    lessons: [lesson]
                )
            ]
        )
        let payload = GradelyWatchSyncPayload(
            generatedAt: Date(timeIntervalSince1970: 1_100),
            isSignedIn: true,
            auth: auth,
            user: GradelyWatchUser(fullName: "Student", schoolName: "School", classAbbrev: "1.A"),
            timetable: timetable
        )

        let envelope = try GradelyWatchSyncCodec.envelope(for: payload)
        let decoded = try #require(try GradelyWatchSyncCodec.payload(from: envelope))

        #expect(decoded == payload)
        #expect(envelope[GradelyWatchMessageKey.messageType] as? String == GradelyWatchMessageType.syncPayload)
        #expect(envelope[GradelyWatchMessageKey.schemaVersion] as? Int == GradelyWatchSyncPayload.currentSchemaVersion)
    }

    @Test func signedOutPayloadClearsPrivateState() {
        let payload = GradelyWatchSyncPayload.signedOut(generatedAt: Date(timeIntervalSince1970: 10))

        #expect(payload.schemaVersion == GradelyWatchSyncPayload.currentSchemaVersion)
        #expect(!payload.isSignedIn)
        #expect(payload.auth == nil)
        #expect(payload.user == nil)
        #expect(payload.timetable == nil)
    }

    @Test func selectsCurrentThenUpcomingLesson() {
        let dayStart = Date(timeIntervalSince1970: 1_000)
        let current = GradelyWatchTimetableLesson(
            id: "current",
            dayStart: dayStart,
            startDate: Date(timeIntervalSince1970: 1_100),
            endDate: Date(timeIntervalSince1970: 1_300),
            subjectName: "Math",
            subjectAbbrev: "M",
            timeRange: nil,
            room: nil,
            teacher: nil,
            changeKind: .none
        )
        let upcoming = GradelyWatchTimetableLesson(
            id: "upcoming",
            dayStart: dayStart,
            startDate: Date(timeIntervalSince1970: 1_400),
            endDate: Date(timeIntervalSince1970: 1_600),
            subjectName: "Physics",
            subjectAbbrev: "P",
            timeRange: nil,
            room: nil,
            teacher: nil,
            changeKind: .none
        )
        let timetable = GradelyWatchTimetable(
            weekStart: dayStart,
            cachedAt: Date(timeIntervalSince1970: 1_000),
            days: [
                GradelyWatchTimetableDay(
                    id: "today",
                    date: dayStart,
                    dayStart: dayStart,
                    weekdayTitle: "Mon",
                    detailTitle: nil,
                    isToday: true,
                    isSchoolDay: true,
                    lessons: [upcoming, current]
                )
            ]
        )

        #expect(GradelyWatchSyncCodec.selectLesson(from: timetable, now: Date(timeIntervalSince1970: 1_200)) == .lesson(current, timing: .current))
        #expect(GradelyWatchSyncCodec.selectLesson(from: timetable, now: Date(timeIntervalSince1970: 1_350)) == .lesson(upcoming, timing: .upcoming))
    }

    @Test func mondayIsWeekAnchorForApiDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let thursday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 6, day: 11, hour: 12))!

        #expect(GradelyWatchTimetableDates.apiDateString(GradelyWatchTimetableDates.monday(of: thursday)) == "2026-06-08")
    }
}
