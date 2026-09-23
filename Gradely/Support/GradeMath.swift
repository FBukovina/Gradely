import CryptoKit
import Foundation

enum GradeBand: Equatable, Sendable {
    case excellent
    case good
    case average
    case poor
    case neutral
}

enum MarkWeightSource: Equatable, Sendable {
    case explicit
    case inferred
    case fallback
}

struct ResolvedMarkWeight: Equatable, Sendable {
    let value: Double
    let source: MarkWeightSource
}

enum GradeMath {
    private static let maximumAverageInferenceGroups = 4
    private static let markWeightRange = 1...10
    private static let averageDisplayPrecision = 100.0

    static let maximumHypotheticalGrades = 10
    private static let supportedGradeRange = 1.0...5.7

    static func parseMarkValue(_ markText: String) -> Double? {
        let text = markText.trimmingCharacters(in: .whitespacesAndNewlines)
        let modifiers: [String: Double] = [
            "1+": 1.3, "1-": 1.7, "2+": 2.3, "2-": 2.7,
            "3+": 3.3, "3-": 3.7, "4+": 4.3, "4-": 4.7,
            "5+": 5.3, "5-": 5.7
        ]
        guard let value = modifiers[text] ?? Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }

    /// Changes only when a subject's calculation/timeline inputs change.
    /// Provider read flags and record ordering do not invalidate prepared work.
    static func revision(for subject: Subject) -> String {
        digest([
            subject.id, subject.pointsOnly ? "points" : "grades",
            subject.averageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            subject.marks.map(canonicalRecord).sorted().joined(separator: "\u{1E}")
        ])
    }

    /// The same identity comparison is shared with local observation continuity.
    /// Read flags and provider bookkeeping timestamps cannot create grade edits.
    static func revision(for mark: Mark) -> String {
        canonicalRecord(mark)
    }

    static func prepare(_ subject: Subject) -> PreparedGradeCalculation {
        var issues = Set<GradeCalculationIssue>()
        var excludedCount = 0
        var uniqueMarks: [Mark] = []
        let groups = Dictionary(grouping: subject.marks) { $0.id.isEmpty ? localIdentity(for: $0) : $0.id }
        for identity in groups.keys.sorted() {
            guard let group = groups[identity], let first = group.first else { continue }
            if group.count > 1 {
                issues.insert(.duplicateMarks)
                guard Set(group.map(canonicalRecord)).count == 1 else {
                    issues.insert(.conflictingDuplicateIDs)
                    excludedCount += group.count
                    continue
                }
                excludedCount += group.count - 1
            }
            guard !subject.pointsOnly, isLocallyGradableMark(first),
                  let value = parseMarkValue(first.markText), supportedGradeRange.contains(value) else {
                excludedCount += 1
                issues.insert(.excludedMarks)
                continue
            }
            if let weight = first.weight, explicitWeightValue(weight) == nil {
                excludedCount += 1
                issues.insert(.invalidWeights)
                continue
            }
            if !first.hasStableProviderID { issues.insert(.missingMarkIdentifiers) }
            uniqueMarks.append(first)
        }
        // Resolve once for the full immutable input. Never infer anew after adding
        // a hypothetical grade or removing a grade to calculate its impact.
        let weights = resolveWeightsForUniqueMarks(uniqueMarks, matchingAverageText: subject.averageText)
        var sum = 0.0
        var totalWeight = 0.0
        var preparedMarks: [PreparedGradeMark] = []
        for mark in uniqueMarks {
            guard let value = parseMarkValue(mark.markText) else { continue }
            let weight = weights[mark.id] ?? ResolvedMarkWeight(value: 1, source: .fallback)
            let modifier = mark.markText.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("+")
                || mark.markText.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("-")
            switch weight.source {
            case .explicit: break
            case .inferred: issues.insert(.inferredWeights)
            case .fallback: issues.insert(.missingWeights)
            }
            if modifier { issues.insert(.modifierMapping) }
            let nextSum = sum + value * weight.value
            let nextWeight = totalWeight + weight.value
            guard nextSum.isFinite, nextWeight.isFinite else {
                issues.insert(.invalidWeights)
                excludedCount += 1
                continue
            }
            sum = nextSum
            totalWeight = nextWeight
            preparedMarks.append(PreparedGradeMark(
                id: mark.id.isEmpty ? localIdentity(for: mark) : mark.id,
                date: MarkDateFormatter.date(from: mark.markDate),
                value: value,
                weight: weight,
                usesModifierMapping: modifier
            ))
        }
        let calculated = totalWeight > 0 ? sum / totalWeight : nil
        let official = parseAverageText(subject.averageText)
        if let calculated, let official, !matchesDisplayedAverage(calculated, official) {
            issues.insert(.inconsistentOfficialAverage)
        }
        if preparedMarks.isEmpty { issues.insert(.noRecordedGrades) }
        let confidence: GradeCalculationConfidence = preparedMarks.isEmpty ? .unavailable : (issues.isEmpty ? .exact : .estimated)
        return PreparedGradeCalculation(
            subjectID: subject.id,
            revision: revision(for: subject),
            marks: preparedMarks,
            weightedSum: sum,
            totalWeight: totalWeight,
            calculatedAverage: calculated,
            officialAverage: official,
            confidence: confidence,
            issues: issues.sorted { $0.rawValue < $1.rawValue },
            excludedMarkCount: excludedCount
        )
    }

