import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsenceAdjustmentAcceptanceTests {
    private let scope = SchoolDataScope(rawValue: "absence-acceptance")

    @Test func categoryTitlesResolveLocalizedCopyInsteadOfDisplayingResourceKeys() {
        for category in AbsenceOverrideCategory.allCases {
            #expect(!category.localizedTitle.isEmpty)
            #expect(!category.localizedTitle.hasPrefix("absence.category."))
        }
    }

    @Test func hidingFlowsThroughMonthRiskAndPredictionWithoutChangingTaughtLessons() throws {
        let day = absenceDay("2026-02-02T00:00:00+01:00", count: 1)
        let raw = AbsenceResponse(percentageThreshold: 0.25, absences: [day], absencesPerSubject: [subject("Matematika", base: 10)])
        let projected = AbsenceOverrideProjection.project(
            rawResponse: raw, rawSubjects: raw.absencesPerSubject, subjectStableIDHints: [],
            overrides: [makeOverride(for: day)], scope: scope
        )

        #expect(projected.metadata.hiddenCount == 1)
        #expect(AbsenceSummary.totalCounts(for: projected.response.absences).total == 0)
        #expect(AbsenceSummary.monthSummaries(for: projected.response.absences).reduce(0) { $0 + $1.counts.total } == 0)
        let adjusted = try #require(projected.absencesPerSubject.first)
        #expect(adjusted.base == 9)
        #expect(adjusted.lessonsCount == 40)
        #expect(adjusted.absencePercentage == 22.5)

        let risk = try #require(AbsenceRiskSummary.make(response: projected.response, subjects: projected.absencesPerSubject).highestRisk)
        #expect(risk.level == .high)
        #expect(risk.missedLessons == 9)
        let nextLesson = AbsenceLessonCandidate(id: "future-math", dateKey: "2026-02-03", hourID: 1,
                                              hourCaption: "1", timeRange: "", subjectKey: "raw-math", subjectName: "Matematika")
        let prediction = AbsencePrediction.project(
            currentTotalCounts: AbsenceSummary.totalCounts(for: projected.response.absences),
            subjectRows: AbsenceSummary.subjectSummaries(for: projected.absencesPerSubject, threshold: 0.25),
            selectedLessons: [nextLesson], threshold: 0.25
        )
        let predictedSubject = try #require(prediction.subjectRows.first)
        #expect(prediction.currentTotal.total == 0)
        #expect(prediction.projectedTotal.total == 1)
        #expect(predictedSubject.currentBase == 9)
        #expect(predictedSubject.projectedBase == 10)
        #expect(predictedSubject.projectedLessonsCount == 41)
        #expect(!predictedSubject.exceedsThreshold)
        #expect(raw.absencesPerSubject.first?.base == 10)
        #expect(raw.absences.first?.ok == 1)
    }

    @Test func officialSubjectRowOrderCannotMoveCorrectionToAnotherSubject() throws {
        let day = absenceDay("2026-02-02", count: 1)
        let raw = AbsenceResponse(percentageThreshold: 25, absences: [day],
                                  absencesPerSubject: [subject("Český jazyk", base: 7), subject("Matematika", base: 10)])
        let first = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: raw.absencesPerSubject,
            subjectStableIDHints: [], overrides: [makeOverride(for: day)], scope: scope)
        let reordered = AbsenceResponse(percentageThreshold: 25, absences: [day], absencesPerSubject: raw.absencesPerSubject.reversed())
        let second = AbsenceOverrideProjection.project(rawResponse: reordered, rawSubjects: reordered.absencesPerSubject,
            subjectStableIDHints: [], overrides: first.reconciledOverrides, scope: scope)
        #expect(second.metadata.hiddenCount == 1)
        #expect(second.absencesPerSubject.first { $0.subjectName == "Matematika" }?.base == 9)
        #expect(second.absencesPerSubject.first { $0.subjectName == "Český jazyk" }?.base == 7)
    }

    @Test func providerCalendarDateRemainsTheOverrideIdentityAcrossUTCOffsets() {
        let original = absenceDay("2026-02-02T00:00:00+14:00", count: 1)
        let refreshed = absenceDay("2026-02-02T00:00:00-10:00", count: 1)
        let raw = AbsenceResponse(percentageThreshold: 25, absences: [refreshed], absencesPerSubject: [subject("Matematika", base: 10)])
        let projected = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: raw.absencesPerSubject,
            subjectStableIDHints: [], overrides: [makeOverride(for: original)], scope: scope)
        #expect(projected.metadata.hiddenCount == 1)
        #expect(projected.metadata.reviewOverrides.isEmpty)
    }

    private func makeOverride(for day: AbsenceDay) -> AbsenceDayOverride {
        let allocation = AbsenceOverrideAllocation(id: "math-1", lessonID: nil, subjectKey: nil,
                                                   subjectName: "Matematika", lessonTitle: "Matematika", category: .ok)
        return AbsenceDayOverride(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, scope: scope, dateKey: "2026-02-02", baselineDay: day,
                                  allocations: [allocation], hiddenAllocationIDs: [allocation.id],
                                  pauseReason: nil, savedAt: Date(timeIntervalSince1970: 1))
    }

    private func absenceDay(_ date: String, count: Int) -> AbsenceDay {
        AbsenceDay(date: date, unsolved: 0, ok: count, missed: 0, late: 0, soon: 0, school: 0, distanceTeaching: 0)
    }

    private func subject(_ name: String, base: Int) -> AbsencePerSubject {
        AbsencePerSubject(subjectName: name, lessonsCount: 40, base: base, late: 0, soon: 0, school: 0, distanceTeaching: 0)
    }
}
