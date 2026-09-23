import Foundation
import Testing
@testable import Gradely

struct AbsenceOverrideProjectionTests {
    private let scope = SchoolDataScope(rawValue: "student-one")

    @Test func mixedCategoriesSubtractOnlyTheirOwnCountersAndPreserveDenominator() {
        let day = makeDay(ok: 1, late: 1, school: 1)
        let rows = [makeSubject(base: 5, late: 3, school: 2)]
        let allocations = [allocation("ok", category: .ok), allocation("late", category: .late), allocation("school", category: .school)]
        let saved = makeOverride(day: day, allocations: allocations, hidden: ["ok", "school"])
        let raw = makeResponse(day: day, subjects: rows)
        let result = project(raw, saved)

        #expect(result.response.absences[0].ok == 0)
        #expect(result.response.absences[0].late == 1)
        #expect(result.response.absences[0].school == 0)
        #expect(result.absencesPerSubject[0].base == 4)
        #expect(result.absencesPerSubject[0].late == 3)
        #expect(result.absencesPerSubject[0].school == 1)
        #expect(result.absencesPerSubject[0].lessonsCount == 20)
        #expect(result.metadata.hiddenCount == 2)
        #expect(raw.absences == [day])
        #expect(raw.absencesPerSubject == rows)
        #expect(project(raw, saved) == result) // Repeated projection cannot compound subtraction.
    }

