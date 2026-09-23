import Foundation

/// A projection always starts from provider data (or its raw synthesized
/// baseline). It never mutates a cache, advances freshness, or reuses an already
/// adjusted response as a baseline.
enum AbsenceOverrideProjection {
    struct Result: Equatable {
        let response: AbsenceResponse
        let absencesPerSubject: [AbsencePerSubject]
        let reconciledOverrides: [AbsenceDayOverride]
        let metadata: AbsenceOverrideMetadata
    }

    static func project(
        rawResponse: AbsenceResponse,
        rawSubjects: [AbsencePerSubject],
        subjectStableIDHints: [String] = [],
        overrides: [AbsenceDayOverride],
        scope: SchoolDataScope,
        currentLessonsByDate: [String: [AbsenceLessonCandidate]]? = nil
    ) -> Result {
        let scoped = overrides.filter { $0.scope == scope }
        let duplicateDates = Set(Dictionary(grouping: scoped, by: \.dateKey).filter { $0.value.count != 1 }.keys)
        let rawDays = Dictionary(grouping: rawResponse.absences, by: { dateKey($0.date) })
        let official = !rawResponse.absencesPerSubject.isEmpty
        var effectiveDays = rawResponse.absences
        var effectiveSubjects = rawSubjects
        var reconciled: [AbsenceDayOverride] = []
        var active: [AbsenceDayOverride] = []
        var review: [AbsenceDayOverride] = []

        for saved in scoped.sorted(by: { $0.dateKey < $1.dateKey }) {
            var entry = saved
            // A previously observed conflict is sticky, even if a later provider
            // response happens to look like the old baseline again.
            var reason = entry.pauseReason
            if reason == nil, duplicateDates.contains(entry.dateKey) { reason = .invalidAllocation }
            if reason == nil {
                reason = validationReason(for: entry, rawDays: rawDays, currentLessonsByDate: currentLessonsByDate)
            }

            var nextSubjects = effectiveSubjects
            if reason == nil {
                // Only hidden units change official counters. An unhidden
                // original lesson may truthfully belong to an unreported subject.
                if official && entry.hiddenAllocations.contains(where: {
                    uniqueSubjectIndex(subjectKey: nil, subjectName: $0.subjectName,
                        subjects: rawSubjects, stableIDHints: []) == nil
                }) {
                    reason = .subjectMappingChanged
                }
            }
            if reason == nil {
                for allocation in entry.hiddenAllocations {
                    guard official || allocation.category.contributesToBase else { continue }
                    let matches = subjectIndices(subjectKey: official ? nil : allocation.subjectKey,
                        subjectName: allocation.subjectName, subjects: nextSubjects,
                        stableIDHints: official ? [] : subjectStableIDHints)
                    if matches.count > 1 {
                        reason = .subjectMappingChanged
                        break
                    }
                    guard let index = matches.first else {
                        // No synthesized denominator exists for this subject.
                        // Its percentage remains unavailable; do not create zero.
                        if official { reason = .subjectMappingChanged; break }
                        continue
                    }
                    guard let adjusted = subtract(allocation.category, from: nextSubjects[index]) else {
                        reason = .insufficientSubjectCount
                        break
                    }
                    nextSubjects[index] = adjusted
                }
            }

            if let reason {
                entry.pauseReason = reason
                review.append(entry)
            } else if let index = effectiveDays.firstIndex(where: { dateKey($0.date) == entry.dateKey }) {
                effectiveDays[index] = subtract(entry.hiddenAllocations, from: effectiveDays[index])
                effectiveSubjects = nextSubjects
                active.append(entry)
            }
            reconciled.append(entry)
        }

        // An empty provider subject array stays empty. Synthesized rows live in
        // AbsenceData.absencesPerSubject and must not masquerade as official.
        let hiddenDays = Set(active.filter(\.hidesEntireDay).map(\.dateKey))
        let response = AbsenceResponse(percentageThreshold: rawResponse.percentageThreshold,
            absences: effectiveDays.filter { !hiddenDays.contains(dateKey($0.date)) },
            absencesPerSubject: official ? effectiveSubjects : rawResponse.absencesPerSubject)
        return Result(response: response, absencesPerSubject: effectiveSubjects,
            reconciledOverrides: reconciled,
            metadata: AbsenceOverrideMetadata(activeOverrides: active, reviewOverrides: review))
    }

