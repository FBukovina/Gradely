import Foundation

struct AbsenceDayLesson: Identifiable, Equatable {
    let id: String
    let hourCaption: String
    let timeRange: String
    let subjectName: String
    let isHidden: Bool
}

struct AbsenceDayLessons: Equatable {
    enum Status: Equatable {
        case resolved
        case needsSelection(required: Int)
    }

    let dateKey: String
    let status: Status
    let lessons: [AbsenceDayLesson]
}

/// Lists the subjects behind one day of absence so the Days list can show what
/// was missed without reopening the editor.
enum AbsenceDayLessonResolver {
    static func resolve(
        day: AbsenceDay,
        timetableLessons: [AbsenceLessonCandidate]?,
        selectedLessonIDs: Set<String>,
        activeOverride: AbsenceDayOverride?
    ) -> AbsenceDayLessons? {
        let dateKey = AbsenceOverrideProjection.dateKey(day.date)

        // A confirmed allocation replaces inference, even without a timetable.
        if let activeOverride {
            let lessonsByID = Dictionary(
                (timetableLessons ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let rows = activeOverride.allocations.enumerated().map { index, allocation in
                let lesson = allocation.lessonID.flatMap { lessonsByID[$0] }
                return (
                    index: index,
                    hourID: lesson?.hourID,
                    lesson: AbsenceDayLesson(
                        id: allocation.id,
                        hourCaption: lesson?.hourCaption ?? "",
                        timeRange: lesson?.timeRange ?? "",
                        subjectName: allocation.subjectName,
                        isHidden: activeOverride.hiddenAllocationIDs.contains(allocation.id)
                    )
                )
            }
            let sorted = rows.sorted { lhs, rhs in
                switch (lhs.hourID, rhs.hourID) {
                case let (lhsHour?, rhsHour?):
                    return lhsHour == rhsHour ? lhs.index < rhs.index : lhsHour < rhsHour
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.index < rhs.index
                }
            }
            return AbsenceDayLessons(dateKey: dateKey, status: .resolved, lessons: sorted.map(\.lesson))
        }

        guard let timetableLessons else { return nil }
        let base = day.unsolved + day.ok + day.missed
        guard base > 0 else {
            return AbsenceDayLessons(dateKey: dateKey, status: .resolved, lessons: [])
        }
        guard !timetableLessons.isEmpty else { return nil }

        func lessonRow(_ lesson: AbsenceLessonCandidate) -> AbsenceDayLesson {
            AbsenceDayLesson(
                id: lesson.id,
                hourCaption: lesson.hourCaption,
                timeRange: lesson.timeRange,
                subjectName: lesson.subjectName,
                isHidden: false
            )
        }

        if base >= timetableLessons.count {
            return AbsenceDayLessons(
                dateKey: dateKey,
                status: .resolved,
                lessons: timetableLessons.map(lessonRow)
            )
        }

        let selected = timetableLessons.filter { selectedLessonIDs.contains($0.id) }
        if selected.count == base {
            return AbsenceDayLessons(dateKey: dateKey, status: .resolved, lessons: selected.map(lessonRow))
        }

        return AbsenceDayLessons(dateKey: dateKey, status: .needsSelection(required: base), lessons: [])
    }
}
