import Foundation

enum NextLessonWidgetConstants {
    static let appGroupIdentifier = "group.com.bukovinafilip.BakalariMarks"
    static let widgetKind = "GradelyNextLessonWidget"
    static let snapshotFileName = "next-lesson-widget-snapshot.json"
    static let timetableDeepLink = URL(string: "gradely://timetable")!
}

enum NextLessonWidgetChangeKind: String, Codable, Equatable {
    case none
    case canceled
    case substitution
    case roomChanged
    case added
}

enum NextLessonWidgetTiming: String, Codable, Equatable {
    case current
    case upcoming
}

struct NextLessonWidgetSnapshot: Codable, Equatable {
    let cachedAt: Date
    let lessons: [NextLessonWidgetLesson]

    init(cachedAt: Date, lessons: [NextLessonWidgetLesson]) {
        self.cachedAt = cachedAt
        self.lessons = lessons
    }
}

struct NextLessonWidgetLesson: Codable, Equatable, Identifiable {
    let id: String
    let dayStart: Date
    let startDate: Date?
    let endDate: Date?
    let subjectName: String?
    let subjectAbbrev: String?
    let timeRange: String?
    let room: String?
    let teacher: String?
    let changeKind: NextLessonWidgetChangeKind

    init(
        id: String,
        dayStart: Date,
        startDate: Date?,
        endDate: Date?,
        subjectName: String?,
        subjectAbbrev: String?,
        timeRange: String?,
        room: String?,
        teacher: String?,
        changeKind: NextLessonWidgetChangeKind
    ) {
        self.id = id
        self.dayStart = dayStart
        self.startDate = startDate
        self.endDate = endDate
        self.subjectName = subjectName
        self.subjectAbbrev = subjectAbbrev
        self.timeRange = timeRange
        self.room = room
        self.teacher = teacher
        self.changeKind = changeKind
    }

    var title: String {
        if let subjectAbbrev, !subjectAbbrev.isEmpty {
            return subjectAbbrev
        }
        if let subjectName, !subjectName.isEmpty {
            return subjectName
        }
        return "Lesson"
    }

    var detailTitle: String {
        subjectName ?? subjectAbbrev ?? "Lesson"
    }

    var sortDate: Date {
        startDate ?? dayStart
    }
}

enum NextLessonWidgetSelection: Equatable {
    case lesson(NextLessonWidgetLesson, timing: NextLessonWidgetTiming)
    case noSnapshot
    case noLessons
    case stale
}
