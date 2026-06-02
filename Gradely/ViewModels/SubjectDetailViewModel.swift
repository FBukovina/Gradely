import Foundation
import Observation

@MainActor
@Observable
final class SubjectDetailViewModel {
    let subject: Subject
    let absence: AbsencePerSubject?

    var theoreticalMark = ""
    var theoreticalWeight = 1

    init(subject: Subject, absence: AbsencePerSubject?) {
        self.subject = subject
        self.absence = absence
    }

    var currentAverage: Double? {
        GradeMath.subjectAverage(subject)
    }

    var averageFormatted: String {
        GradeMath.formattedAverage(currentAverage)
    }

    var sortedMarks: [Mark] {
        subject.marks.sorted { lhs, rhs in
            (MarkDateFormatter.date(from: lhs.markDate) ?? .distantPast) > (MarkDateFormatter.date(from: rhs.markDate) ?? .distantPast)
        }
    }

    var theoreticalAverage: Double? {
        guard let value = GradeMath.parseMarkValue(theoreticalMark), !theoreticalMark.isEmpty else {
            return nil
        }
        return GradeMath.theoreticalAverage(
            existingMarks: subject.marks,
            markValue: value,
            weight: theoreticalWeight
        )
    }

    var theoreticalDifference: Double? {
        guard let theoreticalAverage, let currentAverage else { return nil }
        return theoreticalAverage - currentAverage
    }

    func updateTheoreticalMark(_ newValue: String) {
        guard newValue.count <= 3 else { return }
        theoreticalMark = newValue
    }

    func decrementWeight() {
        theoreticalWeight = max(1, theoreticalWeight - 1)
    }

    func incrementWeight() {
        theoreticalWeight = min(10, theoreticalWeight + 1)
    }
}
