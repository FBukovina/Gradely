// Shell-only dependencies for focused core tests; no Calendar permissions or network providers are used.
import Foundation
enum AppL10n { static func string(_ key: String) -> String { key } }
struct SchoolDataScope: Codable, Equatable { let rawValue: String }
struct ScheduledHour { var id = 1; var caption = "1"; var beginTime = "08:00"; var endTime = "08:45" }
struct ScheduledLesson { var id = "lesson"; var hour = ScheduledHour(); var subjectID: String?; var groupIDs: [String] = []; var teacherName: String?; var teacherAbbrev: String?; var roomAbbrev: String?; var roomName: String?; var subjectName: String?; var subjectAbbrev: String?; var title = "Math" }
struct ScheduledDay { var date: Date?; var id = "day" }
enum TimetableLessonTiming { static func date(_ text: String, on: Date, calendar: Calendar) -> Date? { on } }
enum TimetableDates { static func apiDateString(_ date: Date) -> String { "2026-10-05" } }
@MainActor protocol PlannerCalendarSyncing { var hasAccess: Bool { get }; func requestAccess() async throws; func upsert(_ item: PlannerItem) throws -> String; func remove(_ item: PlannerItem) throws }
@MainActor final class PlannerCalendarService: PlannerCalendarSyncing { var hasAccess = false; func requestAccess() async throws { throw PlannerError.calendarPermission }; func upsert(_ item: PlannerItem) throws -> String { "test" }; func remove(_ item: PlannerItem) throws {} }
typealias UnavailablePlannerCalendarService = PlannerCalendarService
enum AppError: Error { case notLoggedIn }

enum PreviewData {}
