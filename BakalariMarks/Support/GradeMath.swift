import Foundation

enum GradeBand: Equatable {
    case excellent
    case good
    case average
    case poor
    case neutral
}

enum GradeMath {
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
        var totalWeight = 0
        var weightedSum = 0.0

        for mark in marks where !mark.isPoints {
            guard let value = parseMarkValue(mark.markText) else { continue }
            let weight = mark.weight ?? 1
            totalWeight += weight
            weightedSum += value * Double(weight)
        }

        guard totalWeight > 0 else { return nil }
        return weightedSum / Double(totalWeight)
    }

    static func subjectAverage(_ subject: Subject) -> Double? {
        if let apiAverage = parseAverageText(subject.averageText) {
            return apiAverage
        }
        return weightedAverage(for: subject.marks)
    }

    /// Study average across subjects: the mean of each subject's average, ignoring subjects without one.
    static func overallAverage(for subjects: [Subject]) -> Double? {
        let averages = subjects.compactMap(subjectAverage)
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    static func theoreticalAverage(existingMarks: [Mark], markValue: Double, weight: Int) -> Double {
        var totalWeight = max(1, weight)
        var weightedSum = markValue * Double(totalWeight)

        for mark in existingMarks where !mark.isPoints {
            guard let value = parseMarkValue(mark.markText) else { continue }
            let markWeight = mark.weight ?? 1
            totalWeight += markWeight
            weightedSum += value * Double(markWeight)
        }

        return weightedSum / Double(totalWeight)
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
}
