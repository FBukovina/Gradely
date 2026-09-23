import Foundation
import CryptoKit

nonisolated enum GradeySiriKind: String, Codable, Sendable { case subject, grade, lesson, planner }

/// Versioned, opaque identifiers. No account credentials, names, or notes enter URLs.
nonisolated struct GradeySiriID: Hashable, Codable, Sendable {
    let kind: GradeySiriKind
    let scope: String
    let key: String
    var value: String { "v1.\(kind.rawValue).\(scope).\(key)" }
    init(kind: GradeySiriKind, scope: String, source: String) {
        self.kind = kind; self.scope = scope
        self.key = kind == .lesson ? String(source.prefix(10)).replacingOccurrences(of: "-", with: "") + String(Self.hash(source).prefix(56)) : Self.hash(source)
    }
    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "v1", let kind = GradeySiriKind(rawValue: String(parts[1])),
              [parts[2], parts[3]].allSatisfy({ $0.count == 64 && $0.allSatisfy({ "0123456789abcdef".contains($0) }) }) else { return nil }
        self.kind = kind; self.scope = String(parts[2]); self.key = String(parts[3])
    }
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var url: URL { URL(string: "gradey://siri/\(value)")! }
    static func from(url: URL) -> Self? {
        guard ["gradey", "gradely"].contains(url.scheme ?? ""), url.host == "siri",
              url.query == nil, url.fragment == nil else { return nil }
        return Self(String(url.path.dropFirst()))
    }
}

nonisolated struct GradeySiriSubject: Sendable, Equatable {
    let id: String
    let name: String
    let abbreviation: String
    let officialAverage: String?
    let calculatedAverage: String?
    let updatedAt: Date
    let isStale: Bool
}
nonisolated struct GradeySiriGrade: Sendable, Equatable {
    let id: String
    let subjectID: String
    let subjectName: String
    let value: String
    let date: Date?
    let updatedAt: Date
    let isStale: Bool
}
nonisolated struct GradeySiriLesson: Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let room: String
    let change: String
    let isCanceled: Bool
    let updatedAt: Date
    let isStale: Bool
}
nonisolated struct GradeySiriPlannerItem: Sendable, Equatable {
    let id: String
    let title: String
    let type: String
    let subjectName: String?
    let date: Date?
    let hasTime: Bool
    let timeZoneIdentifier: String
    let createdAt: Date
    let updatedAt: Date
}
nonisolated struct GradeySiriSnapshot: Sendable {
    var subjects: [GradeySiriSubject] = []
    var grades: [GradeySiriGrade] = []
    var lessons: [GradeySiriLesson] = []
    var planner: [GradeySiriPlannerItem] = []
}

nonisolated enum GradeySiriError: String, LocalizedError {
    case setup, unavailable, changedAccount, missingItem, unsupported, invalidDate
    var errorDescription: String? { Bundle.main.localizedString(forKey: "siri.error.\(rawValue)", value: nil, table: nil) }
}

@MainActor
final class GradeyIntentService {
    struct Access: Equatable {
        let scope: SchoolDataScope
        let token: String
        let generation: UUID
    }
    struct PreparedCreation {
        let access: Access
        let draft: PlannerItem
        let summary: String
    }
    struct CreationResult {
        let item: GradeySiriPlannerItem
        let calendarPending: Bool
    }
    let environment: AppEnvironment
    var repository: SchoolRepository { environment.repository }
    var snapshot: SchoolSnapshotStore { environment.schoolSnapshotStore }
    var planner: PlannerStore { environment.makePlannerStore() }
    private let setupAllowed: () -> Bool
    private let now: () -> Date
    let calendar: Calendar
    private let refreshTimeout: Duration

