import SwiftUI

struct SubjectsView: View {
    @State private var viewModel: SubjectsViewModel
    @State private var sortMode: SubjectSortMode = .focus
    @State private var siriPath: [String] = []
    private let siriSubjectID: String?
    private let siriRequestID: UUID?
    private let repository: SchoolRepository
    private let accountHub: AnyView?
    private let onOpenGradeyAI: () -> Void

    init(
        repository: SchoolRepository,
        historyRepository: GradeyHistoryRepository? = nil,
        trends: [SubjectGradeTrend] = [],
        snapshotStore: SchoolSnapshotStore? = nil,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {},
        siriSubjectID: String? = nil,
        siriRequestID: UUID? = nil
    ) {
        self.repository = repository
        self.siriSubjectID = siriSubjectID
        self.siriRequestID = siriRequestID
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        let model = SubjectsViewModel(repository: repository, historyRepository: historyRepository, snapshotStore: snapshotStore)
        model.trends = trends
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        NavigationStack(path: $siriPath) {
            Group {
                if viewModel.isLoading && viewModel.subjects.isEmpty {
                    ContentUnavailableView {
                        ProgressView()
                            .controlSize(.large)
                    } description: {
                        Text("subjects.loading")
                    }
                    .accessibilityIdentifier("subjectsLoadingView")
                } else if let errorMessage = viewModel.errorMessage, viewModel.subjects.isEmpty {
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
                    .accessibilityIdentifier("subjectsErrorView")
                } else if viewModel.subjects.isEmpty {
                    ContentUnavailableView {
                        GradelyLabel(
                            AppL10n.string("subjects.empty.title"),
                            systemImage: "list.bullet.rectangle",
                            iconSize: 28
                        )
                    } description: {
                        Text("subjects.empty.message")
                    }
                    .accessibilityIdentifier("subjectsEmptyView")
                } else {
                    marksDashboard
                }
            }
            .navigationTitle(AppL10n.string("subjects.title"))
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
                    .accessibilityIdentifier("refreshButton")
                }

                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    AccountSettingsButton(accountHub: accountHub)
                }
            }
            .navigationDestination(for: String.self) { subjectID in
                if let subject = viewModel.subjects.first(where: { $0.id == subjectID }) {
                    SubjectDetailView(viewModel: SubjectDetailViewModel(subject: subject, absence: viewModel.absence(for: subject), repository: repository,
                        trend: trend(for: subject),
                        prepared: viewModel.snapshotStore?.preparedCalculations[subject.id]), snapshotStore: viewModel.snapshotStore)
                } else { ContentUnavailableView("detail.intelligence.subjectUnavailable", systemImage: "book.closed") }
            }
            .onChange(of: siriSubjectID) { _, id in if id == nil { siriPath = [] } }
            .onChange(of: siriRequestID) { siriPath = siriSubjectID.map { [$0] } ?? [] }
            .onChange(of: viewModel.snapshotStore?.revision) { viewModel.applySharedSnapshot() }
            .task {
                await viewModel.loadIfNeeded()
                if let siriSubjectID { siriPath = [siriSubjectID] }
            }
        }
    }

    private var marksDashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("subjects.refreshing")
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xs)
                }

                MarksHero(viewModel: viewModel)

                if viewModel.hasLocalAbsenceAdjustments {
                    GradelyLabel(AppL10n.string("absence.title") + " · " + AppL10n.string("absence.override.adjusted"), systemImage: "eye.slash")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("subjectsAbsenceAdjusted")
                }

                SubjectDirectory(
                    subjects: displayedSubjects,
                    sortMode: $sortMode,
                    repository: repository,
                    snapshotStore: viewModel.snapshotStore,
                    absence: { viewModel.absence(for: $0) },
                    trend: { trend(for: $0) }
                )
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
        }
        .accessibilityIdentifier("subjectsList")
    }

    private var displayedSubjects: [Subject] {
        let subjects = viewModel.subjects
        switch sortMode {
        case .focus:
            let summaries = viewModel.snapshotStore?.subjectInsights ?? []
            let scores = summaries.reduce(into: [String: Double]()) { scores, summary in
                scores[summary.subjectID] = (summary.currentAverage ?? 0) + max(summary.trendDelta ?? 0, 0) * 2
                    + (summary.upcomingEvents.isEmpty ? 0 : 2)
            }
            return subjects.sorted {
                let firstScore = scores[$0.id] ?? GradeMath.subjectAverage($0) ?? 0
                let secondScore = scores[$1.id] ?? GradeMath.subjectAverage($1) ?? 0
                if firstScore == secondScore {
                    return $0.trimmedName.localizedCaseInsensitiveCompare($1.trimmedName) == .orderedAscending
                }
                return firstScore > secondScore
            }
        case .average:
            return subjects.sorted {
                let firstAverage = GradeMath.subjectAverage($0) ?? .greatestFiniteMagnitude
                let secondAverage = GradeMath.subjectAverage($1) ?? .greatestFiniteMagnitude
                if firstAverage == secondAverage {
                    return $0.trimmedName.localizedCaseInsensitiveCompare($1.trimmedName) == .orderedAscending
                }
                return firstAverage < secondAverage
            }
        }
    }

    private func trend(for subject: Subject) -> SubjectGradeTrend? {
        viewModel.trends.first { trend in
            trend.subjectID == subject.id
                || trend.subjectName?.caseInsensitiveCompare(subject.trimmedName) == .orderedSame
                || trend.subjectAbbrev?.caseInsensitiveCompare(subject.trimmedAbbrev) == .orderedSame
        }
    }

}

