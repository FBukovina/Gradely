import Foundation

/// Turns the normalized Bakalari timetable payload into a view-ready `TimetableWeek`.
///
/// Atoms reference entities by `Id`, and those ids may carry leading/inner spaces, so lookups
/// match the *raw* id and only the resolved display strings are trimmed.
enum TimetableMapper {
    static func makeWeek(
        from response: TimetableResponse,
        weekStart: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableWeek {
        let subjects = index(response.subjects)
        let teachers = index(response.teachers)
        let rooms = index(response.rooms)
        let groups = Dictionary(response.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hoursByID = Dictionary(response.hours.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hourOrder = Dictionary(
            uniqueKeysWithValues: response.hours.enumerated().map { ($0.element.id, $0.offset) }
        )

        let days = response.days.map { dto -> ScheduledDay in
            let date = MarkDateFormatter.date(from: dto.date)
            let dayID = dto.date.isEmpty ? "dow-\(dto.dayOfWeek)" : dto.date

            let lessons = dto.atoms.enumerated().map { offset, atom -> ScheduledLesson in
                let hour = hoursByID[atom.hourID]
                    ?? TimetableHour(id: atom.hourID, caption: "\(atom.hourID)", beginTime: "", endTime: "")
                let subject = atom.subjectID.flatMap { subjects[$0] }
                let teacher = atom.teacherID.flatMap { teachers[$0] }
                let room = atom.roomID.flatMap { rooms[$0] }
                let groupAbbrevs = atom.groupIDs.compactMap { groups[$0] }.compactMap { trimmed($0.abbrev) }

                return ScheduledLesson(
                    id: "\(dayID)#\(atom.hourID)#\(offset)",
                    hour: hour,
                    subjectName: trimmed(subject?.name),
                    subjectAbbrev: trimmed(subject?.abbrev),
                    teacherName: trimmed(teacher?.name),
                    teacherAbbrev: trimmed(teacher?.abbrev),
                    roomAbbrev: trimmed(room?.abbrev),
                    roomName: trimmed(room?.name),
                    groups: groupAbbrevs,
                    theme: trimmed(atom.theme),
                    hasHomework: !atom.homeworkIDs.isEmpty,
                    change: atom.change,
                    changeKind: LessonChangeKind(changeType: atom.change?.changeType)
                )
            }
            .sorted { (hourOrder[$0.hour.id] ?? .max) < (hourOrder[$1.hour.id] ?? .max) }

            let isToday = date.map { calendar.isDate($0, inSameDayAs: today) } ?? false

            return ScheduledDay(
                id: dayID,
                date: date,
                dayOfWeek: dto.dayOfWeek,
                dayType: DayType(apiValue: dto.dayType),
                dayDescription: dto.dayDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                lessons: lessons,
                isToday: isToday
            )
        }

        return TimetableWeek(weekStart: weekStart, days: days, hours: response.hours)
    }

    private static func index(_ entities: [TimetableEntity]) -> [String: TimetableEntity] {
        Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
