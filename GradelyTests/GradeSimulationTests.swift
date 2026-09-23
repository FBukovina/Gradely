import Foundation
import Testing
@testable import Gradely

@MainActor
struct GradeSimulationTests {
    @Test func preparationPreservesFractionalWeightsAndSeparatesOfficialAverage() throws {
        let prepared = GradeMath.prepare(subject([
            mark("1", weight: 0.5, id: "a"), mark("3", weight: 1.5, id: "b")
        ], average: "2,70"))
        #expect(prepared.calculatedAverage == 2.5)
        #expect(prepared.officialAverage == 2.7)
        #expect(prepared.displayAverage == 2.7)
        #expect(prepared.issues.contains(.inconsistentOfficialAverage))
        #expect(prepared.confidence == .estimated)
        let result = try #require(GradeMath.simulate(prepared, adding: [HypotheticalGrade(value: 1, weight: 1)]))
        #expect(abs(result.estimatedAverage - 2) < 0.00001)
        #expect(result.difference == -0.5)
    }

    @Test func knownWeightsAndOrdinaryGradesHaveExactArithmetic() {
        let prepared = GradeMath.prepare(subject([mark("1", weight: 1), mark("3", weight: 3, id: "b")], average: "2,50"))
        #expect(prepared.calculatedAverage == 2.5)
        #expect(prepared.confidence == .exact)
        #expect(prepared.issues.isEmpty)
        #expect(GradeMath.prepare(subject([mark("1-", weight: 1)])).issues.contains(.modifierMapping))
    }

    @Test func unsupportedValuesAndInvalidWeightsCannotPoisonArithmetic() {
        let prepared = GradeMath.prepare(subject([
            mark("2", weight: 2), mark("5", weight: 0, id: "zero"),
            mark("1", weight: -1, id: "negative"), mark("3", weight: .infinity, id: "infinite"),
            mark("NaN", weight: 1, id: "nan"), mark("85", weight: 1, id: "pointsArtifact"),
            mark("4", weight: 1, id: "unsupported", type: "unsupported"),
            mark("5", weight: 1, id: "points", isPoints: true)
        ]))
        #expect(prepared.marks.count == 1)
        #expect(prepared.calculatedAverage == 2)
        #expect(prepared.excludedMarkCount == 7)
        #expect(prepared.issues.contains(.invalidWeights))
        #expect(prepared.issues.contains(.excludedMarks))
        #expect(GradeMath.parseMarkValue("inf") == nil)
        #expect(GradeMath.parseAverageText("NaN") == nil)
        #expect(GradeMath.formattedAverage(.infinity) == "-")
        #expect(GradeMath.formattedWeight(.infinity) == "-")
    }

    @Test func duplicateRecordsCountOnceAndConflictingIDsAreExcluded() {
        let original = mark("2", weight: 3)
        let duplicate = GradeMath.prepare(subject([original, original]))
        #expect(duplicate.totalWeight == 3)
        #expect(duplicate.marks.count == 1)
        #expect(duplicate.issues.contains(.duplicateMarks))
        let conflict = GradeMath.prepare(subject([original, mark("5", weight: 3), mark("1", weight: 1, id: "safe")]))
        #expect(conflict.marks.map(\.id) == ["safe"])
        #expect(conflict.calculatedAverage == 1)
        #expect(conflict.issues.contains(.conflictingDuplicateIDs))
    }

    @Test func malformedOrNonfiniteOfficialAveragesDoNotReplaceTheLocalBaseline() {
        for text in ["NaN", "  nan\n", "inf", "-infinity", "  ", "2 3", "2\t3"] {
            let prepared = GradeMath.prepare(subject([mark("3", weight: 1)], average: text))
            #expect(prepared.officialAverage == nil)
            #expect(prepared.displayAverage == 3)
        }
        #expect(GradeMath.parseAverageText(" \n2,50\t") == 2.5)
    }

