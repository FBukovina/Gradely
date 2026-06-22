import SwiftUI

struct AbsenceView: View {
    @State private var viewModel: AbsenceViewModel
    private let repository: SchoolRepository
    private let supportTipProvider: any SupportTipProviding
    let onSignedOut: () -> Void

    init(
        repository: SchoolRepository,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        onSignedOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AbsenceViewModel(repository: repository))
        self.repository = repository
        self.supportTipProvider = supportTipProvider
        self.onSignedOut = onSignedOut
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "absence.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .gradelyTopBarLeading) {
                        CreditsToolbarButton()
                    }

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        Button {
                            Task { await viewModel.refresh(forceRefresh: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                        }
                        .disabled(viewModel.isLoading || viewModel.isRefreshing)
                        .accessibilityLabel(String(localized: "action.refresh"))
                        .accessibilityIdentifier("absenceRefreshButton")
                    }

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        AccountMenu(
                            user: viewModel.user,
                            repository: repository,
                            supportTipProvider: supportTipProvider,
                            onSignedOut: onSignedOut
                        )
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
                Label(String(localized: "error.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(String(localized: "action.retry")) {
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
                AbsenceHeader(user: viewModel.user, totalCounts: viewModel.totalCounts)
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
                        onRetry: {
                            viewModel.retrySubjectResolution()
                        },
                        onResolveMissingHours: {
                            viewModel.openManualSelectionSheet()
                        }
                    )
                case .days:
                    CountsAbsenceTable(
                        leadingTitle: String(localized: "absence.column.day"),
                        totalTitle: String(localized: "absence.total"),
                        rows: viewModel.dayCountRows,
                        emptyTitle: "absence.days.empty"
                    )
                case .months:
                    CountsAbsenceTable(
                        leadingTitle: String(localized: "absence.column.month"),
                        totalTitle: String(localized: "absence.total"),
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
        .background(Color.gradelyGroupedBackground.ignoresSafeArea())
        .accessibilityIdentifier("absenceList")
    }
}

private struct AbsenceHeader: View {
    let user: UserResponse?
    let totalCounts: AbsenceCounts

    var body: some View {
        Card(padding: Spacing.lg) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: "calendar.badge.exclamationmark")
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
        }
    }
}

private struct AbsencePredictorCard: View {
    let result: AbsencePredictionResult
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Brand.primary)
                        .frame(width: 42, height: 42)
                        .background(Brand.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("absence.predictor.title")
                            .font(.headline)
                        Text(messageKey)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if result.hasSelection {
                    predictionSummary
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: onOpen) {
                        Text(openButtonKey)
                    }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("absencePredictorOpenButton")

                    if result.hasSelection {
                        Button(role: .destructive, action: onClear) {
                            Text("action.clear")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("absencePredictorClearButton")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("absencePredictorCard")
    }

    private var messageKey: LocalizedStringKey {
        result.hasSelection ? "absence.predictor.summary.message" : "absence.predictor.empty.message"
    }

    private var openButtonKey: LocalizedStringKey {
        result.hasSelection ? "absence.predictor.edit" : "absence.predictor.open"
    }

    private var predictionSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                metricTile(
                    title: "absence.predictor.total",
                    value: "\(result.currentTotal.total) -> \(result.projectedTotal.total)"
                )
                metricTile(
                    title: "absence.predictor.okAdded",
                    value: String.localizedStringWithFormat(
                        String(localized: "absence.predictor.addedHours"),
                        result.addedHours
                    )
                )
            }

            if !result.subjectRows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(result.subjectRows) { row in
                        subjectRow(row)
                    }
                }
                .background(Color.gradelyTertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityIdentifier("absencePredictorSubjectRows")
            }
        }
        .accessibilityIdentifier("absencePredictionTotal")
    }

    private func metricTile(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Brand.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.gradelyTertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func subjectRow(_ row: AbsencePredictionSubjectRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.subjectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer()

                StatusChip(
                    text: String.localizedStringWithFormat(
                        String(localized: "absence.predictor.addedHours"),
                        row.addedHours
                    ),
                    color: row.exceedsThreshold ? GradeBand.poor.foregroundColor : Brand.secondary
                )
            }

            if let currentBase = row.currentBase,
               let projectedBase = row.projectedBase,
               let currentPercentage = row.currentPercentage,
               let projectedPercentage = row.projectedPercentage {
                HStack(spacing: Spacing.md) {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "absence.predictor.subject.absentChange"),
                            currentBase,
                            projectedBase
                        )
                    )
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "absence.predictor.subject.percentChange"),
                            currentPercentage,
                            projectedPercentage
                        )
                    )
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(row.exceedsThreshold ? GradeBand.poor.foregroundColor : .secondary)
            } else {
                Text("absence.predictor.baselineUnavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(row.exceedsThreshold ? GradeBand.poor.soft : Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("absencePredictionRow-\(row.id)")
    }
}

private struct CountsAbsenceTable: View {
    let leadingTitle: String
    let totalTitle: String
    let rows: [AbsenceCountRow]
    let emptyTitle: LocalizedStringKey

    private let leadingWidth: CGFloat = 118
    private let columnWidth: CGFloat = 54

    var body: some View {
        if rows.isEmpty {
            EmptyAbsenceSection(title: emptyTitle)
        } else {
            table
        }
    }

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                header
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
            .frame(minWidth: leadingWidth + columnWidth * CGFloat(AbsenceCategory.allCases.count))
            .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(leadingTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.primary)
                .frame(width: leadingWidth, alignment: .leading)

