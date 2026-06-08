import Foundation

protocol NextLessonWidgetStoring {
    func loadSnapshot() throws -> NextLessonWidgetSnapshot?
    func save(snapshot: NextLessonWidgetSnapshot) throws
    func updateLessons(_ lessons: [NextLessonWidgetLesson], forWeekStarting weekStart: Date, cachedAt: Date) throws
    func clear() throws
}

final class NextLessonWidgetStore: NextLessonWidgetStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    convenience init?(fileManager: FileManager = .default) {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: NextLessonWidgetConstants.appGroupIdentifier
        ) else {
            return nil
        }

        self.init(
            fileURL: containerURL.appending(path: NextLessonWidgetConstants.snapshotFileName),
            fileManager: fileManager
        )
    }

    func loadSnapshot() throws -> NextLessonWidgetSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(NextLessonWidgetSnapshot.self, from: data)
    }

    func save(snapshot: NextLessonWidgetSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func updateLessons(_ lessons: [NextLessonWidgetLesson], forWeekStarting weekStart: Date, cachedAt: Date) throws {
        let weekEnd = Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: weekStart)
            ?? weekStart.addingTimeInterval(7 * 24 * 60 * 60)
        let existing = (try loadSnapshot())?.lessons ?? []
        let remainingLessons = existing.filter { lesson in
            lesson.dayStart < weekStart || lesson.dayStart >= weekEnd
        }
        let combined = uniqued(remainingLessons + lessons)
            .sorted { first, second in
                if first.sortDate == second.sortDate {
                    return first.id < second.id
                }
                return first.sortDate < second.sortDate
            }
        let snapshot = NextLessonWidgetSnapshot(cachedAt: cachedAt, lessons: combined)

        try save(snapshot: snapshot)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func uniqued(_ lessons: [NextLessonWidgetLesson]) -> [NextLessonWidgetLesson] {
        var lessonsByID: [String: NextLessonWidgetLesson] = [:]
        for lesson in lessons {
            lessonsByID[lesson.id] = lesson
        }
        return Array(lessonsByID.values)
    }
}