    /// A provider date is a school calendar day. Taking its date prefix avoids
    /// silently moving an edit when the device travels between time zones.
    static func dateKey(_ value: String) -> String {
        String(value.split(separator: "T", maxSplits: 1).first ?? Substring(value))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func schoolDate(_ value: String, calendar: Calendar = TimetableDates.weekCalendar) -> Date? {
        let rawComponents = dateKey(value).split(separator: "-")
        let components = rawComponents.compactMap { Int($0) }
        guard rawComponents.count == 3, components.count == 3 else { return nil }
        let parts = DateComponents(year: components[0], month: components[1], day: components[2])
        guard let date = calendar.date(from: parts),
              calendar.component(.year, from: date) == components[0],
              calendar.component(.month, from: date) == components[1],
              calendar.component(.day, from: date) == components[2] else { return nil }
        return date
    }

    static func dateKey(for date: Date, calendar: Calendar = TimetableDates.weekCalendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func normalizedSubjectName(_ value: String) -> String {
        AbsenceTimetableLessonResolver.normalized(value)
    }

    static func uniqueSubjectIndex(subjectKey: String?, subjectName: String,
                                   subjects: [AbsencePerSubject], stableIDHints: [String] = []) -> Int? {
        let matches = subjectIndices(subjectKey: subjectKey, subjectName: subjectName,
            subjects: subjects, stableIDHints: stableIDHints)
        return matches.count == 1 ? matches[0] : nil
    }

    /// Supplies the complete original allocation to the raw timetable fallback.
    /// Filtering to hidden units here would change a full day into a partial day.
    static func manualAllocations(for overrides: [AbsenceDayOverride], rawResponse: AbsenceResponse,
                                  scope: SchoolDataScope) -> [String: [AbsenceOverrideAllocation]] {
        let days = Dictionary(grouping: rawResponse.absences, by: { dateKey($0.date) })
        let scoped = overrides.filter { $0.scope == scope }
        let counts = Dictionary(grouping: scoped, by: \.dateKey)
        return scoped.reduce(into: [:]) { result, entry in
            guard entry.pauseReason == nil, counts[entry.dateKey]?.count == 1,
                  validationReason(for: entry, rawDays: days, currentLessonsByDate: nil) == nil else { return }
            result[entry.dateKey] = entry.allocations
        }
    }

    static func manualSelections(for overrides: [AbsenceDayOverride], rawResponse: AbsenceResponse,
                                 scope: SchoolDataScope) -> AbsenceLessonSelections {
        let allocations = manualAllocations(for: overrides, rawResponse: rawResponse, scope: scope)
        return AbsenceLessonSelections(selectedLessonIDsByDate: allocations.mapValues { rows in
            rows.filter { $0.category.contributesToBase }.compactMap(\.lessonID).sorted()
        })
    }

    private static func validationReason(for entry: AbsenceDayOverride, rawDays: [String: [AbsenceDay]],
                                         currentLessonsByDate: [String: [AbsenceLessonCandidate]]?) -> AbsenceOverridePauseReason? {
        guard let days = rawDays[entry.dateKey], !days.isEmpty else { return .dayMissing }
        guard days.count == 1 else { return .ambiguousDay }
        let current = days[0]
        guard dateKey(entry.baselineDay.date) == entry.dateKey,
              AbsenceOverrideCategory.allCases.allSatisfy({ $0.count(in: current) == $0.count(in: entry.baselineDay) }) else {
            return .dayChanged
        }
        let ids = Set(entry.allocations.map(\.id))
        guard !entry.hiddenAllocationIDs.isEmpty, entry.hiddenAllocationIDs.isSubset(of: ids),
              ids.count == entry.allocations.count,
              entry.allocations.allSatisfy({ !$0.id.isEmpty && !normalizedSubjectName($0.subjectName).isEmpty }),
              AbsenceOverrideCategory.allCases.allSatisfy({ category in
                  let count = category.count(in: current)
                  return count >= 0 && entry.allocations.filter { $0.category == category }.count == count
              }) else { return .invalidAllocation }
        let baseLessonIDs = entry.allocations.filter { $0.category.contributesToBase }.compactMap(\.lessonID)
        guard Set(baseLessonIDs).count == baseLessonIDs.count else { return .invalidAllocation }
        if let lessons = currentLessonsByDate?[entry.dateKey] {
            for allocation in entry.allocations {
                guard let lessonID = allocation.lessonID else { continue }
                let matches = lessons.filter { $0.id == lessonID }
                guard matches.count == 1,
                      allocation.subjectKey == nil || allocation.subjectKey == matches[0].subjectKey else { return .lessonMappingChanged }
            }
        }
        return nil
    }

    private static func subjectIndices(subjectKey: String?, subjectName: String,
                                       subjects: [AbsencePerSubject], stableIDHints: [String]) -> [Int] {
        if let subjectKey, !subjectKey.isEmpty {
            let matches = subjects.indices.filter { stableIDHints.indices.contains($0) && stableIDHints[$0] == subjectKey }
            if !matches.isEmpty { return matches }
        }
        let normalized = normalizedSubjectName(subjectName)
        guard !normalized.isEmpty else { return [] }
        return subjects.indices.filter { normalizedSubjectName(subjects[$0].subjectName) == normalized }
    }

    private static func subtract(_ allocations: [AbsenceOverrideAllocation], from day: AbsenceDay) -> AbsenceDay {
        func remaining(_ category: AbsenceOverrideCategory) -> Int {
            category.count(in: day) - allocations.filter { $0.category == category }.count
        }
        return AbsenceDay(date: day.date, unsolved: remaining(.unsolved), ok: remaining(.ok),
            missed: remaining(.missed), late: remaining(.late), soon: remaining(.soon),
            school: remaining(.school), distanceTeaching: remaining(.distanceTeaching))
    }

    private static func subtract(_ category: AbsenceOverrideCategory, from row: AbsencePerSubject) -> AbsencePerSubject? {
        let base = row.base - (category.contributesToBase ? 1 : 0)
        let late = row.late - (category == .late ? 1 : 0)
        let soon = row.soon - (category == .soon ? 1 : 0)
        let school = row.school - (category == .school ? 1 : 0)
        let distance = row.distanceTeaching - (category == .distanceTeaching ? 1 : 0)
        guard [base, late, soon, school, distance].allSatisfy({ $0 >= 0 }) else { return nil }
        return AbsencePerSubject(subjectName: row.subjectName, lessonsCount: row.lessonsCount,
            base: base, late: late, soon: soon, school: school, distanceTeaching: distance)
    }
}