    @Test func missingIdentifiersAreDeterministicAcrossDecodingAndReadFlags() throws {
        let payload = """
        {"MarkDate":"2026-09-10T10:00:00+02:00","MarkText":"2","Type":"grade","SubjectId":"math","Weight":"1,5"}
        """
        let first = try JSONDecoder().decode(Mark.self, from: Data(payload.utf8))
        let second = try JSONDecoder().decode(Mark.self, from: Data(payload.utf8))
        #expect(first.id == second.id)
        #expect(first.id.hasPrefix("local-mark-"))
        #expect(!first.hasStableProviderID)
        #expect(first.weight == 1.5)
        #expect(mark("2", weight: 1, id: "").id == mark("2", weight: 1, id: "").id)
    }

    @Test func revisionIgnoresOrderAndProviderReadFlagsButTracksGradeEdits() {
        let a = mark("1", weight: 1)
        let b = mark("3", weight: 1, id: "b")
        #expect(GradeMath.revision(for: subject([a, b])) == GradeMath.revision(for: subject([b, a])))
        #expect(GradeMath.revision(for: subject([a])) == GradeMath.revision(for: subject([mark("1", weight: 1, isNew: true)])))
        #expect(GradeMath.revision(for: subject([a])) != GradeMath.revision(for: subject([mark("2", weight: 1)])))
    }

    @Test func targetSolverRanksFewestGradesThenLeastDemandingGrade() throws {
        let prepared = GradeMath.prepare(subject([mark("3", weight: 1)]))
        let result = GradeMath.targetOptions(for: prepared, targetAverage: 2.6)
        #expect(result.status == .options)
        #expect(result.options.map(\.grade) == [2, 1])
        #expect(result.options.allSatisfy { $0.count == 1 })
        for option in result.options {
            let grades = (0..<option.count).map { _ in HypotheticalGrade(value: Double(option.grade), weight: option.weight) }
            let simulation = try #require(GradeMath.simulate(prepared, adding: grades))
            #expect(simulation.estimatedAverage <= 2.6)
            #expect(simulation.estimatedAverage == option.estimatedAverage)
        }
    }

    @Test func targetDoesNotUseRoundedDisplayOrInferWeightFromCurrentAverage() {
        let light = GradeMath.prepare(subject([mark("3", weight: 1)]))
        let heavy = GradeMath.prepare(subject([mark("3", weight: 10)]))
        let lightResult = GradeMath.targetOptions(for: light, targetAverage: 2.49)
        let heavyResult = GradeMath.targetOptions(for: heavy, targetAverage: 2.49)
        #expect(lightResult.options.first?.count == 1)
        #expect(heavyResult.options.first?.count == 4)
        #expect(lightResult.options.first(where: { $0.grade == 2 })?.count == 2)
        let boundary = GradeMath.prepare(subject([mark("2.494", weight: 1)]))
        #expect(GradeMath.targetOptions(for: boundary, targetAverage: 2.49).status == .options)
    }

    @Test func targetEqualityUsesTheUnroundedForwardCalculation() throws {
        let atTarget = GradeMath.prepare(subject([mark("2.5", weight: 1)]))
        #expect(GradeMath.targetOptions(for: atTarget, targetAverage: 2.5).status == .alreadyReached)
        let justAbove = GradeMath.prepare(subject([mark("2.500000001", weight: 1)]))
        #expect(GradeMath.targetOptions(for: justAbove, targetAverage: 2.5).status == .options)
        let baseline = GradeMath.prepare(subject([mark("3", weight: 1)]))
        let equality = try #require(GradeMath.targetOptions(for: baseline, targetAverage: 2.5).options.first)
        #expect(equality.grade == 2)
        #expect(equality.count == 1)
        #expect(equality.estimatedAverage == 2.5)
    }