    static func simulate(_ prepared: PreparedGradeCalculation, adding grades: [HypotheticalGrade]) -> GradeSimulationResult? {
        guard grades.count <= maximumHypotheticalGrades,
              Set(grades.map(\.id)).count == grades.count,
              grades.allSatisfy({ $0.value.isFinite && supportedGradeRange.contains($0.value) && (1...10).contains($0.weight) })
        else { return nil }
        let sum = grades.reduce(prepared.weightedSum) { $0 + $1.value * Double($1.weight) }
        let weight = grades.reduce(prepared.totalWeight) { $0 + Double($1.weight) }
        guard sum.isFinite, weight.isFinite, weight > 0 else { return nil }
        let average = sum / weight
        guard average.isFinite else { return nil }
        return GradeSimulationResult(
            baselineAverage: prepared.calculatedAverage,
            estimatedAverage: average,
            difference: prepared.calculatedAverage.map { average - $0 },
            confidence: prepared.confidence == .unavailable ? .estimated : prepared.confidence,
            issues: prepared.issues
        )
    }

    /// Each option repeats one ordinary grade at the user's chosen weight.
    /// The <= target comparison uses unrounded arithmetic, never display text.
    static func targetOptions(
        for prepared: PreparedGradeCalculation,
        targetAverage: Double,
        weight: Int = 1,
        maximumCount: Int = 10
    ) -> GradeTargetResult {
        func result(_ status: GradeTargetResult.Status, _ options: [GradeTargetOption] = []) -> GradeTargetResult {
            GradeTargetResult(status: status, options: options, confidence: prepared.confidence)
        }
        guard targetAverage.isFinite, (1.0...5.0).contains(targetAverage), (1...10).contains(weight), maximumCount > 0 else {
            return result(.invalidTarget)
        }
        guard let current = prepared.calculatedAverage, prepared.canSimulate else { return result(.unavailable) }
        if current <= targetAverage { return result(.alreadyReached) }
        var options: [GradeTargetOption] = []
        for grade in 1...5 {
            for count in 1...min(maximumCount, maximumHypotheticalGrades) {
                let additions = (0..<count).map { _ in HypotheticalGrade(value: Double(grade), weight: weight) }
                if let simulation = simulate(prepared, adding: additions), simulation.estimatedAverage <= targetAverage {
                    options.append(GradeTargetOption(grade: grade, count: count, weight: weight,
                                                    estimatedAverage: simulation.estimatedAverage))
                    break
                }
            }
        }
        options.sort { $0.count == $1.count ? $0.grade > $1.grade : $0.count < $1.count }
        return result(options.isEmpty ? .unreachable : .options, Array(options.prefix(3)))
    }

    // Compatibility entry points use the same prepared arithmetic as new consumers.
    static func weightedAverage(for marks: [Mark]) -> Double? {
        prepare(calculationSubject(marks: marks)).calculatedAverage
    }

    static func subjectAverage(_ subject: Subject) -> Double? {
        if let official = parseAverageText(subject.averageText) { return official }
        return prepare(subject).calculatedAverage
    }