            ForEach(AbsenceCategory.allCases) { category in
                Text(category.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(category.color)
                    .frame(width: columnWidth)
                    .accessibilityLabel(category.accessibilityLabel)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color.gradelyTertiaryGroupedBackground)
    }

    private func countRow(
        id: String,
        title: String,
        counts: AbsenceCounts,
        isTotal: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(isTotal ? .subheadline.weight(.bold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: leadingWidth, alignment: .leading)

            ForEach(AbsenceCategory.allCases) { category in
                Text("\(category.value(in: counts))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: columnWidth)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
        .background(isTotal ? Color.gradelyTertiaryGroupedBackground : Color.gradelySecondaryGroupedBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier(id)
    }
}

private struct SubjectAbsenceTable: View {
    let state: AbsenceViewModel.SubjectAbsenceState
    let onRetry: () -> Void
    let onResolveMissingHours: () -> Void

    private let lessonsWidth: CGFloat = 72
    private let absentWidth: CGFloat = 68
    private let percentWidth: CGFloat = 78

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
                    table(rows: rows)
                }
            }
        }
    }

    private func table(rows: [AbsenceSubjectSummary]) -> some View {
        LazyVStack(spacing: 0) {
            header
            ForEach(rows, id: \.stableID) { row in
                subjectRow(row)
            }
        }
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("absence.column.subject")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("absence.column.lessons")
                .frame(width: lessonsWidth)
            Text("absence.column.absent")
                .frame(width: absentWidth)
            Text("absence.column.percent")
                .frame(width: percentWidth)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Brand.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color.gradelyTertiaryGroupedBackground)
    }

    private func subjectRow(_ row: AbsenceSubjectSummary) -> some View {
        HStack(spacing: 0) {
            Text(row.subjectName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(row.lessonsCount)")
                .frame(width: lessonsWidth)
            Text("\(row.base)")
                .frame(width: absentWidth)
            Text(String(format: "%.1f %%", row.absencePercentage))
                .frame(width: percentWidth)
        }
        .font(.body.monospacedDigit())
        .foregroundStyle(row.exceedsThreshold ? GradeBand.poor.foregroundColor : .primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
        .background(row.exceedsThreshold ? GradeBand.poor.soft : Color.gradelySecondaryGroupedBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("absenceRow-\(row.stableID)")
    }
}

private struct SubjectManualResolutionCallout: View {
    let days: [AbsencePartialDayCandidate]
    let onResolveMissingHours: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("absence.manual.callout.title", systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.primary)

                Text(
                    String(
                        format: String(localized: "absence.manual.callout.message"),
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
                        Label(message, systemImage: "exclamationmark.triangle")
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
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Brand.primary)
                                    } else {
                                        Image(systemName: "circle")
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
                                    format: String(localized: "absence.manual.selectedCount"),
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
        .accessibilityIdentifier("absenceManualSelectionSheet")
    }
}

private struct AbsencePredictionSheet: View {
    @Bindable var viewModel: AbsenceViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "absence.predictor.date",
                        selection: $viewModel.predictionSelectedDate,
                        in: viewModel.predictionMinimumDate...,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("absencePredictorDatePicker")
                }

                predictionLessonSection

                Section {
                    Button(role: .destructive) {
                        viewModel.clearPredictionDraftSelections()
                    } label: {
                        Text("action.clear")
                    }
                    .disabled(viewModel.predictionDraftSelectedCount == 0)
                    .accessibilityIdentifier("absencePredictorSheetClearButton")
                }
            }
            .navigationTitle("absence.predictor.sheet.title")
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        viewModel.cancelPredictionSheet()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        viewModel.commitPredictionSelections()
                    }
                    .accessibilityIdentifier("absencePredictorDoneButton")
                }
            }
            .task {
                await viewModel.loadPredictionLessonsForSelectedDate()
            }
            .onChange(of: viewModel.predictionSelectedDate) {
                Task { await viewModel.loadPredictionLessonsForSelectedDate() }
            }
        }
        .accessibilityIdentifier("absencePredictionSheet")
    }

    @ViewBuilder
    private var predictionLessonSection: some View {
        if viewModel.isLoadingPredictionLessons {
            Section {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("absence.predictor.loading")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let message = viewModel.predictionErrorMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(GradeBand.poor.foregroundColor)

                Button("action.retry") {
                    Task { await viewModel.loadPredictionLessonsForSelectedDate() }
                }
            }
        } else if viewModel.predictionLessons.isEmpty {
            Section {
                Label("absence.predictor.noLessons", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(viewModel.predictionLessons) { lesson in
                    Button {
                        viewModel.togglePredictionLesson(lesson)
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

                            if viewModel.isPredictionLessonSelected(lesson.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Brand.primary)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("absencePredictorLesson-\(lesson.id)")
                }
            } header: {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "absence.predictor.selectedCount"),
                        viewModel.predictionDraftSelectedCount
                    )
                )
            }
        }
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
                                format: String(localized: "absence.subjects.progress"),
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
            Label(message, systemImage: "exclamationmark.triangle")
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
                Label(String(localized: "absence.subjects.error.title"), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GradeBand.poor.foregroundColor)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(String(localized: "action.retry"), action: onRetry)
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
                Image(systemName: "calendar.badge.checkmark")
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
        String(localized: String.LocalizationValue(accessibilityKey))
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
