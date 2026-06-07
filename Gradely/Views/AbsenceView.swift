import SwiftUI

struct AbsenceView: View {
    @State private var viewModel: AbsenceViewModel
    private let supportTipProvider: any SupportTipProviding
    let onSignedOut: () -> Void

    init(
        repository: BakalariRepository,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        onSignedOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AbsenceViewModel(repository: repository))
        self.supportTipProvider = supportTipProvider
        self.onSignedOut = onSignedOut
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "absence.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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

                    ToolbarItem(placement: .topBarTrailing) {
                        AccountMenu(
                            user: viewModel.user,
                            supportTipProvider: supportTipProvider,
                            onSignedOut: onSignedOut
                        )
                    }
                }
                .task {
                    await viewModel.loadIfNeeded()
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
        } else if !viewModel.hasAnyAbsenceData {
            ContentUnavailableView(
                String(localized: "absence.empty.title"),
                systemImage: "calendar.badge.checkmark",
                description: Text("absence.empty.message")
            )
            .accessibilityIdentifier("absenceEmptyView")
        } else {
            absenceContent
        }
    }

    private var absenceContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                AbsenceHeader(user: viewModel.user, totalCounts: viewModel.totalCounts)

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
                        }
                    )
                case .days:
                    CountsAbsenceTable(
                        leadingTitle: String(localized: "absence.column.day"),
                        totalTitle: String(localized: "absence.total"),
                        rows: viewModel.dayRows.map {
                            CountsAbsenceRow(id: "day-\($0.id)", title: $0.title, counts: $0.counts)
                        },
                        emptyTitle: "absence.days.empty"
                    )
                case .months:
                    CountsAbsenceTable(
                        leadingTitle: String(localized: "absence.column.month"),
                        totalTitle: String(localized: "absence.total"),
                        rows: viewModel.monthRows.map {
                            CountsAbsenceRow(id: "month-\($0.id)", title: $0.title, counts: $0.counts)
                        },
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

private struct CountsAbsenceRow: Identifiable {
    let id: String
    let title: String
    let counts: AbsenceCounts
}

private struct CountsAbsenceTable: View {
    let leadingTitle: String
    let totalTitle: String
    let rows: [CountsAbsenceRow]
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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
        .background(Color(.tertiarySystemGroupedBackground))
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
        .background(isTotal ? Color(.tertiarySystemGroupedBackground) : Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier(id)
    }
}

private struct SubjectAbsenceTable: View {
    let state: AbsenceViewModel.SubjectAbsenceState
    let onRetry: () -> Void

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
        case .loaded(let rows, _, let warning):
            VStack(spacing: Spacing.sm) {
                if let warning, !warning.isEmpty {
                    SubjectResolutionWarningView(message: warning)
                }
                table(rows: rows)
            }
        }
    }

    private func table(rows: [AbsenceSubjectSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                header
                ForEach(rows, id: \.stableID) { row in
                    subjectRow(row)
                }
            }
            .frame(minWidth: 560)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("absence.column.subject")
                .frame(width: 230, alignment: .leading)
            Text("absence.column.lessons")
                .frame(width: 92)
            Text("absence.column.absent")
                .frame(width: 92)
            Text("absence.column.percent")
                .frame(width: 92)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Brand.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private func subjectRow(_ row: AbsenceSubjectSummary) -> some View {
        HStack(spacing: 0) {
            Text(row.subjectName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(width: 230, alignment: .leading)

            Text("\(row.lessonsCount)")
                .frame(width: 92)
            Text("\(row.base)")
                .frame(width: 92)
            Text(String(format: "%.1f %%", row.absencePercentage))
                .frame(width: 92)
        }
        .font(.body.monospacedDigit())
        .foregroundStyle(row.exceedsThreshold ? GradeBand.poor.foregroundColor : .primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
        .background(row.exceedsThreshold ? GradeBand.poor.soft : Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("absenceRow-\(row.stableID)")
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
        case .soon: Color(.systemOrange)
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