    @Test func fullDayHidingRemovesDailyAndMonthlyRowsAndRestoreUsesRawData() {
        let day = makeDay(ok: 2)
        let saved = makeOverride(day: day, allocations: [allocation("one"), allocation("two")], hidden: ["one", "two"])
        let raw = makeResponse(day: day, subjects: [makeSubject(base: 4)])
        let result = project(raw, saved)
        #expect(result.response.absences.isEmpty)
        #expect(AbsenceSummary.monthSummaries(for: result.response.absences).isEmpty)
        #expect(result.absencesPerSubject[0].base == 2)
        #expect(result.absencesPerSubject[0].lessonsCount == 20)
        let restored = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: raw.absencesPerSubject, overrides: [], scope: scope)
        #expect(restored.response == raw)
    }

    @Test func providerCountChangePausesWholeOverrideAndPauseIsSticky() {
        let day = makeDay(ok: 2)
        let saved = makeOverride(day: day, allocations: [allocation("one"), allocation("two")], hidden: ["one"])
        let changed = makeResponse(day: makeDay(ok: 1), subjects: [makeSubject(base: 3)])
        let paused = project(changed, saved)
        #expect(paused.response == changed)
        #expect(paused.metadata.reviewOverrides.first?.pauseReason == .dayChanged)
        #expect(paused.metadata.hiddenCount == 0)
        let original = makeResponse(day: day, subjects: [makeSubject(base: 4)])
        let afterRevert = AbsenceOverrideProjection.project(rawResponse: original, rawSubjects: original.absencesPerSubject,
            overrides: paused.reconciledOverrides, scope: scope)
        #expect(afterRevert.response == original)
        #expect(afterRevert.metadata.reviewOverrides.first?.pauseReason == .dayChanged)
    }

    @Test func missingDayPausesAndWrongScopeIsIgnored() {
        let saved = makeOverride(day: makeDay(ok: 1), allocations: [allocation("one")], hidden: ["one"])
        let empty = AbsenceResponse(percentageThreshold: 25, absences: [], absencesPerSubject: [])
        #expect(project(empty, saved).metadata.reviewOverrides.first?.pauseReason == .dayMissing)
        let other = AbsenceOverrideProjection.project(rawResponse: empty, rawSubjects: [], overrides: [saved], scope: SchoolDataScope(rawValue: "student-two"))
        #expect(other.metadata == .empty)
        #expect(other.reconciledOverrides.isEmpty)
    }

    @Test func duplicateNormalizedSubjectsAndMissingCategoryAllocationCannotApply() {
        let day = makeDay(ok: 1)
        let saved = makeOverride(day: day, allocations: [allocation("one")], hidden: ["one"])
        let duplicated = makeResponse(day: day, subjects: [makeSubject(base: 2), makeSubject(name: "  MATEMATIKA  ", base: 2)])
        #expect(project(duplicated, saved).metadata.reviewOverrides.first?.pauseReason == .subjectMappingChanged)
        let missingAllocation = makeOverride(day: makeDay(ok: 2), allocations: [allocation("one")], hidden: ["one"])
        let raw = makeResponse(day: makeDay(ok: 2), subjects: [makeSubject(base: 3)])
        #expect(project(raw, missingAllocation).metadata.reviewOverrides.first?.pauseReason == .invalidAllocation)
    }

    @Test func insufficientAggregatePausesWithoutApplyingEvenDailyHalfOfEdit() {
        let day = makeDay(ok: 2)
        let saved = makeOverride(day: day, allocations: [allocation("one"), allocation("two")], hidden: ["one", "two"])
        let raw = makeResponse(day: day, subjects: [makeSubject(base: 1)])
        let result = project(raw, saved)
        #expect(result.response == raw)
        #expect(result.absencesPerSubject == raw.absencesPerSubject)
        #expect(result.metadata.reviewOverrides.first?.pauseReason == .insufficientSubjectCount)
    }

    @Test func unhiddenOriginalSubjectMissingFromOfficialRowsDoesNotBlockReliableHiddenSubject() {
        let day = makeDay(ok: 2)
        let biology = AbsenceOverrideAllocation(id: "biology", subjectName: "Biologie", category: .ok)
        let saved = makeOverride(day: day, allocations: [allocation("math"), biology], hidden: ["math"])
        let raw = makeResponse(day: day, subjects: [makeSubject(base: 3)])
        let result = project(raw, saved)
        #expect(result.metadata.hiddenCount == 1)
        #expect(result.metadata.reviewOverrides.isEmpty)
        #expect(result.response.absences[0].ok == 1)
        #expect(result.absencesPerSubject[0].base == 2)
    }

    @Test func knownChangedTimetableLessonPausesButUnavailableTimetableDoesNotInventConflict() {
        let day = makeDay(ok: 1)
        let original = AbsenceOverrideAllocation(id: "one", lessonID: "lesson-1", subjectKey: "raw-math", subjectName: "Matematika", category: .ok)
        let saved = makeOverride(day: day, allocations: [original], hidden: ["one"])
        let raw = makeResponse(day: day, subjects: [makeSubject(base: 1)])
        #expect(project(raw, saved).metadata.hiddenCount == 1)
        let result = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: raw.absencesPerSubject,
            overrides: [saved], scope: scope, currentLessonsByDate: [saved.dateKey: []])
        #expect(result.metadata.reviewOverrides.first?.pauseReason == .lessonMappingChanged)
    }

    @Test func manualSubjectWithoutDenominatorRemainsUnknown() {
        let day = makeDay(ok: 1)
        let saved = makeOverride(day: day, allocations: [allocation("one")], hidden: ["one"])
        let result = project(makeResponse(day: day, subjects: []), saved)
        #expect(result.metadata.hiddenCount == 1)
        #expect(result.response.absences.isEmpty)
        #expect(result.absencesPerSubject.isEmpty)
        #expect(result.response.absencesPerSubject.isEmpty)
    }

    @Test func completeRawAllocationAvoidsFullDayToPartialDayTrap() throws {
        let day = makeDay(ok: 2)
        let raw = makeResponse(day: day, subjects: [])
        let allocations = [
            AbsenceOverrideAllocation(id: "math", lessonID: "lesson-2026-02-02-1-raw-math", subjectKey: "raw-math", subjectName: "Matematika", category: .ok),
            AbsenceOverrideAllocation(id: "czech", lessonID: "lesson-2026-02-02-2-raw-czech", subjectKey: "raw-czech", subjectName: "Český jazyk", category: .ok)
        ]
        let saved = makeOverride(day: day, allocations: allocations, hidden: ["math"])
        let baseline = AbsenceSubjectFallback.makeAbsenceResult(from: raw, timetableResponses: [timetable], subjects: [],
            manualAllocationsByDate: AbsenceOverrideProjection.manualAllocations(for: [saved], rawResponse: raw, scope: scope))
        #expect(baseline.unresolvedPartialDays.isEmpty)
        #expect(baseline.absences.map(\.base).reduce(0, +) == 2)
        let result = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: baseline.absences,
            subjectStableIDHints: baseline.stableIDHints, overrides: [saved], scope: scope)
        #expect(result.response.absences[0].ok == 1)
        #expect(result.absencesPerSubject.first { $0.subjectName == "Matematika" }?.base == 0)
        #expect(result.absencesPerSubject.first { $0.subjectName == "Český jazyk" }?.base == 1)
        #expect(result.absencesPerSubject.allSatisfy { $0.lessonsCount == 1 })
        #expect(result.metadata.reviewOverrides.isEmpty)
    }

    @Test func manualAllocationResolvesOriginalPartialDayBeforeHiddenProjection() {
        let day = makeDay(ok: 1)
        let raw = makeResponse(day: day, subjects: [])
        let saved = makeOverride(day: day, allocations: [allocation("one")], hidden: ["one"])
        let unresolved = AbsenceSubjectFallback.makeAbsenceResult(from: raw, timetableResponses: [timetable], subjects: [])
        #expect(unresolved.unresolvedPartialDays.count == 1)
        let original = AbsenceSubjectFallback.makeAbsenceResult(from: raw, timetableResponses: [timetable], subjects: [],
            manualAllocationsByDate: AbsenceOverrideProjection.manualAllocations(for: [saved], rawResponse: raw, scope: scope))
        #expect(original.unresolvedPartialDays.isEmpty)
        #expect(original.absences.first { $0.subjectName == "Matematika" }?.base == 1)
        let result = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: original.absences,
            subjectStableIDHints: original.stableIDHints, overrides: [saved], scope: scope)
        #expect(result.metadata.hiddenCount == 1)
        #expect(result.absencesPerSubject.allSatisfy { $0.base == 0 })
    }

    @Test func travelingAcrossTimeZonesDoesNotChangeCandidateIdentityOrPauseSavedLesson() throws {
        let rawDay = makeDay(ok: 1)
        let raw = makeResponse(day: rawDay, subjects: [])
        let lessonID = "lesson-2026-02-02-1-raw-math"
        let saved = makeOverride(day: rawDay, allocations: [AbsenceOverrideAllocation(id: "math", lessonID: lessonID,
            subjectKey: "raw-math", subjectName: "Matematika", category: .ok)], hidden: ["math"])
        for identifier in ["America/Los_Angeles", "Europe/Prague", "Pacific/Kiritimati"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 2)))
            let candidates = AbsenceTimetableLessonResolver.candidates(on: date, in: timetable, subjects: [], calendar: calendar)
            #expect(candidates.contains { $0.id == lessonID })
            let baseline = AbsenceSubjectFallback.makeAbsenceResult(from: raw, timetableResponses: [timetable], subjects: [],
                manualAllocationsByDate: AbsenceOverrideProjection.manualAllocations(for: [saved], rawResponse: raw, scope: scope),
                validDateRange: date...date, calendar: calendar)
            #expect(baseline.absences.first { $0.subjectName == "Matematika" }?.base == 1)
            let result = AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: baseline.absences,
                subjectStableIDHints: baseline.stableIDHints, overrides: [saved], scope: scope,
                currentLessonsByDate: ["2026-02-02": candidates])
            #expect(result.metadata.reviewOverrides.isEmpty)
            #expect(result.metadata.hiddenCount == 1)
        }
    }

    private func project(_ raw: AbsenceResponse, _ saved: AbsenceDayOverride) -> AbsenceOverrideProjection.Result {
        AbsenceOverrideProjection.project(rawResponse: raw, rawSubjects: raw.absencesPerSubject, overrides: [saved], scope: scope)
    }
    private func makeOverride(day: AbsenceDay, allocations: [AbsenceOverrideAllocation], hidden: Set<String>) -> AbsenceDayOverride {
        AbsenceDayOverride(scope: scope, dateKey: "2026-02-02", baselineDay: day, allocations: allocations, hiddenAllocationIDs: hidden)
    }
    private func allocation(_ id: String, category: AbsenceOverrideCategory = .ok) -> AbsenceOverrideAllocation {
        AbsenceOverrideAllocation(id: id, subjectName: "Matematika", category: category)
    }
    private func makeDay(ok: Int, late: Int = 0, school: Int = 0) -> AbsenceDay {
        AbsenceDay(date: "2026-02-02T00:00:00+01:00", unsolved: 0, ok: ok, missed: 0, late: late, soon: 0, school: school, distanceTeaching: 0)
    }
    private func makeSubject(name: String = "Matematika", base: Int, late: Int = 0, school: Int = 0) -> AbsencePerSubject {
        AbsencePerSubject(subjectName: name, lessonsCount: 20, base: base, late: late, soon: 0, school: school, distanceTeaching: 0)
    }
    private func makeResponse(day: AbsenceDay, subjects: [AbsencePerSubject]) -> AbsenceResponse {
        AbsenceResponse(percentageThreshold: 25, absences: [day], absencesPerSubject: subjects)
    }
    private var timetable: TimetableResponse {
        TimetableResponse(hours: [TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
            TimetableHour(id: 2, caption: "2", beginTime: "8:55", endTime: "9:40")],
            days: [TimetableDayDTO(atoms: [TimetableAtom(hourID: 1, subjectID: "math"), TimetableAtom(hourID: 2, subjectID: "czech")],
                dayOfWeek: 1, date: "2026-02-02T00:00:00+01:00")],
            subjects: [TimetableEntity(id: "math", abbrev: "M", name: "Matematika"), TimetableEntity(id: "czech", abbrev: "ČJ", name: "Český jazyk")])
    }
}