    init(environment: AppEnvironment, calendar: Calendar = .current, now: @escaping () -> Date = Date.init,
         refreshTimeout: Duration = .seconds(8), setupAllowed: (() -> Bool)? = nil) {
        self.environment = environment; self.calendar = calendar; self.now = now
        self.refreshTimeout = refreshTimeout
        self.setupAllowed = setupAllowed ?? {
            let defaults = UserDefaults.standard
            return AgeAttestationStore.shared.allowsAppUse && !PrivacyPolicyConsentStore.shared.needsAcknowledgement
                && (defaults.bool(forKey: OnboardingProgressStore.completionKey)
                    || (defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey)
                        && OnboardingProgressStore(userDefaults: defaults).loadProgress() == nil))
        }
    }

    func access() throws -> Access {
        guard setupAllowed(), let session = try repository.currentStoredSession() else { throw GradeySiriError.setup }
        guard session.provider != .eduPage || session.eduPage?.activeStudent != nil else { throw GradeySiriError.setup }
        if environment.requiresGradeyID && !environment.guestModeStore.isEnabled {
            guard try environment.gradeyAuthClient.bootstrapSession() != nil else { throw GradeySiriError.setup }
        }
        let scope = SchoolDataScope(session: session)
        let account = (try? environment.gradeyAuthClient.bootstrapSession())?.account.id ?? "local"
        return Access(scope: scope, token: GradeySiriID.hash(account + "\u{1f}" + scope.rawValue), generation: repository.sessionGeneration)
    }
    func validate(_ expected: Access) throws {
        try Task.checkCancellation()
        guard try access() == expected else { throw GradeySiriError.changedAccount }
    }
    func validateID(_ value: String, kind: GradeySiriKind, access: Access) throws -> GradeySiriID {
        guard let id = GradeySiriID(value), id.kind == kind, id.scope == access.token else { throw GradeySiriError.missingItem }
        return id
    }
    func id(_ kind: GradeySiriKind, source: String, access: Access) -> String {
        GradeySiriID(kind: kind, scope: access.token, source: source).value
    }

    func subjects(matching query: String? = nil, refresh: Bool = true) async throws -> [GradeySiriSubject] {
        let access = try access()
        snapshot.activateCurrentScope()
        var completed = true
        if refresh { completed = await waitForRefresh { await self.snapshot.refresh(requirements: .marks) } }
        try validate(access)
        guard let updated = snapshot.marksFetchedAt else { throw GradeySiriError.unavailable }
        let stale = !completed || snapshot.sourceState("marks").isStale(at: now(), interval: 300)
        return snapshot.subjects.filter { Self.matches(query, in: [$0.trimmedName, $0.trimmedAbbrev]) }.map { subject in
            let calculated = snapshot.preparedCalculations[subject.id]?.calculatedAverage
            return GradeySiriSubject(id: id(.subject, source: subject.id, access: access), name: subject.trimmedName,
                abbreviation: subject.trimmedAbbrev, officialAverage: subject.averageText?.nilIfSiriEmpty,
                calculatedAverage: calculated.map { GradeMath.formattedAverage($0) }, updatedAt: updated, isStale: stale)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func grades(subjectID: String, refresh: Bool = true) async throws -> [GradeySiriGrade] {
        let access = try access()
        _ = try validateID(subjectID, kind: .subject, access: access)
        let subjects = try await subjects(refresh: refresh)
        try validate(access)
        guard let record = subjects.first(where: { $0.id == subjectID }),
              let subject = snapshot.subjects.first(where: { id(.subject, source: $0.id, access: access) == subjectID }) else { throw GradeySiriError.missingItem }
        // Provider IDs (including the existing stable local fallback) are scoped by subject.
        return subject.marks.map { mark in
            GradeySiriGrade(id: id(.grade, source: subject.id + "\u{1f}" + mark.id, access: access), subjectID: subjectID,
                subjectName: record.name, value: mark.displayText, date: MarkDateFormatter.date(from: mark.markDate),
                updatedAt: record.updatedAt, isStale: record.isStale)
        }.sorted { ($0.date ?? .distantPast, $0.id) > ($1.date ?? .distantPast, $1.id) }
    }

    func schedule(on date: Date, refresh: Bool = true) async throws -> [GradeySiriLesson] {
        let access = try access()
        snapshot.activateCurrentScope()
        var completed = true
        if refresh { completed = await waitForRefresh { await self.snapshot.refreshTimetable(containing: date) } }
        try validate(access)
        guard let week = cachedWeek(containing: date),
              let day = week.days.first(where: { $0.date.map { calendar.isDate($0, inSameDayAs: date) } == true }),
              let updated = repository.cachedTimetableDate(weekContaining: date) else { throw GradeySiriError.unavailable }
        let records = lessons(in: day, updated: updated, stale: !completed || timetableIsStale(date), access: access)
        guard day.lessons.isEmpty || !records.isEmpty else { throw GradeySiriError.unavailable }
        return records
    }

    func nextLessons() async throws -> [GradeySiriLesson] {
        let access = try access(), date = now(), next = TimetableDates.addingWeeks(1, to: now())
        snapshot.activateCurrentScope()
        let completed = await waitForRefresh {
            await self.snapshot.refreshTimetable(containing: date)
            await self.snapshot.refreshTimetable(containing: next)
        }
        try validate(access)
        // An absent week cannot establish that there is no upcoming lesson.
        guard let first = cachedWeek(containing: date), let second = cachedWeek(containing: next),
              let firstUpdated = repository.cachedTimetableDate(weekContaining: date),
              let secondUpdated = repository.cachedTimetableDate(weekContaining: next) else {
            // Still return a known upcoming lesson in the current week when the following week is unavailable.
            guard let week = cachedWeek(containing: date), let updated = repository.cachedTimetableDate(weekContaining: date),
                  let lesson = week.days.flatMap({ lessons(in: $0, updated: updated, stale: true, access: access) })
                    .filter({ !$0.isCanceled && $0.start > date }).sorted(by: { $0.start < $1.start }).first else { throw GradeySiriError.unavailable }
            return [lesson]
        }
        let records = first.days.flatMap { lessons(in: $0, updated: firstUpdated, stale: !completed || timetableIsStale(date), access: access) }
            + second.days.flatMap { lessons(in: $0, updated: secondUpdated, stale: !completed || timetableIsStale(next), access: access) }
        return Array(records.filter { !$0.isCanceled && $0.start > date }.sorted { $0.start < $1.start }.prefix(1))
    }

    func cachedWeek(containing date: Date) -> TimetableWeek? {
        snapshot.cachedWeek(containing: date) ?? repository.loadCachedTimetable(weekContaining: date, publishSummaries: false)
    }
    private func timetableIsStale(_ date: Date) -> Bool {
        var state = snapshot.sourceState("timetable-" + TimetableDates.apiDateString(TimetableDates.monday(of: date)))
        state.lastSuccessAt = repository.cachedTimetableDate(weekContaining: date)
        return state.isStale(at: now(), interval: 900)
    }
    func lessons(in day: ScheduledDay, updated: Date, stale: Bool, access: Access) -> [GradeySiriLesson] {
        guard let date = day.date else { return [] }
        return day.lessons.compactMap { lesson in
            guard let start = TimetableLessonTiming.date(lesson.hour.beginTime, on: date, calendar: calendar),
                  let end = TimetableLessonTiming.date(lesson.hour.endTime, on: date, calendar: calendar), end > start else { return nil }
            let key = lessonKey(lesson, day: day)
            return GradeySiriLesson(id: id(.lesson, source: key, access: access), title: lesson.subjectName ?? lesson.title,
                start: start, end: end, room: lesson.roomAbbrev ?? lesson.roomName ?? "",
                change: lesson.changeKind.localizedLabel ?? "", isCanceled: lesson.isCanceled, updatedAt: updated, isStale: stale)
        }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
    func lessonKey(_ lesson: ScheduledLesson, day: ScheduledDay) -> String {
        (day.date.map(TimetableDates.apiDateString) ?? day.id) + ":" + [String(lesson.hour.id), lesson.subjectID ?? "", lesson.groupIDs.sorted().joined(separator: "\u{1e}")]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    func plannerItems(on date: Date? = nil, subjectID: String? = nil, matching query: String? = nil) throws -> [GradeySiriPlannerItem] {
        let access = try access()
        if let subjectID { _ = try validateID(subjectID, kind: .subject, access: access) }
        planner.loadIfNeeded()
        guard planner.isLoaded else { throw PlannerError.storageUnavailable }
        return planner.items.filter { item in
            guard Self.isVisible(item, scope: access.scope), !item.isCompleted else { return false }
            if let date {
                guard let day = PlannerDayProjection.day(for: item, calendar: calendar), calendar.isDate(day, inSameDayAs: date) else { return false }
            }
            if let subjectID {
                guard let subject = item.subject, subject.scope == access.scope,
                      id(.subject, source: subject.id, access: access) == subjectID else { return false }
            }
            return Self.matches(query, in: [item.title, item.subject?.name ?? ""])
        }.map { plannerRecord($0, access: access) }
    }
    static func isVisible(_ item: PlannerItem, scope: SchoolDataScope) -> Bool {
        guard item.deletedAt == nil else { return false }
        if let a = item.subject?.scope, let b = item.lesson?.scope, a != b { return false }
        return (item.subject?.scope ?? item.lesson?.scope).map { $0 == scope } ?? true
    }
    func plannerRecord(_ item: PlannerItem, access: Access) -> GradeySiriPlannerItem {
        GradeySiriPlannerItem(id: id(.planner, source: item.id.uuidString, access: access), title: item.title, type: item.type.rawValue,
            subjectName: item.subject?.name, date: item.orderingDate,
            hasTime: item.dueDate != nil ? item.dueHasTime : item.lesson?.start != nil,
            timeZoneIdentifier: item.timeZoneIdentifier, createdAt: item.createdAt, updatedAt: item.updatedAt)
    }

    func prepareCreation(title: String, type: PlannerItemType, due: Date?, hasTime: Bool,
                         subjectID: String?, notes: String?, timeZone: TimeZone? = nil) throws -> PreparedCreation {
        let access = try access()
        guard let title = title.nilIfSiriEmpty else { throw PlannerError.titleRequired }
        if hasTime && due == nil { throw GradeySiriError.invalidDate }
        var draft = PlannerItem()
        draft.title = title; draft.type = type; draft.dueDate = due; draft.dueHasTime = hasTime
        let timeZone = timeZone ?? calendar.timeZone
        draft.timeZoneIdentifier = timeZone.identifier; draft.notes = notes?.nilIfSiriEmpty
        if let subjectID {
            _ = try validateID(subjectID, kind: .subject, access: access)
            snapshot.activateCurrentScope()
            guard let subject = snapshot.subjects.first(where: { id(.subject, source: $0.id, access: access) == subjectID }) else { throw GradeySiriError.missingItem }
            draft.subject = PlannerSubjectReference(scope: access.scope, id: subject.id, name: subject.trimmedName, abbreviation: subject.trimmedAbbrev)
        }
        let dateText = due.map { Self.dateText($0, hasTime: hasTime, timeZone: timeZone) } ?? AppL10n.string("siri.undated")
        let summary = [type.title, title, draft.subject?.name, dateText, notes?.nilIfSiriEmpty].compactMap { $0 }.joined(separator: ". ")
        return PreparedCreation(access: access, draft: draft, summary: summary)
    }
    /// Confirmation is injected so tests exercise the actual commit boundary, including cancellation/account switches.
    func create(_ prepared: PreparedCreation, confirm: () async throws -> Void) async throws -> CreationResult {
        try validate(prepared.access)
        try await confirm()
        try validate(prepared.access)
        // UUID was allocated before confirmation. Re-entering this execution cannot append a duplicate.
        try await planner.save(prepared.draft, requestCalendarAccess: false)
        try validate(prepared.access)
        guard let saved = planner.items.first(where: { $0.id == prepared.draft.id }) else { throw PlannerError.storageUnavailable }
        return CreationResult(item: plannerRecord(saved, access: prepared.access), calendarPending: saved.calendarNeedsSync)
    }

    func scheduleFreshness(on date: Date) throws -> String {
        _ = try access()
        guard let updated = repository.cachedTimetableDate(weekContaining: date) else { throw GradeySiriError.unavailable }
        return Self.freshness(updated, stale: timetableIsStale(date))
    }

    func resolveLessons(identifiers: [String]) async throws -> [GradeySiriLesson] {
        let expected = try access()
        snapshot.activateCurrentScope()
        let identifiers = identifiers.filter { GradeySiriID($0)?.scope == expected.token }
        let dates = Set(identifiers.compactMap { GradeySiriID($0).flatMap(lessonDate) }.map { TimetableDates.monday(of: $0) })
        _ = await waitForRefresh {
            for date in dates.sorted() { await self.snapshot.refreshTimetable(containing: date) }
        }
        try validate(expected)
        let records = dates.flatMap { date -> [GradeySiriLesson] in
            guard let week = cachedWeek(containing: date), let updated = repository.cachedTimetableDate(weekContaining: date) else { return [] }
            return week.days.flatMap { lessons(in: $0, updated: updated, stale: timetableIsStale(date), access: expected) }
        }
        return identifiers.compactMap { id in records.first { $0.id == id } }
    }

    func resolveDueDate(_ input: DateComponents?) throws -> (date: Date?, hasTime: Bool, timeZone: TimeZone) {
        guard var components = input else { return (nil, false, calendar.timeZone) }
        var calendar = components.calendar ?? self.calendar
        calendar.timeZone = components.timeZone ?? calendar.timeZone
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let hasTime = components.hour != nil || components.minute != nil
        guard components.year != nil, components.month != nil, components.day != nil,
              !hasTime || components.hour != nil, components.isValidDate(in: calendar),
              let date = calendar.date(from: components) else { throw GradeySiriError.invalidDate }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard roundTrip.year == components.year, roundTrip.month == components.month, roundTrip.day == components.day,
              components.hour.map({ roundTrip.hour == $0 }) ?? true,
              components.minute.map({ roundTrip.minute == $0 }) ?? true else { throw GradeySiriError.invalidDate }
        return (date, hasTime, calendar.timeZone)
    }

    /// Cache-only materialization for indexing and entity resolution. Never fetch a whole school account to index it.
    func discoverySnapshot() async throws -> GradeySiriSnapshot {
        let access = try access()
        snapshot.activateCurrentScope()
        var result = GradeySiriSnapshot()
        if snapshot.marksFetchedAt != nil {
            result.subjects = try await subjects(refresh: false)
            for subject in result.subjects { result.grades += try await grades(subjectID: subject.id, refresh: false) }
        }
        for date in [now(), TimetableDates.addingWeeks(1, to: now())] {
            if let week = cachedWeek(containing: date), let updated = repository.cachedTimetableDate(weekContaining: date) {
                result.lessons += week.days.flatMap { lessons(in: $0, updated: updated, stale: timetableIsStale(date), access: access) }
            }
        }
        result.planner = try plannerItems()
        try validate(access)
        return result
    }

    static func matches(_ query: String?, in values: [String]) -> Bool {
        guard let query = query?.nilIfSiriEmpty else { return true }
        return values.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    static func dateText(_ date: Date, hasTime: Bool = true, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageOverride.locale; formatter.timeZone = timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = hasTime ? .short : .none
        return formatter.string(from: date)
    }
    static func summary(_ lines: [String], emptyKey: String = "siri.empty") -> String {
        guard !lines.isEmpty else { return AppL10n.string(String.LocalizationValue(emptyKey)) }
        return String(format: AppL10n.string("siri.results"), lines.count, lines.prefix(3).joined(separator: "; "))
    }
    static func freshness(_ date: Date, stale: Bool) -> String {
        String(format: AppL10n.string(stale ? "siri.cached" : "siri.updated"), dateText(date))
    }
    private func waitForRefresh(_ operation: @escaping @MainActor () async -> Void) async -> Bool {
        let waiter = GradeySiriRefreshWaiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.continuation = continuation
                if Task.isCancelled { waiter.finish(false); return }
                waiter.work = Task { await operation(); waiter.finish(!Task.isCancelled) }
                waiter.timer = Task {
                    do { try await Task.sleep(for: refreshTimeout); waiter.finish(false) } catch { }
                }
            }
        } onCancel: { Task { @MainActor in waiter.finish(false) } }
    }
}

/// An unstructured waiter lets Siri time out without waiting for a shared provider request to finish.
@MainActor private final class GradeySiriRefreshWaiter {
    var continuation: CheckedContinuation<Bool, Never>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
    func finish(_ completed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel(); work?.cancel(); timer = nil; work = nil
        continuation.resume(returning: completed)
    }
}

private extension String {
    var nilIfSiriEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
