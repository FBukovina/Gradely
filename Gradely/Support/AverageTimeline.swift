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
    /// Values outside the Czech 1…5 scale (with +/- modifiers) are points or
    /// percent artifacts, not chartable grades.
    private static let gradableRange = 0.9...5.7

    static func entries(for subject: Subject) -> [AverageTimelineEntry] {
        let weights = GradeMath.resolvedWeights(for: subject)

        let samples: [(mark: Mark, date: Date, value: Double)] = subject.marks
            .compactMap { mark in
                guard !mark.isPoints,
                      mark.type != "unsupported",
                      let date = MarkDateFormatter.date(from: mark.markDate),
                      let value = GradeMath.parseMarkValue(mark.markText),
                      gradableRange.contains(value)
                else { return nil }
                return (mark, date, value)
            }
            .sorted {
                $0.date == $1.date ? $0.mark.id < $1.mark.id : $0.date < $1.date
            }

        var totalWeight = 0.0
        var weightedSum = 0.0

        return samples.map { sample in
            let weight = weights[sample.mark.id]?.value ?? 1
            totalWeight += weight
            weightedSum += sample.value * weight
            return AverageTimelineEntry(
                markID: sample.mark.id,
                date: sample.date,
                markValue: sample.value,
                weight: weight,
                runningAverage: weightedSum / totalWeight,
                band: GradeMath.band(for: sample.value)
            )
        }
    }
}
