import Foundation
import GradelyWatchShared

enum GradelyWatchDemoTimetable {
    static func make(weekStart: Date, now: Date, calendar: Calendar = .current) -> GradelyWatchTimetable {
        let subjects = [
            ("Mathematics", "M", "12"),
            ("Czech", "CZ", "24"),
            ("Physics", "PH", "Lab"),
            ("History", "H", "31")
        ]
        let hours = [
            ("08:00", "08:45"),
            ("08:55", "09:40"),
            ("10:00", "10:45"),
            ("10:55", "11:40")
        ]

        let days = (0..<5).map { offset -> GradelyWatchTimetableDay in
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart)
            let lessons = subjects.enumerated().map { index, subject -> GradelyWatchTimetableLesson in
                let hour = hours[index]
                let startDate = date(hour.0, on: dayStart, calendar: calendar)
                let endDate = date(hour.1, on: dayStart, calendar: calendar)
                return GradelyWatchTimetableLesson(
                    id: "demo-\(offset)-\(index)",
                    dayStart: dayStart,
                    startDate: startDate,
                    endDate: endDate,
                    subjectName: subject.0,
                    subjectAbbrev: subject.1,
                    timeRange: "\(hour.0)-\(hour.1)",
                    room: subject.2,
                    teacher: nil,
                    changeKind: index == 2 && offset == 0 ? .roomChanged : .none
                )
            }

            return GradelyWatchTimetableDay(
                id: "demo-day-\(offset)",
                date: dayStart,
                dayStart: dayStart,
                weekdayTitle: weekdayTitle(for: dayStart, calendar: calendar),
                detailTitle: detailTitle(for: dayStart, calendar: calendar),
                isToday: calendar.isDate(dayStart, inSameDayAs: now),
                isSchoolDay: true,
                lessons: lessons
            )
        }

        return GradelyWatchTimetable(weekStart: weekStart, cachedAt: now, days: days)
    }

    private static func date(_ time: String, on dayStart: Date, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
    }

    private static func weekdayTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private static func detailTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}