// MARK: - Sort

private enum SubjectSortMode: String, CaseIterable, Identifiable, Hashable {
    case focus
    case average

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: AppL10n.string("marks.sort.focus")
        case .average: AppL10n.string("marks.sort.average")
        }
    }
}

// MARK: - Hero

private struct MarksHero: View {
    let viewModel: SubjectsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("marks.hero.average")
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(GradeMath.formattedAverage(viewModel.overallAverage))
                    .font(.gradely(size: 52, weight: .bold).monospacedDigit())
                    .foregroundStyle(GradeMath.band(for: viewModel.overallAverage).foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(
                    String.localizedStringWithFormat(AppL10n.string("marks.hero.subjectCount"), viewModel.subjects.count)
                        + " · "
                        + String.localizedStringWithFormat(AppL10n.string("subject.markCount"), viewModel.totalMarks)
                )
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marksHeroCard")
    }
}

// MARK: - Subject directory

private struct SubjectDirectory: View {
    let subjects: [Subject]
    @Binding var sortMode: SubjectSortMode
    let repository: SchoolRepository
    let snapshotStore: SchoolSnapshotStore?
    let absence: (Subject) -> AbsencePerSubject?
    let trend: (Subject) -> SubjectGradeTrend?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                SectionHeader("marks.directory.title")

                Picker(AppL10n.string("marks.sort.label"), selection: $sortMode) {
                    ForEach(SubjectSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("subjectsSortPicker")
            }

            VStack(spacing: 0) {
                ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
                    NavigationLink {
                        SubjectDetailView(
                            viewModel: SubjectDetailViewModel(
                                subject: subject,
                                absence: absence(subject),
                                repository: repository,
                                trend: trend(subject),
                                prepared: snapshotStore?.preparedCalculations[subject.id]
                            ),
                            snapshotStore: snapshotStore
                        )
                    } label: {
                        SubjectRow(
                            subject: subject,
                            absence: absence(subject),
                            prepared: snapshotStore?.preparedCalculations[subject.id]
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subjectRow-\(subject.id)")

                    if index < subjects.count - 1 {
                        Divider()
                            .padding(.leading, Spacing.md + 44 + Spacing.md)
                    }
                }
            }
            .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

private struct SubjectRow: View {
    let subject: Subject
    let absence: AbsencePerSubject?
    var prepared: PreparedGradeCalculation? = nil

    var body: some View {
        let average = prepared == nil ? GradeMath.subjectAverage(subject) : prepared?.displayAverage
        let band = GradeMath.band(for: average)

        HStack(alignment: .center, spacing: Spacing.md) {
            SubjectAbbrevBadge(text: abbrev, band: band)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subject.trimmedName)
                    .font(.gradely(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: Spacing.sm) {
                    Text(String.localizedStringWithFormat(AppL10n.string("subject.markCount"), subject.marks.count))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)

                    if let latestMark = subject.marks.first {
                        InlineMark(text: latestMark.displayText, band: GradeMath.band(for: latestMark))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(GradeMath.formattedAverage(average))
                    .font(.gradely(.title3).weight(.bold).monospacedDigit())
                    .foregroundStyle(band.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let absence {
                    Text(String(format: AppL10n.string("marks.row.absencePercent"), absence.absencePercentage))
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            GradelyIcon(systemName: "chevron.right")
                .font(.gradely(.caption).weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }

    private var abbrev: String {
        let trimmed = subject.trimmedAbbrev
        return trimmed.isEmpty ? String(subject.trimmedName.prefix(2)).uppercased() : trimmed
    }
}

private struct SubjectAbbrevBadge: View {
    let text: String
    let band: GradeBand

    var body: some View {
        Text(text)
            .font(.gradely(.subheadline).weight(.bold))
            .foregroundStyle(band.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 44, height: 40)
            .background(band.soft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

private struct InlineMark: View {
    let text: String
    let band: GradeBand

    var body: some View {
        Text(text)
            .font(.gradely(.caption).weight(.bold).monospacedDigit())
            .foregroundStyle(band.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(band.soft, in: Capsule())
    }
}

#Preview("Light") {
    SubjectsView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
        ),
        trends: PreviewData.subjectGradeTrends
    )
}

#Preview("Dark") {
    SubjectsView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
        ),
        trends: PreviewData.subjectGradeTrends
    )
    .preferredColorScheme(.dark)
}
