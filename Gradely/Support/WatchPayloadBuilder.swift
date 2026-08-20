import Foundation
#if !os(macOS)
import GradelyWatchShared

enum WatchPayloadBuilder {
    static func auth(from session: StoredSession) -> GradelyWatchAuth {
        let eduPage = session.eduPage
        return GradelyWatchAuth(
            baseURL: session.baseURL,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            tokenType: session.tokenType,
            expiresAt: session.provider == .eduPage ? Date().addingTimeInterval(6 * 60 * 60) : session.expiresAt,
            provider: session.provider == .eduPage ? .eduPage : .bakalari,
            // Bakaláři credentials let the watch re-login on its own token family
            // instead of redeeming the refresh token it shares with the phone.
            username: eduPage?.username ?? session.bakalari?.username,
            password: eduPage?.password ?? session.bakalari?.password,
            sessionID: eduPage?.sessionID,
            selectedStudentID: eduPage?.activeStudent?.id,
            gsecHash: eduPage?.gsecHash
        )
    }

    static func supportTier(from entitlement: SupportEntitlement) -> GradelyWatchSupportTier {
        switch entitlement.tier {
        case .none: .none
        case .standard: .standard
        case .plus: .plus
        }
    }

    static func user(from user: UserResponse) -> GradelyWatchUser {
        GradelyWatchUser(
            fullName: user.fullName,
            schoolName: user.displaySchoolName,
            classAbbrev: user.userClass?.abbrev
        )
    }

    static func timetable(
        from week: TimetableWeek,
        cachedAt: Date,
        calendar: Calendar = .current
    ) -> GradelyWatchTimetable {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = .current
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")

        let detailFormatter = DateFormatter()
        detailFormatter.calendar = calendar
        detailFormatter.locale = .current
        detailFormatter.setLocalizedDateFormatFromTemplate("d MMM")

        return GradelyWatchTimetable(
            weekStart: week.weekStart,
            cachedAt: cachedAt,
            days: week.days.map { day in
                let dayStart = startOfDay(for: day, in: week, calendar: calendar)
                return GradelyWatchTimetableDay(
                    id: day.id,
                    date: day.date,
                    dayStart: dayStart,
                    weekdayTitle: day.date.map { weekdayFormatter.string(from: $0) } ?? fallbackWeekdayTitle(for: day.dayOfWeek),
                    detailTitle: day.date.map { detailFormatter.string(from: $0) } ?? emptyToNil(day.dayDescription),
                    isToday: day.isToday,
                    isSchoolDay: day.dayType.isSchoolDay,
                    lessons: day.lessons.map { lesson in
                        makeLesson(from: lesson, dayStart: dayStart, calendar: calendar)
                    }
                )
            }
        )
    }

    private static func makeLesson(
        from lesson: ScheduledLesson,
        dayStart: Date,
        calendar: Calendar
    ) -> GradelyWatchTimetableLesson {
        let startDate = date(from: lesson.hour.beginTime, on: dayStart, calendar: calendar)
        var endDate = date(from: lesson.hour.endTime, on: dayStart, calendar: calendar)

        if let startDate, let currentEndDate = endDate, currentEndDate < startDate {
            endDate = calendar.date(byAdding: .day, value: 1, to: currentEndDate)
        }

        return GradelyWatchTimetableLesson(
            id: lesson.id,
            dayStart: dayStart,
            startDate: startDate,
            endDate: endDate,
            subjectName: lesson.subjectName,
            subjectAbbrev: lesson.subjectAbbrev,
            timeRange: timeRange(for: lesson.hour),
            room: lesson.roomAbbrev ?? lesson.roomName,
            teacher: lesson.teacherAbbrev ?? lesson.teacherName,
            changeKind: changeKind(for: lesson.changeKind)
        )
    }

    private static func startOfDay(for day: ScheduledDay, in week: TimetableWeek, calendar: Calendar) -> Date {
        if let date = day.date {
            return calendar.startOfDay(for: date)
        }

        let dayOffset = max(day.dayOfWeek - 1, 0)
        let fallbackDate = calendar.date(byAdding: .day, value: dayOffset, to: week.weekStart) ?? week.weekStart
        return calendar.startOfDay(for: fallbackDate)
    }

    private static func date(from time: String, on dayStart: Date, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
    }

    private static func timeRange(for hour: TimetableHour) -> String? {
        let beginTime = hour.beginTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let endTime = hour.endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !beginTime.isEmpty, !endTime.isEmpty else {
            return nil
        }

        return "\(beginTime)-\(endTime)"
    }

    private static func changeKind(for kind: LessonChangeKind) -> GradelyWatchLessonChangeKind {
        switch kind {
        case .none:
            return .none
        case .canceled:
            return .canceled
        case .substitution:
            return .substitution
        case .roomChanged:
            return .roomChanged
        case .added:
            return .added
        }
    }

    private static func fallbackWeekdayTitle(for dayOfWeek: Int) -> String {
        switch dayOfWeek {
        case 1: return "Mon"
        case 2: return "Tue"
        case 3: return "Wed"
        case 4: return "Thu"
        case 5: return "Fri"
        case 6: return "Sat"
        case 7: return "Sun"
        default: return "Day"
        }
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
