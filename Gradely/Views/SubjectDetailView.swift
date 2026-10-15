import SwiftUI

struct SubjectDetailView: View {
    @State private var viewModel: SubjectDetailViewModel
    @Environment(\.requestGradeyAIAction) private var requestAI
    private let snapshotStore: SchoolSnapshotStore?
    private let navigationScope: SchoolDataScope?

    init(viewModel: SubjectDetailViewModel, snapshotStore: SchoolSnapshotStore? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.snapshotStore = snapshotStore
        self.navigationScope = snapshotStore?.scope
    }

    private var subjectUnavailable: Bool {
        guard let snapshotStore else { return false }
        return snapshotStore.scope != navigationScope || snapshotStore.subject(id: viewModel.subject.id) == nil
    }

    var body: some View {
        Group {
        if subjectUnavailable {
            ContentUnavailableView("detail.intelligence.subjectUnavailable", systemImage: "book.closed")
        } else {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AverageHero(viewModel: viewModel, hasLocalAbsenceAdjustment: hasLocalAbsenceAdjustment)
                marksSection
                calculatorSection
                chartSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        }
        }
        .gradelyScreenBackground()
        .scrollDismissesKeyboard(.interactively)
        .gradeySiriContext(.subject(viewModel.subject.id, navigationScope))
        .navigationTitle(subjectUnavailable ? AppL10n.string("detail.intelligence.subjectUnavailable") : viewModel.subject.trimmedName)
        .gradelyNavigationTitleDisplayMode(.large)
        .toolbar {
            if !subjectUnavailable {
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    GradeyAIToolbarButton { requestAI(.subjectHelp, viewModel.subject.id, nil) }
                }
            }
        }
        .onChange(of: snapshotStore?.revision, initial: true) { _, _ in
            if !subjectUnavailable { refreshSubjectSnapshot() }
        }
    }

    private var hasLocalAbsenceAdjustment: Bool {
        guard let snapshotStore, snapshotStore.scope == navigationScope,
              let absence = viewModel.absence else { return false }
        let name = AbsenceOverrideProjection.normalizedSubjectName(absence.subjectName)
        return snapshotStore.absence?.overrideMetadata.activeOverrides.contains { saved in
            saved.hiddenAllocations.contains { AbsenceOverrideProjection.normalizedSubjectName($0.subjectName) == name }
        } ?? false
    }

    private func refreshSubjectSnapshot() {
        guard let snapshotStore, snapshotStore.scope == navigationScope,
              let subject = snapshotStore.subject(id: viewModel.subject.id) else { return }
        viewModel.updateAbsence(SubjectsViewModel.matchingAbsence(for: subject, in: snapshotStore.absence?.absencesPerSubject ?? []))
        viewModel.updateSubject(
            subject,
            prepared: snapshotStore.preparedCalculations[subject.id],
            trend: snapshotStore.history.trends.first { $0.subjectID == subject.id }
        )
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
                        .frame(height: 220)

                        Divider()

                        HStack(spacing: Spacing.sm) {
                            GradelyIcon(systemName: viewModel.chartSource == .cloud ? "cloud.fill" : "chart.line.uptrend.xyaxis", size: 13)
                                .foregroundStyle(.secondary)
                            Text(sourceCaption)
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: Spacing.sm)

                            if let delta = viewModel.chartDelta {
                                AverageDeltaChip(delta: delta)
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
    let hasLocalAbsenceAdjustment: Bool

    var body: some View {
        let band = GradeMath.band(for: viewModel.currentAverage)

        VStack(spacing: Spacing.md) {
            Text(AppL10n.string(viewModel.preparedCalculation.officialAverage != nil
                ? "detail.intelligence.schoolAverage" : "detail.intelligence.calculatedAverage"))
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text(viewModel.averageFormatted)
                .font(.gradely(size: 64, weight: .bold).monospacedDigit())
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
            if hasLocalAbsenceAdjustment {
                GradelyLabel("absence.override.adjusted", systemImage: "eye.slash")
                    .font(.gradely(.caption))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("subjectAbsenceAdjusted")
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
                .font(.gradely(.caption2).weight(.bold))
            Text(text)
                .font(.gradely(.caption).weight(.semibold))
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

    @State private var isExpanded = false
    @State private var isCaptionTruncated = false
    @State private var isDescriptionTruncated = false

    private var canExpand: Bool {
        isExpanded || isCaptionTruncated || isDescriptionTruncated
    }

    var body: some View {
        let band = GradeMath.band(for: mark)

        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs + 2) {
                    TruncationAwareText(
                        text: mark.displayCaption,
                        lineLimit: 2,
                        isExpanded: isExpanded,
                        isTruncated: $isCaptionTruncated
                    )
                    .font(.gradely(.headline))

                    if mark.isNew {
                        Circle()
                            .fill(Brand.primary)
                            .frame(width: 7, height: 7)
                            .accessibilityElement()
                            .accessibilityLabel(AppL10n.string("New mark"))
                    }
                }

                if let description {
                    TruncationAwareText(
                        text: description,
                        lineLimit: 2,
                        isExpanded: isExpanded,
                        isTruncated: $isDescriptionTruncated
                    )
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                }

                metadataLine

                if !chips.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        ForEach(chips) { chip in
                            StatusChip(text: chip.text, color: chip.color)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: Spacing.sm)

            VStack(spacing: Spacing.sm) {
                GradeBadge(text: mark.markText, band: band, size: .regular)

                if canExpand {
                    GradelyIcon("arrow-down-01", size: 14)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
    }

    /// The topic, when it adds something beyond the caption.
    private var description: String? {
        guard mark.shouldShowTheme, let theme = mark.theme else { return nil }
        return theme.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The teacher's mark-type note ("Písemka", "Ústní zkoušení"). Provider
    /// type codes (`X`, `grade`, `points`) and symbols like `%` are internal and
    /// never shown, nor is a note that just repeats the caption.
    private var typeLabel: String? {
        guard let note = mark.typeNote?.trimmingCharacters(in: .whitespacesAndNewlines),
              note.count > 1, note.contains(where: \.isLetter),
              note.localizedCaseInsensitiveCompare(mark.displayCaption) != .orderedSame
        else { return nil }
        return note
    }

    private var isRecent: Bool {
        guard let date = MarkDateFormatter.date(from: mark.markDate) else { return false }
        return Date().timeIntervalSince(date) < 7 * 86_400
    }

    private var metadataLine: some View {
        HStack(spacing: Spacing.xs + 2) {
            if isRecent {
                Text(MarkDateFormatter.relativeDate(mark.markDate))
                    .font(.gradely(.caption).weight(.semibold))
                    .foregroundStyle(Brand.primary)
                separator
            }
            Text(MarkDateFormatter.fullDate(mark.markDate))
                .monospacedDigit()
            if let typeLabel {
                separator
                Text(typeLabel)
                    .lineLimit(1)
            }
        }
        .font(.gradely(.caption))
        .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(.tertiary)
    }

    private struct Chip: Identifiable {
        let text: String
        let color: Color
        var id: String { text }
    }

    private var chips: [Chip] {
        if mark.isPoints {
            guard let maxPoints = mark.maxPoints else { return [] }
            return [Chip(text: "\(mark.markText)/\(maxPoints)", color: .teal)]
        }
        guard resolvedWeight.value != 1 else { return [] }
        switch resolvedWeight.source {
        case .explicit:
            return [Chip(text: String.localizedStringWithFormat(
                AppL10n.string("detail.weight.decimal"),
                GradeMath.formattedWeight(resolvedWeight.value)
            ), color: Brand.secondary)]
        case .inferred:
            return [Chip(text: String.localizedStringWithFormat(
                AppL10n.string("detail.weight.estimated.decimal"),
                GradeMath.formattedWeight(resolvedWeight.value)
            ), color: Brand.secondary)]
        case .fallback:
            return []
        }
    }
}

/// Text clamped to `lineLimit` lines that reports whether the clamp actually
/// hides anything, so rows only offer to expand when there is more to read.
private struct TruncationAwareText: View {
    let text: String
    let lineLimit: Int
    let isExpanded: Bool
    @Binding var isTruncated: Bool

    var body: some View {
        Text(text)
            .lineLimit(isExpanded ? nil : lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                if !isExpanded {
                    // Offered the clamped height, the full text either fits
                    // (first branch) or falls through to the empty view.
                    ViewThatFits(in: .vertical) {
                        Text(text)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onAppear { isTruncated = false }
                        Color.clear
                            .onAppear { isTruncated = true }
                    }
                }
            }
    }
}

// MARK: - Average delta

/// Change of the average across the charted period, following the subject
/// list's convention: the arrow follows the sign, teal is better, rose worse.
private struct AverageDeltaChip: View {
    let delta: Double

    var body: some View {
        let color = delta > 0 ? GradeBand.poor.foregroundColor : Brand.primary

        HStack(spacing: 3) {
            GradelyIcon(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right", size: 12)
            Text(String(format: "%+.2f", locale: .current, delta))
                .font(.gradely(.caption).weight(.bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localizedStringWithFormat(
            AppL10n.string(delta > 0 ? "detail.intelligence.worsening" : "detail.intelligence.improving"),
            abs(delta)
        ))
    }
}

// MARK: - Theoretical calculator

private struct TheoreticalCalculatorView: View {
    @Bindable var viewModel: SubjectDetailViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if viewModel.preparedCalculation.canSimulate {
                    HStack(spacing: Spacing.sm) {
                        TextField(AppL10n.string("detail.calculator.mark.placeholder"), text: Binding(
                            get: { viewModel.theoreticalMark },
                            set: { viewModel.updateTheoreticalMark($0) }
                        ))
                        .gradelyKeyboardType(.numbersAndPunctuation)
                        .brandField()
                        .accessibilityIdentifier("theoreticalMarkField")

                        weightControl
                    }

                    if let theoreticalAverage = viewModel.theoreticalAverage {
                        ResultLine(theoreticalAverage: theoreticalAverage, difference: viewModel.theoreticalDifference)
                            .accessibilityIdentifier("theoreticalResultPanel")
                    }
                    if let warning = viewModel.calculationWarningKey {
                        Text(AppL10n.string(String.LocalizationValue(warning)))
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(AppL10n.string("detail.simulator.unavailable"))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weightControl: some View {
        HStack(spacing: Spacing.sm) {
            stepButton(systemImage: "minus", disabled: viewModel.theoreticalWeight <= 1) {
                viewModel.decrementWeight()
            }

            Text(String.localizedStringWithFormat(AppL10n.string("detail.weight"), viewModel.theoreticalWeight))
                .font(.gradely(.subheadline).weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()

            stepButton(systemImage: "plus", disabled: viewModel.theoreticalWeight >= 10) {
                viewModel.incrementWeight()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.gradelyTertiaryFill)
        )
        .fixedSize()
        .accessibilityIdentifier("theoreticalWeightStepper")
    }

    private func stepButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GradelyIcon(systemName: systemImage)
                .font(.gradely(.headline).weight(.bold))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Brand.primary))
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.sm - 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppL10n.string(systemImage == "minus" ? "detail.weight.decrease" : "detail.weight.increase"))
        .disabled(disabled)
    }
}

private struct ResultLine: View {
    let theoreticalAverage: Double
    let difference: Double?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(verbatim: "→ " + GradeMath.formattedAverage(theoreticalAverage))
                .font(.gradely(.headline).monospacedDigit())
            if let differenceText {
                Text(differenceText)
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(differenceColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [String.localizedStringWithFormat(AppL10n.string("detail.simulator.result"), theoreticalAverage), differenceText]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
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
