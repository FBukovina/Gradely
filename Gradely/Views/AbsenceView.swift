import SwiftUI

struct AbsenceView: View {
    @State private var viewModel: AbsenceViewModel
    private let accountHub: AnyView?
    private let onOpenGradeyAI: () -> Void

    init(
        repository: SchoolRepository,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: AbsenceViewModel(repository: repository))
        self.accountHub = accountHub
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
                        AccountSettingsButton(accountHub: accountHub)
                    }
                }
                .task {
                    await viewModel.loadIfNeeded()
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
                    user: viewModel.user,
                    totalCounts: viewModel.totalCounts,
                    threshold: viewModel.normalizedThreshold
                )
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
                .accessibilityIdentifier("absenceSegmentedControl")

                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("absence.refreshing")
                            .font(.subheadline)
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
                        emptyTitle: "absence.days.empty"
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
        }
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
        }
        .gradelyScreenBackground()
        .accessibilityIdentifier("absenceList")
    }
}

private struct AbsenceHeader: View {
    let user: UserResponse?
    let totalCounts: AbsenceCounts
    let threshold: Double?

    var body: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    GradelyIcon(systemName: "calendar.badge.exclamationmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Brand.primary)
                        .frame(width: 46, height: 46)
                        .background(Brand.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("absence.title")
                            .font(.headline)

                        if let name = user?.fullName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalCounts.total)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Brand.primary)
                        Text("absence.totalHours")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !nonzeroCategories.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64), spacing: Spacing.xs, alignment: .leading)],
                        alignment: .leading,
                        spacing: Spacing.xs
                    ) {
                        ForEach(nonzeroCategories) { category in
                            StatusChip(
                                text: "\(category.symbol) \(category.value(in: totalCounts))",
                                color: category.color
                            )
                            .accessibilityLabel("\(category.accessibilityLabel): \(category.value(in: totalCounts))")
                        }
                    }
                }

                if let threshold {
                    Text(String(format: AppL10n.string("absence.threshold.caption"), threshold))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nonzeroCategories: [AbsenceCategory] {
        AbsenceCategory.allCases.filter { $0.value(in: totalCounts) > 0 }
    }
}

private struct AbsenceCountsList: View {
    let totalTitle: String
    let rows: [AbsenceCountRow]
    let emptyTitle: LocalizedStringKey

    var body: some View {
        if rows.isEmpty {
            EmptyAbsenceSection(title: emptyTitle)
        } else {
            LazyVStack(spacing: 0) {
                countRow(
                    id: "absenceRow-total",
                    title: totalTitle,
                    counts: rows.reduce(into: .zero) { total, row in total.add(row.counts) },
                    isTotal: true
                )

                ForEach(rows) { row in
                    countRow(
                        id: "absenceRow-\(row.id)",
                        title: row.title,
                        counts: row.counts,
                        isTotal: false
                    )
                }
            }
            .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func countRow(
        id: String,
        title: String,
        counts: AbsenceCounts,
        isTotal: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(title)
                .font(isTotal ? .subheadline.weight(.bold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: Spacing.sm)

            categoryChips(for: counts)

            Text("\(counts.total)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(isTotal ? Color.gradelyTertiaryGroupedBackground : Color.gradelySecondaryGroupedBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier(id)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("absence.months.chart")

            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
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
            }
        }
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
                riskRow(row)
            }
        }
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func riskRow(_ row: AbsenceSubjectSummary) -> some View {
        let risk = risk(row)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.subjectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.1f %%", row.absencePercentage))
                    .font(.headline.monospacedDigit())
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
                .font(.caption)
                .foregroundStyle(.secondary)

                if let status = riskStatus(for: risk) {
                    Text(verbatim: "·")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(status.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                GradelyLabel("absence.manual.callout.title", systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.primary)

                Text(
                    String(
                        format: AppL10n.string("absence.manual.callout.message"),
                        days.count
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button("absence.manual.callout.button", action: onResolveMissingHours)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("absenceManualResolveButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absenceManualResolutionCallout")
    }
}

private struct ManualAbsenceLessonSelectionSheet: View {
    @Bindable var viewModel: AbsenceViewModel

    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.manualSelectionErrorMessage {
                    Section {
                        GradelyLabel(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(GradeBand.poor.foregroundColor)
                    }
                }

                ForEach(viewModel.manualResolutionCandidates) { day in
                    Section {
                        ForEach(day.lessons) { lesson in
                            Button {
                                viewModel.toggleManualLesson(lesson.id, dateKey: day.dateKey)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lesson.displayTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        if !lesson.timeRange.isEmpty {
                                            Text(lesson.timeRange)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if viewModel.isManualLessonSelected(lesson.id, dateKey: day.dateKey) {
                                        GradelyIcon(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Brand.primary)
                                    } else {
                                        GradelyIcon(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("absenceManualLesson-\(lesson.id)")
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.title)
                            Text(
                                String(
                                    format: AppL10n.string("absence.manual.selectedCount"),
                                    viewModel.selectedManualLessonCount(for: day.dateKey),
                                    day.requiredSelectionCount
                                )
                            )
                        }
                        .accessibilityIdentifier("absenceManualDay-\(day.dateKey)")
                    }
                }
            }
            .navigationTitle("absence.manual.title")
            .gradelyNavigationTitleDisplayMode(.inline)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absenceManualSelectionSheet")
    }
}

private struct SubjectResolutionStatusView: View {
    let progress: AbsenceSubjectResolutionProgress?

    var body: some View {
        Card {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("absence.subjects.calculating")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let progress {
                        Text(
                            String(
                                format: AppL10n.string("absence.subjects.progress"),
                                progress.completedWeeks,
                                progress.totalWeeks
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("absenceSubjectsProgress")
                    }
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("absenceSubjectsCalculating")
    }
}

private struct SubjectResolutionWarningView: View {
    let message: String

    var body: some View {
        Card {
            GradelyLabel(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(GradeBand.average.foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("absenceSubjectsWarning")
    }
}

private struct SubjectResolutionErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                GradelyLabel(AppL10n.string("absence.subjects.error.title"), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GradeBand.poor.foregroundColor)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(AppL10n.string("action.retry"), action: onRetry)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("absenceSubjectsError")
    }
}

private struct EmptyAbsenceSection: View {
    let title: LocalizedStringKey

    var body: some View {
        Card {
            HStack(spacing: Spacing.sm) {
                GradelyIcon(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(Brand.primary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
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