    /// Study average across subjects is a mean of subject averages, not of all marks.
    static func overallAverage(for subjects: [Subject]) -> Double? {
        let averages = subjects.compactMap { subjectAverage($0) }
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    static func theoreticalAverage(
        existingMarks: [Mark],
        subjectAverageText: String? = nil,
        markValue: Double,
        weight: Int
    ) -> Double {
        let prepared = prepare(calculationSubject(marks: existingMarks, averageText: subjectAverageText))
        return simulate(prepared, adding: [HypotheticalGrade(value: markValue, weight: min(10, max(1, weight)))])?.estimatedAverage
            ?? prepared.calculatedAverage ?? 0
    }

    static func resolvedWeight(for mark: Mark, in subject: Subject) -> ResolvedMarkWeight {
        prepare(subject).resolvedWeights[mark.id] ?? defaultResolvedWeight(for: mark)
    }

    static func resolvedWeights(for subject: Subject) -> [String: ResolvedMarkWeight] {
        prepare(subject).resolvedWeights
    }

    static func resolvedWeights(for marks: [Mark], matchingAverageText averageText: String? = nil) -> [String: ResolvedMarkWeight] {
        prepare(calculationSubject(marks: marks, averageText: averageText)).resolvedWeights
    }

    private static func calculationSubject(marks: [Mark], averageText: String? = nil) -> Subject {
        Subject(marks: marks, subjectInfo: SubjectInfo(id: "calculation", abbrev: "", name: ""), averageText: averageText)
    }

    private static func resolveWeightsForUniqueMarks(_ marks: [Mark], matchingAverageText averageText: String?) -> [String: ResolvedMarkWeight] {
        var resolved: [String: ResolvedMarkWeight] = [:]
        for mark in marks {
            if let weight = explicitWeightValue(mark.weight) {
                resolved[mark.id] = ResolvedMarkWeight(value: weight, source: .explicit)
            }
        }
        for mark in marks where isHiddenGradableMark(mark) && resolved[mark.id] == nil {
            guard let weight = sameLabelExplicitWeight(for: mark, in: marks) else { continue }
            resolved[mark.id] = ResolvedMarkWeight(value: weight, source: .inferred)
        }
        if let target = parseAverageText(averageText) {
            let inferred = averageInferredWeights(for: marks, knownWeightsByID: resolved.mapValues(\.value), targetAverage: target)
            for mark in marks where isHiddenGradableMark(mark) && resolved[mark.id] == nil {
                guard let label = averageInferenceLabel(for: mark), let weight = inferred[label] else { continue }
                resolved[mark.id] = ResolvedMarkWeight(value: Double(weight), source: .inferred)
            }
        }
        return resolved
    }

    private static func canonicalRecord(_ mark: Mark) -> String {
        // Length-prefixed hashing avoids ambiguity when captions contain separators.
        digest([
            mark.id, mark.subjectID, mark.markDate, mark.markText.trimmingCharacters(in: .whitespacesAndNewlines),
            mark.type, mark.typeNote ?? "", mark.caption ?? "", mark.theme ?? "",
            mark.weight.map { String($0) } ?? "nil", mark.isPoints ? "points" : "grade",
            mark.pointsText ?? "", mark.maxPoints.map(String.init) ?? ""
        ])
    }

    private static func localIdentity(for mark: Mark) -> String { "local-mark-" + canonicalRecord(mark) }

    private static func digest(_ values: [String]) -> String {
        let input = values.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func parseAverageText(_ averageText: String?) -> Double? {
        guard let averageText else { return nil }
        let normalized = averageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    static func formattedAverage(_ average: Double?) -> String {
        guard let average, average.isFinite else { return "-" }
        return String(format: "%.2f", locale: Locale.current, average)
    }

    static func formattedWeight(_ weight: Double) -> String {
        guard weight.isFinite else { return "-" }
        if weight.rounded() == weight, weight < Double(Int.max), weight > Double(Int.min) {
            return String(Int(weight))
        }
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), weight)
    }

    static func band(for average: Double?) -> GradeBand {
        guard let average, average.isFinite else { return .neutral }
        if average <= 1.5 { return .excellent }
        if average <= 2.5 { return .good }
        if average <= 3.5 { return .average }
        return .poor
    }

    static func band(for mark: Mark) -> GradeBand {
        guard !mark.isPoints else { return .excellent }
        switch mark.markText.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1", "1+", "1-": return .excellent
        case "2", "2+", "2-": return .good
        case "3", "3+", "3-": return .average
        case "4", "4+", "4-", "5", "5+", "5-": return .poor
        default: return .neutral
        }
    }

    private static func defaultResolvedWeight(for mark: Mark) -> ResolvedMarkWeight {
        if let explicitWeight = explicitWeightValue(mark.weight) {
            return ResolvedMarkWeight(value: explicitWeight, source: .explicit)
        }
        return ResolvedMarkWeight(value: 1, source: .fallback)
    }

    private static func explicitWeightValue(_ weight: Double?) -> Double? {
        guard let weight, weight.isFinite, weight > 0 else { return nil }
        return weight
    }

