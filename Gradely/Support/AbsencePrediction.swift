import Foundation

struct AbsencePredictionResult: Equatable {
    let currentTotal: AbsenceCounts
    let projectedTotal: AbsenceCounts
    let addedHours: Int
    let subjectRows: [AbsencePredictionSubjectRow]

    var hasSelection: Bool {
        addedHours > 0
    }
}

struct AbsencePredictionSubjectRow: Identifiable, Equatable {
    let id: String
    let subjectName: String
    let addedHours: Int
    let currentBase: Int?
    let projectedBase: Int?
    let currentLessonsCount: Int?
    let projectedLessonsCount: Int?
    let currentPercentage: Double?
    let projectedPercentage: Double?
    let exceedsThreshold: Bool
    let crossesThreshold: Bool

    var hasBaseline: Bool {
        currentBase != nil
            && projectedBase != nil
            && currentLessonsCount != nil
            && projectedLessonsCount != nil
            && currentPercentage != nil
            && projectedPercentage != nil
    }
}

enum AbsencePrediction {
    static func project(
        currentTotalCounts: AbsenceCounts,
        subjectRows: [AbsenceSubjectSummary],
        selectedLessons: [AbsenceLessonCandidate],
        threshold: Double?
    ) -> AbsencePredictionResult {
        let uniqueLessons = selectedLessonsByID(selectedLessons)
        var projectedTotal = currentTotalCounts
        projectedTotal.ok += uniqueLessons.count

        let normalizedThreshold = normalizedThreshold(threshold)
        let rows = Dictionary(grouping: uniqueLessons, by: \.subjectKey)
            .map { subjectKey, lessons -> AbsencePredictionSubjectRow in
                let sortedLessons = lessons.sorted(by: lessonSort)
                let sample = sortedLessons[0]
                let baseline = baselineRow(
                    for: sample,
                    subjectKey: subjectKey,
                    in: subjectRows
                )
                let addedHours = sortedLessons.count

                guard let baseline else {
                    return AbsencePredictionSubjectRow(
                        id: subjectKey,
                        subjectName: sample.subjectName,
                        addedHours: addedHours,
                        currentBase: nil,
                        projectedBase: nil,
                        currentLessonsCount: nil,
                        projectedLessonsCount: nil,
                        currentPercentage: nil,
                        projectedPercentage: nil,
                        exceedsThreshold: false,
                        crossesThreshold: false
                    )
                }

                let projectedBase = baseline.base + addedHours
                let projectedLessonsCount = baseline.lessonsCount + addedHours
                let projectedPercentage = projectedLessonsCount > 0
                    ? Double(projectedBase) / Double(projectedLessonsCount) * 100
                    : 0
                let exceedsThreshold = normalizedThreshold > 0 && projectedPercentage >= normalizedThreshold
                let currentlyExceedsThreshold = normalizedThreshold > 0 && baseline.absencePercentage >= normalizedThreshold

                return AbsencePredictionSubjectRow(
                    id: baseline.stableID,
                    subjectName: baseline.subjectName,
                    addedHours: addedHours,
                    currentBase: baseline.base,
                    projectedBase: projectedBase,
                    currentLessonsCount: baseline.lessonsCount,
                    projectedLessonsCount: projectedLessonsCount,
                    currentPercentage: baseline.absencePercentage,
                    projectedPercentage: projectedPercentage,
                    exceedsThreshold: exceedsThreshold,
                    crossesThreshold: !currentlyExceedsThreshold && exceedsThreshold
                )
            }
            .sorted { lhs, rhs in
                if lhs.exceedsThreshold != rhs.exceedsThreshold {
                    return lhs.exceedsThreshold && !rhs.exceedsThreshold
                }
                if lhs.projectedPercentage != rhs.projectedPercentage {
                    return (lhs.projectedPercentage ?? -1) > (rhs.projectedPercentage ?? -1)
                }
                return lhs.subjectName.localizedCaseInsensitiveCompare(rhs.subjectName) == .orderedAscending
            }

        return AbsencePredictionResult(
            currentTotal: currentTotalCounts,
            projectedTotal: projectedTotal,
            addedHours: uniqueLessons.count,
            subjectRows: rows
        )
    }

    static func selectedLessonsByID(_ lessons: [AbsenceLessonCandidate]) -> [AbsenceLessonCandidate] {
        var seen: Set<String> = []
        return lessons
            .filter { seen.insert($0.id).inserted }
            .sorted(by: lessonSort)
    }

    private static func baselineRow(
        for lesson: AbsenceLessonCandidate,
        subjectKey: String,
        in rows: [AbsenceSubjectSummary]
    ) -> AbsenceSubjectSummary? {
        let safeSubjectKey = AbsenceTimetableLessonResolver.storageSafe(subjectKey)
        let lessonSubjectName = AbsenceTimetableLessonResolver.normalized(lesson.subjectName)

        return rows.first { row in
            row.stableID == subjectKey
                || row.stableID.hasSuffix("-\(safeSubjectKey)")
                || AbsenceTimetableLessonResolver.normalized(row.subjectName) == lessonSubjectName
        }
    }

    private static func lessonSort(
        _ lhs: AbsenceLessonCandidate,
        _ rhs: AbsenceLessonCandidate
    ) -> Bool {
        if lhs.dateKey != rhs.dateKey {
            return lhs.dateKey < rhs.dateKey
        }
        if lhs.hourID != rhs.hourID {
            return lhs.hourID < rhs.hourID
        }
        return lhs.subjectName.localizedCaseInsensitiveCompare(rhs.subjectName) == .orderedAscending
    }

    private static func normalizedThreshold(_ threshold: Double?) -> Double {
        guard let threshold else { return 0 }
        return threshold > 0 && threshold <= 1 ? threshold * 100 : threshold
    }
}
