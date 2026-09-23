import Foundation

/// A single gradable mark projected onto the subject's running-average timeline.
struct AverageTimelineEntry: Identifiable, Equatable {
    let markID: String
    let date: Date
    let markValue: Double
    let weight: Double
    let runningAverage: Double
    let band: GradeBand

    var id: String { markID }
}

/// Builds a running weighted-average series from a subject's own marks, so the
/// detail chart works even without cloud grade history.
enum AverageTimeline {
    static func entries(for subject: Subject, prepared: PreparedGradeCalculation? = nil) -> [AverageTimelineEntry] {
        let calculation = prepared ?? GradeMath.prepare(subject)
        let samples = calculation.marks.compactMap { mark -> (PreparedGradeMark, Date)? in
            guard let date = mark.date else { return nil }
            return (mark, date)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 < rhs.1
        }
        var totalWeight = 0.0
        var weightedSum = 0.0
        return samples.map { mark, date in
            totalWeight += mark.weight.value
            weightedSum += mark.value * mark.weight.value
            return AverageTimelineEntry(
                markID: mark.id,
                date: date,
                markValue: mark.value,
                weight: mark.weight.value,
                runningAverage: weightedSum / totalWeight,
                band: GradeMath.band(for: mark.value)
            )
        }
    }
}
