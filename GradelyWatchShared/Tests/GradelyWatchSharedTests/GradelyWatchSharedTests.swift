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
            timetable: timetable,
            supportTier: .plus
        )

        let envelope = try GradelyWatchSyncCodec.envelope(for: payload)
        let decoded = try #require(try GradelyWatchSyncCodec.payload(from: envelope))

        #expect(decoded == payload)
        #expect(decoded.supportTier == .plus)
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
        #expect(payload.supportTier == .none)
    }

    @Test func legacySchema2PayloadDecodesMissingSupportTierAsNone() throws {
        struct LegacyPayload: Encodable {
            var schemaVersion = 2
            var generatedAt: Date
            var isSignedIn: Bool
            var auth: GradelyWatchAuth?
            var user: GradelyWatchUser?
            var timetable: GradelyWatchTimetable?
        }

        let encoded = try GradelyWatchSyncCodec.encoder.encode(
            LegacyPayload(
                generatedAt: Date(timeIntervalSince1970: 20),
                isSignedIn: false,
                auth: nil,
                user: nil,
                timetable: nil
            )
        )
        let decoded = try GradelyWatchSyncCodec.decoder.decode(GradelyWatchSyncPayload.self, from: encoded)

        #expect(decoded.schemaVersion == 2)
        #expect(decoded.supportTier == .none)
        #expect(!decoded.isSignedIn)
    }

    @Test func remainingLessonsTodaySkipCurrentAndCanceled() {
        let dayStart = Date(timeIntervalSince1970: 1_000)
        let current = lesson(
            id: "current",
            dayStart: dayStart,
            start: 1_100,
            end: 1_300,
            changeKind: .none
        )
        let upcoming = lesson(
            id: "upcoming",
            dayStart: dayStart,
            start: 1_400,
            end: 1_600,
            changeKind: .none
        )
        let canceled = lesson(
            id: "canceled",
            dayStart: dayStart,
            start: 1_700,
            end: 1_900,
            changeKind: .canceled
        )
        let timetable = dayTimetable(dayStart: dayStart, lessons: [current, upcoming, canceled])

        #expect(
            GradelyWatchSyncCodec.remainingLessonsToday(
                from: timetable,
                now: Date(timeIntervalSince1970: 1_200)
            ).map(\.id) == ["upcoming"]
        )
        #expect(
            GradelyWatchSyncCodec.remainingLessonsToday(
                from: timetable,
                now: Date(timeIntervalSince1970: 2_000)
            ).isEmpty
        )
    }

    @Test func lessonProgressClampsBetweenZeroAndOne() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        #expect(GradelyWatchSyncCodec.progress(from: start, to: end, now: Date(timeIntervalSince1970: 500)) == 0)
        #expect(GradelyWatchSyncCodec.progress(from: start, to: end, now: Date(timeIntervalSince1970: 1_500)) == 0.5)
        #expect(GradelyWatchSyncCodec.progress(from: start, to: end, now: Date(timeIntervalSince1970: 2_500)) == 1)
    }

    @Test func nowPageReportsBreakThenDone() {
        let dayStart = Date(timeIntervalSince1970: 1_000)
        let first = lesson(id: "first", dayStart: dayStart, start: 1_100, end: 1_300, changeKind: .none)
        let second = lesson(id: "second", dayStart: dayStart, start: 1_400, end: 1_600, changeKind: .none)
        let timetable = dayTimetable(dayStart: dayStart, lessons: [first, second])

        #expect(
            GradelyWatchSyncCodec.nowPage(from: timetable, now: Date(timeIntervalSince1970: 1_200))
            == .inLesson(first, progress: 0.5)
        )
        #expect(
            GradelyWatchSyncCodec.nowPage(from: timetable, now: Date(timeIntervalSince1970: 1_350))
            == .betweenLessons(next: second, progress: 0.5, previous: first)
        )
        #expect(
            GradelyWatchSyncCodec.nowPage(from: timetable, now: Date(timeIntervalSince1970: 1_800))
            == .doneForToday
        )
    }

    @Test func aiEnvelopeRoundTrips() throws {
        let request = GradelyWatchAIStreamRequest(
            requestID: "req-1",
            conversationID: nil,
            clientMessageID: "msg-1",
            text: "What is 2+2?"
        )
        let requestEnvelope = try GradelyWatchSyncCodec.envelope(for: request)
        let decodedRequest = try #require(try GradelyWatchSyncCodec.aiRequest(from: requestEnvelope))
        #expect(decodedRequest == request)

        let event = GradelyWatchAIStreamEvent(
            requestID: "req-1",
            conversationID: "chat-1",
            kind: .delta,
            text: "4"
        )
        let eventEnvelope = try GradelyWatchSyncCodec.envelope(for: event)
        let decodedEvent = try #require(try GradelyWatchSyncCodec.aiEvent(from: eventEnvelope))
        #expect(decodedEvent == event)
    }

    private func lesson(
        id: String,
        dayStart: Date,
        start: TimeInterval,
        end: TimeInterval,
        changeKind: GradelyWatchLessonChangeKind
    ) -> GradelyWatchTimetableLesson {
        GradelyWatchTimetableLesson(
            id: id,
            dayStart: dayStart,
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: end),
            subjectName: id,
            subjectAbbrev: id,
            timeRange: nil,
            room: nil,
            teacher: nil,
            changeKind: changeKind
        )
    }

    private func dayTimetable(
        dayStart: Date,
        lessons: [GradelyWatchTimetableLesson]
    ) -> GradelyWatchTimetable {
        GradelyWatchTimetable(
            weekStart: dayStart,
            cachedAt: dayStart,
            days: [
                GradelyWatchTimetableDay(
                    id: "today",
                    date: dayStart,
                    dayStart: dayStart,
                    weekdayTitle: "Mon",
                    detailTitle: nil,
                    isToday: true,
                    isSchoolDay: true,
                    lessons: lessons
                )
            ]
        )
    }

    @Test func eduPageCredentialsRoundTripForDirectWatchRefresh() throws {
        let auth = GradelyWatchAuth(
            baseURL: URL(string: "https://school.edupage.org")!,
            accessToken: "session",
            refreshToken: "",
            tokenType: "Cookie",
            expiresAt: Date(timeIntervalSince1970: 2_000),
            provider: .eduPage,
            username: "student",
            password: "secret",
            sessionID: "session",
            selectedStudentID: "Student1",
            gsecHash: "gsec"
        )

        let encoded = try GradelyWatchSyncCodec.encoder.encode(auth)
        let decoded = try GradelyWatchSyncCodec.decoder.decode(GradelyWatchAuth.self, from: encoded)
        #expect(decoded == auth)
        #expect(decoded.resolvedProvider == .eduPage)
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
