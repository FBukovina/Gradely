import Observation
import SwiftUI

/// Report cards from Bakaláři: the written ones, newest first.
@MainActor @Observable
final class ReportCardViewModel {
    private(set) var terms: [ReportCardTerm] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let period: ReportCardPeriod
    private let repository: SchoolRepository

    init(repository: SchoolRepository, now: Date = Date()) {
        self.repository = repository
        period = ReportCardPeriod(containing: now)
        if let cached = repository.loadCachedFinalMarks() {
            terms = ReportCardTerm.sorted(cached.value.terms.map(ReportCardTerm.init))
        }
    }

    /// This semester's report card once the teachers start writing it.
    var currentTerm: ReportCardTerm? { terms.first { $0.matches(period) } }

    var pastTerms: [ReportCardTerm] { terms.filter { !$0.matches(period) && !$0.marks.isEmpty } }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await repository.loadFinalMarks()
            terms = ReportCardTerm.sorted(response.terms.map(ReportCardTerm.init))
            errorMessage = nil
        } catch {
            guard !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
}

enum ReportCardText {
    /// "1. pololetí 2026/27".
    static func term(semester: String, schoolYear: String) -> String {
        String(format: AppL10n.string("reportCard.term"), semester, schoolYear)
    }

    static func term(_ period: ReportCardPeriod) -> String {
        term(semester: String(period.semester), schoolYear: period.schoolYear)
    }

    /// "Na hraně · 0,04 od dvojky".
    static func borderline(_ borderline: ReportCardEstimate.Borderline) -> String {
        String(format: AppL10n.string("reportCard.borderline.\(borderline.mark)"), GradeMath.formattedAverage(borderline.distance))
    }

    static func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Marks row

/// The one row on Marks that opens the report card estimate.
struct MarksReportCardRow: View {
    let estimates: [ReportCardEstimate]
    let period: ReportCardPeriod

