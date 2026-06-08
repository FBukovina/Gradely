import Foundation

enum NextLessonWidgetSnapshotBuilder {
    static func lessons(
        from week: TimetableWeek,
        calendar: Calendar = .current
    ) -> [NextLessonWidgetLesson] {
        week.days.flatMap { day -> [NextLessonWidgetLesson] in
            let dayStart = startOfDay(for: day, in: week, calendar: calendar)

            return day.lessons.map { lesson in
                let startDate = date(from: lesson.hour.beginTime, on: dayStart, calendar: calendar)
                var endDate = date(from: lesson.hour.endTime, on: dayStart, calendar: calendar)

                if let startDate, let currentEndDate = endDate, currentEndDate < startDate {
                    endDate = calendar.date(byAdding: .day, value: 1, to: currentEndDate)
                }

                return NextLessonWidgetLesson(
                    id: lesson.id,
                    dayStart: dayStart,
                    startDate: startDate,
                    endDate: endDate,
                    subjectName: lesson.subjectName,
                    subjectAbbrev: lesson.subjectAbbrev,
                    timeRange: timeRange(for: lesson.hour),
                    room: lesson.roomAbbrev ?? lesson.roomName,
                    teacher: lesson.teacherName ?? lesson.teacherAbbrev,
                    changeKind: changeKind(for: lesson.changeKind)
                )
            }
        }
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

    private static func changeKind(for kind: LessonChangeKind) -> NextLessonWidgetChangeKind {
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
}
