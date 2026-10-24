import SwiftUI

struct AbsenceView: View {
    @State private var viewModel: AbsenceViewModel
    private let snapshotStore: SchoolSnapshotStore?
    private let onOpenGradeyAI: () -> Void

    init(
        repository: SchoolRepository,
        snapshotStore: SchoolSnapshotStore? = nil,
        onOpenGradeyAI: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: AbsenceViewModel(repository: repository, snapshotStore: snapshotStore))
        self.snapshotStore = snapshotStore
        self.onOpenGradeyAI = onOpenGradeyAI
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(AppL10n.string("absence.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .gradelyTopBarLeading) {
                        GradeyAIToolbarButton(onOpen: onOpenGradeyAI)
                    }

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        Button {
                            Task { await viewModel.refresh(forceRefresh: true) }
                        } label: {
                            GradelyIcon(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                        }
                        .disabled(viewModel.isLoading || viewModel.isRefreshing)
                        .accessibilityLabel(AppL10n.string("action.refresh"))
                        .accessibilityIdentifier("absenceRefreshButton")
                    }

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        Button {
                            viewModel.isHiddenAbsencesSheetPresented = true
                        } label: {
                            GradelyIcon(systemName: "eye.slash")
                        }
                        .accessibilityLabel(AppL10n.string("absence.override.hiddenTitle"))
                        .accessibilityIdentifier("absenceHiddenButton")
                    }