    var body: some View {
        PlainSection {
            NavigationLink(value: MarksRoute.reportCard) {
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("reportCard.title")
                            .font(.gradely(.headline))
                            .foregroundStyle(.primary)
                        Text(verbatim: summary)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Spacing.sm)
                    GradelyIcon(systemName: "chevron.right")
                        .font(.gradely(.caption).weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marksReportCardRow")
        }
    }

    private var summary: String {
        var parts = [ReportCardText.term(period)]
        if let average = ReportCardEstimate.average(of: estimates) {
            parts.append(String(format: AppL10n.string("reportCard.row.estimate"), GradeMath.formattedAverage(average)))
        }
        let borderline = estimates.filter { $0.borderline != nil }.count
        if borderline > 0 {
            parts.append(String.localizedStringWithFormat(AppL10n.string("reportCard.borderlineCount"), borderline))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Estimate

/// This semester's expected report card plus the ones already written.
struct ReportCardView: View {
    let subjects: [Subject]
    let prepared: [String: PreparedGradeCalculation]
    @State private var model: ReportCardViewModel

    init(subjects: [Subject], prepared: [String: PreparedGradeCalculation], repository: SchoolRepository) {
        self.subjects = subjects
        self.prepared = prepared
        _model = State(initialValue: ReportCardViewModel(repository: repository))
    }

    var body: some View {
        let estimates = ReportCardEstimate.estimates(subjects: subjects, prepared: prepared, written: model.currentTerm)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ReportCardHero(
                    label: "reportCard.hero.estimate",
                    average: ReportCardEstimate.average(of: estimates),
                    detail: ReportCardText.term(model.period)
                )

                PlainSection(footer: "reportCard.estimate.footer") {
                    PlainSectionTitle("reportCard.subjects")
                } content: {
                    ForEach(estimates) { estimate in
                        ReportCardEstimateRow(estimate: estimate)
                    }
                }

                pastSection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .refreshable { await model.load() }
        .navigationTitle(AppL10n.string("reportCard.title"))
        .gradelyNavigationTitleDisplayMode(.inline)
        .task { await model.load() }
        .accessibilityIdentifier("reportCardView")
    }

    @ViewBuilder
    private var pastSection: some View {
        let past = model.pastTerms
        PlainSection {
            PlainSectionTitle("reportCard.past")
        } content: {
            if past.isEmpty {
                if model.isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("reportCard.past.loading")
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = model.errorMessage {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verbatim: errorMessage)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(AppL10n.string("action.retry")) {
                            Task { await model.load() }
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.primary)
                    }
                } else {
                    Text("reportCard.past.empty")
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(past) { term in
                    NavigationLink(value: MarksRoute.reportCardTerm(term)) {
                        ReportCardTermRow(term: term)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reportCardTerm-\(term.id)")
                }
            }
        }
    }
}

private struct ReportCardHero: View {
    let label: LocalizedStringKey
    let average: Double?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(GradeMath.formattedAverage(average))
                    .font(.gradely(size: 52, weight: .bold).monospacedDigit())
                    .foregroundStyle(GradeMath.band(for: average).foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(verbatim: detail)
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reportCardHero")
    }
}

private struct ReportCardEstimateRow: View {
    let estimate: ReportCardEstimate

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: estimate.subjectName)
                    .font(.gradely(.headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(verbatim: detail)
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let borderline = estimate.borderline {
                    Text(verbatim: ReportCardText.borderline(borderline))
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(Color.gradelySystemOrange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: Spacing.sm)

            Text(verbatim: markText)
                .font(.gradely(.title2).weight(.bold).monospacedDigit())
                .foregroundStyle(band.foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reportCardEstimate-\(estimate.subjectID)")
    }

    private var markText: String {
        estimate.writtenMarkText ?? estimate.estimatedMark.map(String.init) ?? "–"
    }

    private var band: GradeBand {
        GradeMath.band(forMarkText: markText)
    }

    private var detail: String {
        let average = estimate.average.map { String(format: AppL10n.string("reportCard.row.average"), GradeMath.formattedAverage($0)) }
        if estimate.writtenMarkText != nil {
            return [AppL10n.string("reportCard.row.written"), average].compactMap { $0 }.joined(separator: " · ")
        }
        return average ?? AppL10n.string("reportCard.row.noMarks")
    }
}

private struct ReportCardTermRow: View {
    let term: ReportCardTerm

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: ReportCardText.term(semester: term.semester, schoolYear: term.schoolYear))
                    .font(.gradely(.headline))
                    .foregroundStyle(.primary)
                if let achievement = term.achievementText {
                    Text(verbatim: achievement)
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            if let average = term.average {
                Text(GradeMath.formattedAverage(average))
                    .font(.gradely(.title3).weight(.bold).monospacedDigit())
                    .foregroundStyle(GradeMath.band(for: average).foregroundColor)
            }

            GradelyIcon(systemName: "chevron.right")
                .font(.gradely(.caption).weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - A written report card

struct ReportCardTermView: View {
    let term: ReportCardTerm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ReportCardHero(
                    label: "reportCard.hero.written",
                    average: term.average,
                    detail: term.achievementText ?? ""
                )

                PlainSection(footer: absenceFooter) {
                    PlainSectionTitle("reportCard.subjects")
                } content: {
                    ForEach(term.marks) { mark in
                        HStack(spacing: Spacing.md) {
                            Text(verbatim: mark.subjectName)
                                .font(.gradely(.headline))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: Spacing.sm)
                            Text(verbatim: mark.markText)
                                .font(.gradely(.title3).weight(.bold).monospacedDigit())
                                .foregroundStyle(GradeMath.band(forMarkText: mark.markText).foregroundColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .navigationTitle(ReportCardText.term(semester: term.semester, schoolYear: term.schoolYear))
        .gradelyNavigationTitleDisplayMode(.inline)
        .accessibilityIdentifier("reportCardTermView")
    }

    private var absenceFooter: LocalizedStringKey? {
        guard let absent = term.absentHours else { return nil }
        let unexcused = term.unexcusedHours ?? 0
        return "reportCard.absence \(ReportCardText.hours(absent)) \(ReportCardText.hours(unexcused))"
    }
}
