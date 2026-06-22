import Foundation

enum GradeBand: Equatable {
    case excellent
    case good
    case average
    case poor
    case neutral
}

enum MarkWeightSource: Equatable {
    case explicit
    case inferred
    case fallback
}

struct ResolvedMarkWeight: Equatable {
    let value: Double
    let source: MarkWeightSource
}

enum GradeMath {
    private static let maximumAverageInferenceGroups = 4
    private static let markWeightRange = 1...10
    private static let averageDisplayPrecision = 100.0

    static func parseMarkValue(_ markText: String) -> Double? {
        switch markText.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1": 1.0
        case "1+": 1.3
        case "1-": 1.7
        case "2": 2.0
        case "2+": 2.3
        case "2-": 2.7
        case "3": 3.0
        case "3+": 3.3
        case "3-": 3.7
        case "4": 4.0
        case "4+": 4.3
        case "4-": 4.7
        case "5": 5.0
        case "5+": 5.3
        case "5-": 5.7
        default:
            Double(markText.replacingOccurrences(of: ",", with: "."))
        }
    }

    static func weightedAverage(for marks: [Mark]) -> Double? {
        weightedAverage(for: marks, resolvedWeights: resolvedWeights(for: marks))
    }

    private static func weightedAverage(
        for marks: [Mark],
        resolvedWeights: [String: ResolvedMarkWeight]
    ) -> Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0

        for mark in marks where isLocallyGradableMark(mark) {
            guard let value = parseMarkValue(mark.markText) else { continue }
            let weight = resolvedWeights[mark.id]?.value ?? 1
            totalWeight += weight
            weightedSum += value * weight
        }

        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    static func subjectAverage(_ subject: Subject) -> Double? {
        if let apiAverage = parseAverageText(subject.averageText) {
            return apiAverage
        }
        return weightedAverage(for: subject.marks, resolvedWeights: resolvedWeights(for: subject))
    }

    /// Study average across subjects: the mean of each subject's average, ignoring subjects without one.
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
        var totalWeight = Double(max(1, weight))
        var weightedSum = markValue * totalWeight
        let resolvedWeights = resolvedWeights(for: existingMarks, matchingAverageText: subjectAverageText)

        for mark in existingMarks where isLocallyGradableMark(mark) {
            guard let value = parseMarkValue(mark.markText) else { continue }
            let markWeight = resolvedWeights[mark.id]?.value ?? 1
            totalWeight += markWeight
            weightedSum += value * markWeight
        }

        return weightedSum / totalWeight
    }

    static func resolvedWeight(for mark: Mark, in subject: Subject) -> ResolvedMarkWeight {
        resolvedWeights(for: subject)[mark.id] ?? defaultResolvedWeight(for: mark)
    }

    static func resolvedWeights(for subject: Subject) -> [String: ResolvedMarkWeight] {
        resolvedWeights(for: subject.marks, matchingAverageText: subject.averageText)
    }

    static func resolvedWeights(
        for marks: [Mark],
        matchingAverageText averageText: String? = nil
    ) -> [String: ResolvedMarkWeight] {
        var resolved = Dictionary(
            uniqueKeysWithValues: marks.compactMap { mark -> (String, ResolvedMarkWeight)? in
                guard let explicitWeight = explicitWeightValue(mark.weight) else { return nil }
                return (mark.id, ResolvedMarkWeight(value: explicitWeight, source: .explicit))
            }
        )

        for mark in marks where isHiddenGradableMark(mark) && resolved[mark.id] == nil {
            guard let inferredWeight = sameLabelExplicitWeight(for: mark, in: marks) else { continue }
            resolved[mark.id] = ResolvedMarkWeight(value: inferredWeight, source: .inferred)
        }

        if let targetAverage = parseAverageText(averageText) {
            let knownWeights = resolved.mapValues(\.value)
            let inferredByLabel = averageInferredWeights(
                for: marks,
                knownWeightsByID: knownWeights,
                targetAverage: targetAverage
            )

            for mark in marks where isHiddenGradableMark(mark) && resolved[mark.id] == nil {
                guard
                    let label = averageInferenceLabel(for: mark),
                    let inferredWeight = inferredByLabel[label]
                else {
                    continue
                }
                resolved[mark.id] = ResolvedMarkWeight(value: Double(inferredWeight), source: .inferred)
            }
        }

        return resolved
    }

    static func parseAverageText(_ averageText: String?) -> Double? {
        guard let averageText else { return nil }
        let normalized = averageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        return Double(normalized)
    }

    static func formattedAverage(_ average: Double?) -> String {
        guard let average else { return "-" }
        return String(format: "%.2f", locale: Locale.current, average)
    }

    static func formattedWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), weight)
    }

    static func band(for average: Double?) -> GradeBand {
        guard let average else { return .neutral }
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
        guard let weight else { return nil }
        return max(0.0001, weight)
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

        guard totalWeight > 0 else { return nil }
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
