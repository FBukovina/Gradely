import Foundation

/// The lesson happening right now and the one after it, as shown on the watch and its complications.
public struct GradelyWatchNowNext: Equatable, Sendable {
    public let current: GradelyWatchTimetableLesson?
    public let next: GradelyWatchTimetableLesson?

    public init(current: GradelyWatchTimetableLesson?, next: GradelyWatchTimetableLesson?) {
        self.current = current
        self.next = next
    }

    public var isEmpty: Bool {
        current == nil && next == nil
    }
}

public extension GradelyWatchSyncCodec {
    static func nowAndNext(
        from timetable: GradelyWatchTimetable?,
        now: Date = Date(),
        staleInterval: TimeInterval = staleInterval
    ) -> GradelyWatchNowNext {
        guard let timetable, now.timeIntervalSince(timetable.cachedAt) <= staleInterval else {
            return GradelyWatchNowNext(current: nil, next: nil)
        }

        let lessons = timetable.days
            .flatMap(\.lessons)
            .sorted { first, second in
                if first.sortDate == second.sortDate {
                    return first.id < second.id
                }
                return first.sortDate < second.sortDate
            }

        let current = lessons.first { lesson in
            guard let startDate = lesson.startDate, let endDate = lesson.endDate else {
                return false
            }
            return startDate <= now && now <= endDate
        }

        let next = lessons.first { lesson in
            guard lesson.id != current?.id else { return false }
            guard let startDate = lesson.startDate else {
                return lesson.sortDate >= now
            }
            return startDate > now
        }

        return GradelyWatchNowNext(current: current, next: next)
    }
}

/// Shared storage location so the watch app and its complications read the same timetable cache.
public enum GradelyWatchAppGroup {
    public static let identifier = "group.com.bukovinafilip.BakalariMarks"

    public static func timetableCacheURL(fileManager: FileManager = .default) -> URL {
        let directory: URL
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            directory = container
        } else {
            directory = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
        }
        return directory
            .appending(path: "GradelyWatch", directoryHint: .isDirectory)
            .appending(path: "timetable-cache.json")
    }
}