    @Test func targetOptionsForwardVerifyFractionalAndInferredBaselines() throws {
        let baselines = [
            GradeMath.prepare(subject([mark("2", weight: 0.5), mark("4", weight: 1.5, id: "b")])),
            GradeMath.prepare(subject([mark("1", weight: 1), mark("5", weight: nil, id: "b", note: "Test")], average: "3.67"))
        ]
        for prepared in baselines {
            let originalWeights = prepared.resolvedWeights
            for target in [1.49, 2.49, 2.5, 3.49] {
                for weight in [1, 3, 10] {
                    for option in GradeMath.targetOptions(for: prepared, targetAverage: target, weight: weight).options {
                        let additions = (0..<option.count).map { _ in HypotheticalGrade(value: Double(option.grade), weight: option.weight) }
                        let result = try #require(GradeMath.simulate(prepared, adding: additions))
                        #expect(result.estimatedAverage == option.estimatedAverage)
                        #expect(result.estimatedAverage <= target)
                        #expect(prepared.resolvedWeights == originalWeights)
                    }
                }
            }
        }
    }

    @Test func targetReturnsHonestUnavailableReachedAndUnreachableStates() {
        let empty = GradeMath.prepare(subject([]))
        #expect(GradeMath.targetOptions(for: empty, targetAverage: 2.49).status == .unavailable)
        #expect(GradeMath.targetOptions(for: GradeMath.prepare(subject([mark("2", weight: 1)])), targetAverage: 2.49).status == .alreadyReached)
        let hard = GradeMath.prepare(subject([mark("5", weight: 100)]))
        #expect(GradeMath.targetOptions(for: hard, targetAverage: 1).status == .unreachable)
        #expect(GradeMath.targetOptions(for: hard, targetAverage: .nan).status == .invalidTarget)
        #expect(GradeMath.targetOptions(for: hard, targetAverage: 6).status == .invalidTarget)
        #expect(GradeMath.targetOptions(for: hard, targetAverage: 2.49, weight: 0).status == .invalidTarget)
        #expect(GradeMath.targetOptions(for: GradeMath.prepare(subject([], average: "2.70")), targetAverage: 2.49).status == .unavailable)
    }

    @Test func simulationBoundsAndMultipleWeightsAreEnforced() throws {
        let prepared = GradeMath.prepare(subject([mark("3", weight: 2)]))
        let result = try #require(GradeMath.simulate(prepared, adding: [HypotheticalGrade(value: 1, weight: 2), HypotheticalGrade(value: 2, weight: 1)]))
        #expect(result.estimatedAverage == 2)
        #expect(prepared.totalWeight == 2)
        #expect(GradeMath.simulate(prepared, adding: (0..<11).map { _ in HypotheticalGrade() }) == nil)
        #expect(GradeMath.simulate(prepared, adding: [HypotheticalGrade(value: .nan)]) == nil)
        #expect(GradeMath.simulate(prepared, adding: [HypotheticalGrade(value: 1, weight: 0)]) == nil)
        let repeated = HypotheticalGrade()
        #expect(GradeMath.simulate(prepared, adding: [repeated, repeated]) == nil)
    }

    @Test func timelineAndContributionShareResolvedWeights() throws {
        let subject = subject([mark("1", weight: 1, id: "a"), mark("5", weight: nil, id: "b", note: "Large test")], average: "3.67")
        let prepared = GradeMath.prepare(subject)
        #expect(prepared.resolvedWeights["b"]?.value == 2)
        #expect(prepared.confidence == .estimated)
        #expect(AverageTimeline.entries(for: subject, prepared: prepared).last?.runningAverage == prepared.calculatedAverage)
        #expect(prepared.averageWithout(markID: "b") == 1)
        #expect(abs(try #require(prepared.impact(of: "b")) - (8.0 / 3.0)) < 0.0001)
        #expect(prepared.impact(of: "missing") == nil)
    }

    private func subject(_ marks: [Mark], average: String? = nil) -> Subject {
        Subject(marks: marks, subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Mathematics"), averageText: average)
    }

    private func mark(_ value: String, weight: Double?, id: String = "a", type: String = "grade", isPoints: Bool = false, isNew: Bool = false, note: String? = nil) -> Mark {
        Mark(markDate: "2026-09-10T10:00:00+02:00", markText: value, type: type, typeNote: note, weight: weight, subjectID: "math", isNew: isNew, isPoints: isPoints, id: id)
    }
}