                    #if !os(macOS)
                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        AccountSettingsButton()
                    }
                    #endif
                }
                .task {
                    await viewModel.loadIfNeeded()
                }
                .gradelyOnRefreshCommand { await viewModel.refresh(forceRefresh: true) }
                .onChange(of: snapshotStore?.revision) { _, _ in viewModel.applySharedSnapshot() }
                .sheet(isPresented: $viewModel.isHiddenAbsencesSheetPresented) {
                    HiddenAbsencesView(viewModel: viewModel)
                }
                .sheet(item: Binding(
                    get: { viewModel.isHiddenAbsencesSheetPresented ? nil : viewModel.editor },
                    set: { viewModel.editor = $0 }
                )) { editor in
                    AbsenceOverrideEditorView(viewModel: editor)
                }
                .sheet(isPresented: $viewModel.isManualSelectionSheetPresented) {
                    ManualAbsenceLessonSelectionSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPredictionSheetPresented) {
                    AbsencePredictionSheet(viewModel: viewModel)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.response == nil {
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text("absence.loading")
            }
            .accessibilityIdentifier("absenceLoadingView")
        } else if let errorMessage = viewModel.errorMessage, viewModel.response == nil {
            ContentUnavailableView {
                GradelyLabel(AppL10n.string("error.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(AppL10n.string("action.retry")) {
                    Task { await viewModel.refresh(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("absenceErrorView")
        } else {
            absenceContent
        }
    }

    private var absenceContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                AbsenceHeader(
                    totalCounts: viewModel.totalCounts,
                    threshold: viewModel.normalizedThreshold
                )
                if viewModel.isLocallyAdjusted {
                    GradelyLabel("absence.override.adjusted", systemImage: "eye.slash")
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("absenceLocallyAdjusted")
                }
                if !viewModel.overrideMetadata.reviewOverrides.isEmpty {
                    Button {
                        viewModel.isHiddenAbsencesSheetPresented = true
                    } label: {
                        GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle")
                    }
                    .accessibilityIdentifier("absenceOverridesNeedReview")
                }
                if let error = viewModel.overrideErrorMessage {
                    GradelyLabel(error, systemImage: "exclamationmark.triangle")
                        .font(.gradely(.caption)).foregroundStyle(GradeBand.poor.foregroundColor)
                }
                AbsencePredictorCard(
                    result: viewModel.predictionResult,
                    onOpen: {
                        viewModel.openPredictionSheet()
                    },
                    onClear: {
                        viewModel.clearPredictionSelections()
                    }
                )
                Picker("absence.segment.title", selection: $viewModel.selectedSegment) {
                    ForEach(AbsenceViewModel.Segment.allCases) { segment in
                        Text(segment.localizedTitle).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("absenceSegmentedControl")

                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("absence.refreshing")
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xs)
                }

                switch viewModel.selectedSegment {
                case .subjects:
                    SubjectAbsenceTable(
                        state: viewModel.subjectAbsenceState,
                        risk: { viewModel.risk(for: $0) },
                        onRetry: {
                            viewModel.retrySubjectResolution()
                        },
                        onResolveMissingHours: {
                            viewModel.openManualSelectionSheet()
                        }
                    )
                case .days:
                    AbsenceCountsList(
                        totalTitle: AppL10n.string("absence.total"),
                        rows: viewModel.dayCountRows,
                        emptyTitle: "absence.days.empty",
                        onSelect: { viewModel.openOverrideEditor(dayRowID: $0) }
                    )
                case .months:
                    if viewModel.monthRows.count >= 2 {
                        AbsenceMonthsChartCard(months: viewModel.monthRows)
                    }
                    AbsenceCountsList(
                        totalTitle: AppL10n.string("absence.total"),
                        rows: viewModel.monthCountRows,
                        emptyTitle: "absence.months.empty"
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
        }
        .gradelyScreenBackground()
        .accessibilityIdentifier("absenceList")
    }
}

private struct AbsenceHeader: View {
    let totalCounts: AbsenceCounts
    let threshold: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("absence.header.total")
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("\(totalCounts.total)")
                    .font(.gradely(size: 52, weight: .bold).monospacedDigit())
                    .foregroundStyle(Brand.primary)
                    .lineLimit(1)
                Text("absence.totalHours")
                    .font(.gradely(.title3).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !summary.isEmpty {
                Text(summary)
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("absenceHeader")
    }

    /// "Unresolved 6 · Excused 15 · Late 1 · Limit 25 %"
    private var summary: String {
        var parts = AbsenceCategory.allCases.compactMap { category -> String? in
            let value = category.value(in: totalCounts)
            return value > 0 ? "\(category.shortLabel) \(value)" : nil
        }
        if let threshold {
            parts.append(String(format: AppL10n.string("absence.threshold.caption"), threshold))
        }
        // Keep each item on one line so wrapping only happens between items.
        return parts
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " · ")
    }
}

private struct AbsenceCountsList: View {
    let totalTitle: String
    let rows: [AbsenceCountRow]
    let emptyTitle: LocalizedStringKey
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        if rows.isEmpty {
            EmptyAbsenceSection(title: emptyTitle)
        } else {
            LazyVStack(spacing: 0) {
                Divider()
                countRow(
                    title: totalTitle,
                    counts: rows.reduce(into: .zero) { total, row in total.add(row.counts) },
                    isTotal: true
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("absenceRow-total")

                ForEach(rows) { row in
                    Divider()
                    if let onSelect {
                        Button { onSelect(row.id) } label: {
                            countRow(title: row.title, counts: row.counts, isTotal: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("absenceRow-\(row.id)")
                        .accessibilityHint(AppL10n.string("absence.override.editHint"))
                    } else {
                        countRow(title: row.title, counts: row.counts, isTotal: false)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("absenceRow-\(row.id)")
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    private func countRow(
        title: String,
        counts: AbsenceCounts,
        isTotal: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(title)
                .font(isTotal ? .gradely(.subheadline).weight(.bold) : .gradely(.subheadline).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: Spacing.sm)

            categoryChips(for: counts)

            Text("\(counts.total)")
                .font(.gradely(.subheadline).weight(.bold).monospacedDigit())
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }

    private func categoryChips(for counts: AbsenceCounts) -> some View {
        let nonzero = AbsenceCategory.allCases.filter { $0.value(in: counts) > 0 }

        return HStack(spacing: Spacing.xs) {
            ForEach(Array(nonzero.prefix(4))) { category in
                StatusChip(
                    text: "\(category.symbol) \(category.value(in: counts))",
                    color: category.color
                )
                .accessibilityLabel("\(category.accessibilityLabel): \(category.value(in: counts))")
            }

            if nonzero.count > 4 {
                StatusChip(
                    text: String(format: AppL10n.string("absence.chip.overflow"), nonzero.count - 4),
                    color: .secondary
                )
            }
        }
    }
}

private struct AbsenceMonthsChartCard: View {
    let months: [AbsenceMonthSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            PlainSectionTitle("absence.months.chart")

            AbsenceMonthsChart(series: series)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: Spacing.xs, alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.xs
            ) {
                ForEach(series) { entry in
                    StatusChip(text: "\(symbol(for: entry.id)) \(entry.label)", color: entry.color)
                }
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.bottom, Spacing.md)
    }

    private var series: [AbsenceChartSeries] {
        AbsenceCategory.allCases.compactMap { category in
            let samples = months.compactMap { month -> AbsenceChartSeries.Sample? in
                let count = category.value(in: month.counts)
                guard count > 0 else { return nil }
                return AbsenceChartSeries.Sample(
                    id: "\(month.id)-\(category.id)",
                    month: month.monthDate,
                    count: count
                )
            }
            guard !samples.isEmpty else { return nil }
            return AbsenceChartSeries(
                id: category.id,
                label: category.accessibilityLabel,
                color: category.color,
                samples: samples
            )
        }
    }

    private func symbol(for seriesID: String) -> String {
        AbsenceCategory.allCases.first { $0.id == seriesID }?.symbol ?? ""
    }
}

private struct SubjectAbsenceTable: View {
    let state: AbsenceViewModel.SubjectAbsenceState
    let risk: (AbsenceSubjectSummary) -> AbsenceRiskSubject
    let onRetry: () -> Void
    let onResolveMissingHours: () -> Void

    var body: some View {
        switch state {
        case .idle:
            SubjectResolutionStatusView(progress: nil)
        case .loading(let progress):
            SubjectResolutionStatusView(progress: progress)
        case .empty:
            EmptyAbsenceSection(title: "absence.subjects.empty")
                .accessibilityIdentifier("absenceSubjectsEmpty")
        case .failed(let message):
            SubjectResolutionErrorView(message: message, onRetry: onRetry)
        case .loaded(let rows, _, let warning, let unresolvedPartialDays):
            VStack(spacing: Spacing.sm) {
                if let warning, !warning.isEmpty {
                    SubjectResolutionWarningView(message: warning)
                }
                if !unresolvedPartialDays.isEmpty {
                    SubjectManualResolutionCallout(
                        days: unresolvedPartialDays,
                        onResolveMissingHours: onResolveMissingHours
                    )
                }
                if !rows.isEmpty {
                    riskList(rows: rows)
                }
            }
        }
    }

    private func riskList(rows: [AbsenceSubjectSummary]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(rows, id: \.stableID) { row in
                Divider()
                riskRow(row)
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func riskRow(_ row: AbsenceSubjectSummary) -> some View {
        let risk = risk(row)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.subjectName)
                    .font(.gradely(.subheadline).weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.1f %%", row.absencePercentage))
                    .font(.gradely(.headline).monospacedDigit())
                    .foregroundStyle(risk.level.color)
            }

            RiskCapsuleBar(
                percentage: risk.percentage,
                threshold: risk.threshold,
                level: risk.level
            )

            HStack(spacing: Spacing.xs) {
                Text(
                    String(
                        format: AppL10n.string("absence.risk.missed"),
                        risk.missedLessons,
                        risk.totalLessons
                    )
                )
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)

                if let status = riskStatus(for: risk) {
                    Text(verbatim: "·")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)

                    Text(status.text)
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(status.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, Spacing.md)
        .accessibilityIdentifier("absenceRow-\(row.stableID)")
    }

    private func riskStatus(for risk: AbsenceRiskSubject) -> (text: String, color: Color)? {
        guard risk.threshold != nil else {
            return (AppL10n.string("absence.risk.noThreshold"), .secondary)
        }
        guard let misses = risk.missesUntilLimit else { return nil }
        if misses == 0 {
            return (AppL10n.string("absence.risk.overLimit"), GradeBand.poor.foregroundColor)
        }
        return (
            String(format: AppL10n.string("absence.risk.untilLimit"), misses),
            .secondary
        )
    }
}

private struct SubjectManualResolutionCallout: View {
    let days: [AbsencePartialDayCandidate]
    let onResolveMissingHours: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GradelyLabel("absence.manual.callout.title", systemImage: "hand.tap")
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(Brand.primary)

            Text(
                String(
                    format: AppL10n.string("absence.manual.callout.message"),
                    days.count
                )
            )
            .font(.gradely(.subheadline))
            .foregroundStyle(.secondary)

            Button("absence.manual.callout.button", action: onResolveMissingHours)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("absenceManualResolveButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absenceManualResolutionCallout")
    }
}

private struct ManualAbsenceLessonSelectionSheet: View {
    @Bindable var viewModel: AbsenceViewModel

    var body: some View {
        ModalNavigationContainer {
            AbsenceSheetPage(title: "absence.manual.title") {
                if let message = viewModel.manualSelectionErrorMessage {
                    GradelyLabel(message, systemImage: "exclamationmark.triangle")
                        .font(.gradely(.subheadline))
                        .foregroundStyle(GradeBand.poor.foregroundColor)
                }

                ForEach(viewModel.manualResolutionCandidates) { day in
                    PlainSection {
                        VStack(alignment: .leading, spacing: 2) {
                            PlainSectionTitle(verbatim: day.title)
                            Text(
                                String(
                                    format: AppL10n.string("absence.manual.selectedCount"),
                                    viewModel.selectedManualLessonCount(for: day.dateKey),
                                    day.requiredSelectionCount
                                )
                            )
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("absenceManualDay-\(day.dateKey)")
                    } content: {
                        ForEach(day.lessons) { lesson in
                            AbsenceLessonToggleRow(
                                lesson: lesson,
                                isSelected: viewModel.isManualLessonSelected(lesson.id, dateKey: day.dateKey)
                            ) {
                                viewModel.toggleManualLesson(lesson.id, dateKey: day.dateKey)
                            }
                            .accessibilityIdentifier("absenceManualLesson-\(lesson.id)")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        viewModel.cancelManualSelectionSheet()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task { await viewModel.saveManualSelections() }
                    }
                    .disabled(!viewModel.canSaveManualSelectionDrafts || viewModel.isSavingManualSelections)
                    .accessibilityIdentifier("absenceManualSaveButton")
                }
            }
        }
        .gradelyMacSheetSize(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absenceManualSelectionSheet")
    }
}

/// Page of the absence sheets: plain sections straight on the background
/// instead of a grouped list. The Mac draws the title in the page because a
/// NavigationStack in a Mac sheet adds a grey title strip.
struct AbsenceSheetPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                #if os(macOS)
                Text(title)
                    .font(.gradely(.title2).weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                #endif
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
        }
        .background { SettingsBackground() }
        .navigationTitle(title)
        .gradelyNavigationTitleDisplayMode(.inline)
    }
}

/// One lesson to tick in the absence sheets: period, subject and time once.
struct AbsenceLessonToggleRow: View {
    let lesson: AbsenceLessonCandidate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text(lesson.hourCaption)
                    .font(.gradely(.headline).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.subjectName)
                        .font(.gradely(.subheadline).weight(.semibold))
                    if !lesson.timeRange.isEmpty {
                        Text(lesson.timeRange)
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: Spacing.sm)

                GradelyIcon(systemName: isSelected ? "checkmark.circle.fill" : "circle", size: 20)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.tertiary))
            }
            .frame(minHeight: ControlMetrics.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SubjectResolutionStatusView: View {
    let progress: AbsenceSubjectResolutionProgress?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("absence.subjects.calculating")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)

                if let progress {
                    Text(
                        String(
                            format: AppL10n.string("absence.subjects.progress"),
                            progress.completedWeeks,
                            progress.totalWeeks
                        )
                    )
                    .font(.gradely(.caption))
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("absenceSubjectsProgress")
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .accessibilityIdentifier("absenceSubjectsCalculating")
    }
}

private struct SubjectResolutionWarningView: View {
    let message: String

    var body: some View {
        GradelyLabel(message, systemImage: "exclamationmark.triangle")
            .font(.gradely(.subheadline))
            .foregroundStyle(GradeBand.average.foregroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.sm)
            .accessibilityIdentifier("absenceSubjectsWarning")
    }
}

private struct SubjectResolutionErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GradelyLabel(AppL10n.string("absence.subjects.error.title"), systemImage: "exclamationmark.triangle")
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(GradeBand.poor.foregroundColor)

            Text(message)
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)

            Button(AppL10n.string("action.retry"), action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .accessibilityIdentifier("absenceSubjectsError")
    }
}

private struct EmptyAbsenceSection: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.sm) {
            GradelyIcon(systemName: "calendar.badge.checkmark")
                .foregroundStyle(Brand.primary)
            Text(title)
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
    }
}

private enum AbsenceCategory: CaseIterable, Identifiable {
    case unsolved
    case ok
    case missed
    case late
    case soon
    case school
    case distanceTeaching

    var id: String { accessibilityKey }

    var symbol: String {
        switch self {
        case .unsolved: "?"
        case .ok: "✓"
        case .missed: "N"
        case .late: "P"
        case .soon: "O"
        case .school: "–"
        case .distanceTeaching: "D"
        }
    }

    var color: Color {
        switch self {
        case .unsolved: Brand.primary
        case .ok: Brand.secondary
        case .missed: GradeBand.poor.foregroundColor
        case .late: GradeBand.average.foregroundColor
        case .soon: Color.gradelySystemOrange
        case .school, .distanceTeaching: Brand.secondary
        }
    }

    var accessibilityLabel: String {
        AppL10n.string(String.LocalizationValue(accessibilityKey))
    }

    var shortLabel: String {
        switch self {
        case .unsolved: AppL10n.string("absence.category.short.unsolved")
        case .ok: AppL10n.string("absence.category.short.ok")
        case .missed: AppL10n.string("absence.category.short.missed")
        case .late: AppL10n.string("absence.category.short.late")
        case .soon: AppL10n.string("absence.category.short.soon")
        case .school: AppL10n.string("absence.category.short.school")
        case .distanceTeaching: AppL10n.string("absence.category.short.distanceTeaching")
        }
    }

    private var accessibilityKey: String {
        switch self {
        case .unsolved: "absence.category.unsolved"
        case .ok: "absence.category.ok"
        case .missed: "absence.category.missed"
        case .late: "absence.category.late"
        case .soon: "absence.category.soon"
        case .school: "absence.category.school"
        case .distanceTeaching: "absence.category.distanceTeaching"
        }
    }

    func value(in counts: AbsenceCounts) -> Int {
        switch self {
        case .unsolved: counts.unsolved
        case .ok: counts.ok
        case .missed: counts.missed
        case .late: counts.late
        case .soon: counts.soon
        case .school: counts.school
        case .distanceTeaching: counts.distanceTeaching
        }
    }
}

private extension AbsenceViewModel.Segment {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .subjects: "absence.segment.subjects"
        case .days: "absence.segment.days"
        case .months: "absence.segment.months"
        }
    }
}

#Preview("Light") {
    AbsenceView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            absenceCache: InMemoryAbsenceCache(
                cachedAbsence: CachedAbsence(response: PreviewData.riskAbsenceResponse, cachedAt: Date())
            )
        )
    )
}

#Preview("Dark") {
    AbsenceView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            absenceCache: InMemoryAbsenceCache(
                cachedAbsence: CachedAbsence(response: PreviewData.riskAbsenceResponse, cachedAt: Date())
            )
        )
    )
    .preferredColorScheme(.dark)
}