    private static func isHiddenGradableMark(_ mark: Mark) -> Bool {
        mark.weight == nil && isLocallyGradableMark(mark) && parseMarkValue(mark.markText) != nil
    }

    private static func isLocallyGradableMark(_ mark: Mark) -> Bool {
        !mark.isPoints && mark.type != "unsupported"
    }

    private static func sameLabelExplicitWeight(for mark: Mark, in marks: [Mark]) -> Double? {
        guard let labelKind = MarkLabelKind.primaryKind(for: mark),
              let label = labelKind.normalizedLabel(for: mark)
        else {
            return nil
        }

        let matchingWeights = Set(
            marks.compactMap { candidate -> Double? in
                guard candidate.id != mark.id,
                      !candidate.isPoints,
                      labelKind.normalizedLabel(for: candidate) == label
                else {
                    return nil
                }
                return explicitWeightValue(candidate.weight)
            }
        )

        return matchingWeights.count == 1 ? matchingWeights.first : nil
    }

    private static func averageInferredWeights(
        for marks: [Mark],
        knownWeightsByID: [String: Double],
        targetAverage: Double
    ) -> [String: Int] {
        let labels = orderedHiddenLabels(for: marks, knownWeightsByID: knownWeightsByID)
        guard !labels.isEmpty, labels.count <= maximumAverageInferenceGroups else {
            return [:]
        }

        var matches: [[String: Int]] = []
        var candidateWeights: [String: Int] = [:]

        func search(labelIndex: Int) {
            guard matches.count <= 1 else { return }

            if labelIndex == labels.count {
                guard
                    let candidateAverage = weightedAverage(
                        for: marks,
                        knownWeightsByID: knownWeightsByID,
                        candidateWeightsByLabel: candidateWeights
                    ),
                    matchesDisplayedAverage(candidateAverage, targetAverage)
                else {
                    return
                }
                matches.append(candidateWeights)
                return
            }

            let label = labels[labelIndex]
            for weight in markWeightRange {
                candidateWeights[label] = weight
                search(labelIndex: labelIndex + 1)
            }
            candidateWeights[label] = nil
        }

        search(labelIndex: 0)
        return matches.count == 1 ? matches[0] : [:]
    }

    private static func orderedHiddenLabels(
        for marks: [Mark],
        knownWeightsByID: [String: Double]
    ) -> [String] {
        var seen: Set<String> = []
        var labels: [String] = []

        for mark in marks where isHiddenGradableMark(mark) && knownWeightsByID[mark.id] == nil {
            guard let label = averageInferenceLabel(for: mark), !seen.contains(label) else {
                continue
            }
            seen.insert(label)
            labels.append(label)
        }

        return labels
    }

    private static func weightedAverage(
        for marks: [Mark],
        knownWeightsByID: [String: Double],
        candidateWeightsByLabel: [String: Int]
    ) -> Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0

        for mark in marks where isLocallyGradableMark(mark) {
            guard let value = parseMarkValue(mark.markText) else { continue }

            let weight: Double
            if let explicitWeight = explicitWeightValue(mark.weight) {
                weight = explicitWeight
            } else if let knownWeight = knownWeightsByID[mark.id] {
                weight = knownWeight
            } else if let label = averageInferenceLabel(for: mark),
                      let candidateWeight = candidateWeightsByLabel[label] {
                weight = Double(candidateWeight)
            } else {
                weight = 1
            }

            totalWeight += weight
            weightedSum += value * weight
        }

        guard totalWeight.isFinite, weightedSum.isFinite, totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    private static func matchesDisplayedAverage(_ candidateAverage: Double, _ targetAverage: Double) -> Bool {
        (candidateAverage * averageDisplayPrecision).rounded()
            == (targetAverage * averageDisplayPrecision).rounded()
    }

    private static func averageInferenceLabel(for mark: Mark) -> String? {
        MarkLabelKind.primaryKind(for: mark)?.normalizedLabel(for: mark)
    }
}

private enum MarkLabelKind: CaseIterable {
    case typeNote
    case type
    case caption

    func normalizedLabel(for mark: Mark) -> String? {
        switch self {
        case .typeNote:
            return Self.normalized(mark.typeNote)
        case .type:
            return Self.normalized(mark.type)
        case .caption:
            return Self.normalized(mark.caption)
        }
    }

    static func primaryKind(for mark: Mark) -> MarkLabelKind? {
        allCases.first { $0.normalizedLabel(for: mark) != nil }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}
