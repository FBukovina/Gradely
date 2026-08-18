import SwiftUI

struct SubjectsView: View {
    @State private var viewModel: SubjectsViewModel
    @State private var sortMode: SubjectSortMode = .focus
    private let repository: SchoolRepository
    private let accountHub: AnyView?
    private let onOpenGradeyAI: () -> Void

    init(
        repository: SchoolRepository,
        historyRepository: GradeyHistoryRepository? = nil,
        trends: [SubjectGradeTrend] = [],
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        let model = SubjectsViewModel(repository: repository, historyRepository: historyRepository)
        model.trends = trends
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
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
                        GradelyLabel(String(localized: "error.title"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(String(localized: "action.retry")) {
                            Task { await viewModel.refresh(forceRefresh: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .accessibilityIdentifier("subjectsErrorView")
                } else if viewModel.subjects.isEmpty {
                    ContentUnavailableView {
                        GradelyLabel(
                            String(localized: "subjects.empty.title"),
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
            .navigationTitle(String(localized: "subjects.title"))
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
                    .accessibilityLabel(String(localized: "action.refresh"))
                    .accessibilityIdentifier("refreshButton")
                }

                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    AccountSettingsButton(accountHub: accountHub)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xs)
                }

                MarksHero(viewModel: viewModel)

                if !recentTrends.isEmpty {
                    MarksTrendSection(trends: Array(recentTrends.prefix(4)))
                        .accessibilityIdentifier("marksTrendSection")
                }

                SubjectDirectory(
                    subjects: displayedSubjects,
                    sortMode: $sortMode,
                    repository: repository,
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
            return subjects.sorted {
                let firstScore = attentionScore(for: $0)
                let secondScore = attentionScore(for: $1)
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
        case .name:
            return subjects.sorted {
                $0.trimmedName.localizedCaseInsensitiveCompare($1.trimmedName) == .orderedAscending
            }
        }
    }

    private func attentionScore(for subject: Subject) -> Double {
        var score = GradeMath.subjectAverage(subject) ?? 0

        if let delta = trend(for: subject)?.averageDelta {
            score += max(delta, 0) * 2
        }

        if let absence = viewModel.absence(for: subject) {
            score += absence.absencePercentage / 25
        }

        if subject.marks.isEmpty {
            score -= 2
        }

        return score
    }

    private func trend(for subject: Subject) -> SubjectGradeTrend? {
        viewModel.trends.first { trend in
            trend.subjectID == subject.id
                || trend.subjectName?.caseInsensitiveCompare(subject.trimmedName) == .orderedSame
                || trend.subjectAbbrev?.caseInsensitiveCompare(subject.trimmedAbbrev) == .orderedSame
        }
    }

    /// The "Grade movement" section stays scoped to the last 90 days even though
    /// the view model loads the whole school year for the detail charts.
    private var recentTrends: [SubjectGradeTrend] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else {
            return viewModel.trends
        }
        let recentEvents = viewModel.trends
            .flatMap(\.events)
            .filter { $0.capturedAt >= cutoff }
        return SubjectGradeTrend.make(from: recentEvents)
    }
}

// MARK: - Sort

private enum SubjectSortMode: String, CaseIterable, Identifiable, Hashable {
    case focus
    case average
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: String(localized: "marks.sort.focus")
        case .average: String(localized: "marks.sort.average")
        case .name: String(localized: "marks.sort.name")
        }
    }
}

// MARK: - Hero

private struct MarksHero: View {
    let viewModel: SubjectsViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("marks.hero.average")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.onAccent.opacity(0.7))
                Text(GradeMath.formattedAverage(viewModel.overallAverage))
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Brand.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: Spacing.md)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(String.localizedStringWithFormat(String(localized: "marks.hero.subjectCount"), viewModel.subjects.count))
                Text(String.localizedStringWithFormat(String(localized: "subject.markCount"), viewModel.totalMarks))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.onAccent.opacity(0.72))
        }
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.24), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marksHeroCard")
    }
}

// MARK: - Trends

private struct MarksTrendSection: View {
    let trends: [SubjectGradeTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader("marks.trends.title")
                Spacer()
                Text("marks.trends.range90")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(trends.enumerated()), id: \.element.id) { index, trend in
                    MarksTrendChartRow(trend: trend)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)

                    if index < trends.count - 1 {
                        Divider()
                            .padding(.leading, Spacing.md)
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

private struct MarksTrendChartRow: View {
    let trend: SubjectGradeTrend

    var body: some View {
        let band = GradeMath.band(for: trend.latestAverage)

        HStack(spacing: Spacing.md) {
            AverageHistoryChart(points: points, band: band, style: .sparkline)
                .frame(width: 64, height: 26)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(band.soft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(trend.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            if let delta = trend.averageDelta {
                Text(String(format: "%+.2f", delta))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(delta > 0 ? GradeBand.poor.foregroundColor : Brand.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var points: [AveragePoint] {
        trend.events.compactMap { event in
            event.averageValue.map { AveragePoint(id: event.id, date: event.capturedAt, value: $0) }
        }
    }

    private var detail: String {
        let newMarks = trend.latestMarkCount - trend.firstMarkCount
        if newMarks > 0 {
            return String(format: String(localized: "marks.trends.newMarks"), newMarks)
        }
        return String(localized: "marks.trends.movement")
    }
}

// MARK: - Subject directory

private struct SubjectDirectory: View {
    let subjects: [Subject]
    @Binding var sortMode: SubjectSortMode
    let repository: SchoolRepository
    let absence: (Subject) -> AbsencePerSubject?
    let trend: (Subject) -> SubjectGradeTrend?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                SectionHeader("marks.directory.title")

                Picker(String(localized: "marks.sort.label"), selection: $sortMode) {
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
                                trend: trend(subject)
                            )
                        )
                    } label: {
                        SubjectRow(
                            subject: subject,
                            absence: absence(subject),
                            trend: trend(subject)
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
    let trend: SubjectGradeTrend?

    var body: some View {
        let average = GradeMath.subjectAverage(subject)
        let band = GradeMath.band(for: average)

        HStack(alignment: .center, spacing: Spacing.md) {
            SubjectAbbrevBadge(text: abbrev, band: band)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subject.trimmedName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: Spacing.sm) {
                    Text(String.localizedStringWithFormat(String(localized: "subject.markCount"), subject.marks.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let latestMark = subject.marks.first {
                        InlineMark(text: latestMark.displayText, band: GradeMath.band(for: latestMark))
                    }

                    if let delta = trendDelta {
                        HStack(spacing: 2) {
                            GradelyIcon(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                            Text(String(format: "%+.2f", delta))
                        }
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(delta < 0 ? Brand.primary : GradeBand.poor.foregroundColor)
                        .accessibilityLabel(trendAccessibilityLabel(for: delta))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(GradeMath.formattedAverage(average))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(band.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let absence {
                    Text(String(format: String(localized: "marks.row.absencePercent"), absence.absencePercentage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            GradelyIcon(systemName: "chevron.right")
                .font(.caption.weight(.bold))
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

    private var trendDelta: Double? {
        guard let delta = trend?.averageDelta, delta != 0 else { return nil }
        return delta
    }

    private func trendAccessibilityLabel(for delta: Double) -> String {
        delta < 0
            ? String(format: String(localized: "marks.row.trendBetter"), abs(delta))
            : String(format: String(localized: "marks.row.trendWorse"), delta)
    }
}

private struct SubjectAbbrevBadge: View {
    let text: String
    let band: GradeBand

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
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
            .font(.caption.weight(.bold).monospacedDigit())
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
