import SwiftUI

struct SubjectDetailView: View {
    @State private var viewModel: SubjectDetailViewModel

    init(viewModel: SubjectDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AverageHero(viewModel: viewModel)
                chartSection
                calculatorSection
                marksSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(viewModel.subject.trimmedName)
        .gradelyNavigationTitleDisplayMode(.large)
    }

    private var marksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("detail.marks.section")

            VStack(spacing: 0) {
                ForEach(Array(viewModel.sortedMarks.enumerated()), id: \.element.id) { index, mark in
                    MarkRow(mark: mark, resolvedWeight: viewModel.resolvedWeight(for: mark))
                        .accessibilityIdentifier("markRow-\(mark.id)")

                    if index < viewModel.sortedMarks.count - 1 {
                        Divider()
                            .padding(.leading, Spacing.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.gradelySecondaryGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if viewModel.chartSource != .none {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("detail.chart.title")
                Card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        AverageHistoryChart(
                            points: viewModel.chartPoints,
                            band: GradeMath.band(for: viewModel.currentAverage),
                            style: .detail,
                            overlayMarks: viewModel.averageTimeline
                        )
                        .frame(height: 180)

                        HStack {
                            Text(sourceCaption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if let delta = viewModel.chartDelta {
                                Text(String(format: "%+.2f", delta))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(delta > 0 ? GradeBand.poor.foregroundColor : Brand.primary)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("subjectGradeTrendSection")
        }
    }

    private var sourceCaption: String {
        viewModel.chartSource == .cloud
            ? AppL10n.string("detail.chart.source.cloud")
            : AppL10n.string("detail.chart.source.local")
    }

    private var calculatorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("detail.calculator.section")
            TheoreticalCalculatorView(viewModel: viewModel)
        }
    }
}

// MARK: - Average hero

private struct AverageHero: View {
    let viewModel: SubjectDetailViewModel

    var body: some View {
        let band = GradeMath.band(for: viewModel.currentAverage)

        VStack(spacing: Spacing.md) {
            Text("detail.average.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text(viewModel.averageFormatted)
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            HStack(spacing: Spacing.sm) {
                heroChip(
                    String.localizedStringWithFormat(
                        AppL10n.string("subject.markCount"),
                        viewModel.subject.marks.count
                    ),
                    systemImage: "checkmark.seal.fill"
                )

                if let absence = viewModel.absence {
                    heroChip(
                        String.localizedStringWithFormat(
                            AppL10n.string("detail.absence.percent"),
                            absence.absencePercentage
                        ),
                        systemImage: "calendar"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background(band.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: band.foregroundColor.opacity(0.22), radius: 10, x: 0, y: 6)
    }

    private func heroChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: Spacing.xs) {
            GradelyIcon(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(.white.opacity(0.22), in: Capsule())
    }
}

// MARK: - Mark row

private struct MarkRow: View {
    let mark: Mark
    let resolvedWeight: ResolvedMarkWeight

    var body: some View {
        let band = GradeMath.band(for: mark)

        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(mark.displayCaption)
                    .font(.headline)
                    .lineLimit(2)

                if mark.shouldShowTheme, let theme = mark.theme {
                    Text(theme.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.sm - 1) {
                    Text(MarkDateFormatter.relativeDate(mark.markDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.primary)

                    Text(MarkDateFormatter.fullDate(mark.markDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.sm) {
                    StatusChip(
                        text: (mark.typeNote?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                            ?? mark.type,
                        color: .secondary
                    )

                    if !mark.isPoints, resolvedWeight.source == .explicit, resolvedWeight.value > 1 {
                        StatusChip(
                            text: String.localizedStringWithFormat(
                                AppL10n.string("detail.weight.decimal"),
                                GradeMath.formattedWeight(resolvedWeight.value)
                            ),
                            color: Brand.secondary
                        )
                    }

                    if !mark.isPoints, resolvedWeight.source == .inferred, resolvedWeight.value > 1 {
                        StatusChip(
                            text: String.localizedStringWithFormat(
                                AppL10n.string("detail.weight.estimated.decimal"),
                                GradeMath.formattedWeight(resolvedWeight.value)
                            ),
                            color: Brand.secondary
                        )
                    }

                    if mark.isPoints, let maxPoints = mark.maxPoints {
                        StatusChip(
                            text: "\(mark.markText)/\(maxPoints)",
                            color: .teal
                        )
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            GradeBadge(text: mark.markText, band: band, size: .regular)
        }
        .padding(Spacing.md)
    }
}

// MARK: - Theoretical calculator

private struct TheoreticalCalculatorView: View {
    @Bindable var viewModel: SubjectDetailViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                TextField(AppL10n.string("detail.calculator.mark.placeholder"), text: Binding(
                    get: { viewModel.theoreticalMark },
                    set: { viewModel.updateTheoreticalMark($0) }
                ))
                .gradelyKeyboardType(.numbersAndPunctuation)
                .brandField()
                .accessibilityIdentifier("theoreticalMarkField")

                weightControl

                if let theoreticalAverage = viewModel.theoreticalAverage {
                    ResultView(
                        theoreticalAverage: theoreticalAverage,
                        difference: viewModel.theoreticalDifference
                    )
                    .accessibilityIdentifier("theoreticalResultPanel")
                }
            }
        }
    }

    private var weightControl: some View {
        HStack(spacing: Spacing.md) {
            stepButton(systemImage: "minus", disabled: viewModel.theoreticalWeight <= 1) {
                viewModel.decrementWeight()
            }

            Text(String.localizedStringWithFormat(AppL10n.string("detail.weight"), viewModel.theoreticalWeight))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)

            stepButton(systemImage: "plus", disabled: viewModel.theoreticalWeight >= 10) {
                viewModel.incrementWeight()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.gradelyTertiaryFill)
        )
        .accessibilityIdentifier("theoreticalWeightStepper")
    }

    private func stepButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GradelyIcon(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Brand.primary))
                .frame(width: 36, height: 32)
                .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.sm - 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct ResultView: View {
    let theoreticalAverage: Double
    let difference: Double?

    var body: some View {
        let tint = differenceColor

        VStack(spacing: Spacing.xs) {
            Text(
                String.localizedStringWithFormat(
                    AppL10n.string("detail.calculator.newAverage"),
                    theoreticalAverage
                )
            )
            .font(.title3.bold())
            .monospacedDigit()

            if let differenceText {
                Text(differenceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var differenceColor: Color {
        guard let difference else { return .secondary }
        if difference < -0.01 { return GradeBand.excellent.foregroundColor }
        if difference > 0.01 { return GradeBand.poor.foregroundColor }
        return .secondary
    }

    private var differenceText: String? {
        guard let difference else { return nil }
        if difference < -0.01 {
            return String.localizedStringWithFormat(AppL10n.string("detail.calculator.better"), -difference)
        }
        if difference > 0.01 {
            return String.localizedStringWithFormat(AppL10n.string("detail.calculator.worse"), difference)
        }
        return AppL10n.string("detail.calculator.same")
    }
}

#Preview("Cloud trend") {
    NavigationStack {
        SubjectDetailView(
            viewModel: SubjectDetailViewModel(
                subject: PreviewData.subjects[0],
                absence: PreviewData.absenceResponse.absencesPerSubject[0],
                repository: SchoolRepository(
                    client: MockBakalariClient(),
                    sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
                    marksCache: InMemoryMarksCache()
                ),
                trend: PreviewData.subjectGradeTrends.first
            )
        )
    }
}

#Preview("Marks-derived chart") {
    NavigationStack {
        SubjectDetailView(
            viewModel: SubjectDetailViewModel(
                subject: PreviewData.subjects[0],
                absence: PreviewData.absenceResponse.absencesPerSubject[0],
                repository: SchoolRepository(
                    client: MockBakalariClient(),
                    sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
                    marksCache: InMemoryMarksCache()
                )
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Points only") {
    NavigationStack {
        SubjectDetailView(
            viewModel: SubjectDetailViewModel(
                subject: PreviewData.pointsOnlySubject,
                absence: nil,
                repository: SchoolRepository(
                    client: MockBakalariClient(),
                    sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
                    marksCache: InMemoryMarksCache()
                )
            )
        )
    }
}
