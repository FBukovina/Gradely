import Foundation

/// Describes the arithmetic inputs, never certainty about a teacher's final grade.
enum GradeCalculationConfidence: String, Equatable, Sendable {
    case exact
    case estimated
    case unavailable
}

enum GradeCalculationIssue: String, Equatable, Hashable, Sendable {
    case inferredWeights
    case missingWeights
    case modifierMapping
    case excludedMarks
    case invalidWeights
    case duplicateMarks
    case conflictingDuplicateIDs
    case inconsistentOfficialAverage
    case missingMarkIdentifiers
    case noRecordedGrades
}

struct PreparedGradeMark: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date?
    let value: Double
    let weight: ResolvedMarkWeight
    let usesModifierMapping: Bool
}

/// A single immutable baseline shared by the simulator, timeline and insights.
struct PreparedGradeCalculation: Equatable, Sendable {
    let subjectID: String
    let revision: String
    let marks: [PreparedGradeMark]
    let weightedSum: Double
    let totalWeight: Double
    let calculatedAverage: Double?
    let officialAverage: Double?
    let confidence: GradeCalculationConfidence
    let issues: [GradeCalculationIssue]
    let excludedMarkCount: Int

    var displayAverage: Double? { officialAverage ?? calculatedAverage }
    var canSimulate: Bool { calculatedAverage != nil && totalWeight > 0 }
    var resolvedWeights: [String: ResolvedMarkWeight] {
        Dictionary(uniqueKeysWithValues: marks.map { ($0.id, $0.weight) })
    }

    func averageWithout(markID: String) -> Double? {
        guard let mark = marks.first(where: { $0.id == markID }) else { return nil }
        let remainingWeight = totalWeight - mark.weight.value
        guard remainingWeight > 0 else { return nil }
        let result = (weightedSum - mark.value * mark.weight.value) / remainingWeight
        return result.isFinite ? result : nil
    }

    /// Counterfactual effect using the same resolved weights, not observed history.
    func impact(of markID: String) -> Double? {
        guard let calculatedAverage, let without = averageWithout(markID: markID) else { return nil }
        return calculatedAverage - without
    }
}

struct HypotheticalGrade: Identifiable, Equatable, Sendable {
    var id: UUID
    var value: Double
    var weight: Int

    init(id: UUID = UUID(), value: Double = 1, weight: Int = 1) {
        self.id = id
        self.value = value
        self.weight = weight
    }
}

struct GradeSimulationResult: Equatable, Sendable {
    let baselineAverage: Double?
    let estimatedAverage: Double
    let difference: Double?
    let confidence: GradeCalculationConfidence
    let issues: [GradeCalculationIssue]
}

struct GradeTargetOption: Identifiable, Equatable, Sendable {
    let grade: Int
    let count: Int
    let weight: Int
    let estimatedAverage: Double

    var id: String { "\(grade)-\(count)-\(weight)" }
}

struct GradeTargetResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case options
        case alreadyReached
        case unreachable
        case unavailable
        case invalidTarget
    }

    let status: Status
    let options: [GradeTargetOption]
    let confidence: GradeCalculationConfidence
}
