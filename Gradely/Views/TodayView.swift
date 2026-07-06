import SwiftUI

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @State private var absenceViewModel: AbsenceViewModel
    private let repository: SchoolRepository
    private let supportTipProvider: any SupportTipProviding
    private let accountHub: AnyView?
    private let onOpenMarks: () -> Void
    private let onOpenAbsence: () -> Void
    private let onSignedOut: () -> Void

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository,
        supportTipProvider: any SupportTipProviding,
        accountHub: AnyView? = nil,
        onOpenMarks: @escaping () -> Void,
        onOpenAbsence: @escaping () -> Void,
        onSignedOut: @escaping () -> Void
    ) {
        self.repository = repository
        self.supportTipProvider = supportTipProvider
        self.accountHub = accountHub
        self.onOpenMarks = onOpenMarks
        self.onOpenAbsence = onOpenAbsence
        self.onSignedOut = onSignedOut
        _viewModel = State(initialValue: TodayViewModel(
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: historyRepository
        ))
        _absenceViewModel = State(initialValue: AbsenceViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.snapshot.subjects.isEmpty {
                    ContentUnavailableView {
                        ProgressView().controlSize(.large)
                    } description: {
                        Text("Loading today...")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Today")
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .gradelyTopBarLeading) {
                    CreditsToolbarButton()
                }
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    Button {
                        Task {
                            await viewModel.refresh(forceRefresh: true)
                            await absenceViewModel.refresh(forceRefresh: false)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                    }
                    .disabled(viewModel.isLoading || viewModel.isRefreshing)
                    .accessibilityLabel(String(localized: "action.refresh"))
                    .accessibilityIdentifier("todayRefreshButton")
                }
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    AccountMenu(
                        user: viewModel.snapshot.user,
                        repository: repository,
                        supportTipProvider: supportTipProvider,
                        accountHub: accountHub,
                        onSignedOut: onSignedOut
                    )
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .task {
                await absenceViewModel.loadIfNeeded()
            }
            .sheet(isPresented: $absenceViewModel.isPredictionSheetPresented) {
                AbsencePredictionSheet(viewModel: absenceViewModel)
            }
            .alert(String(localized: "error.title"), isPresented: errorBinding) {
                Button(String(localized: "action.ok"), role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                accountSwitcher
                TodayHero(snapshot: viewModel.snapshot)

                Button {
                    onOpenMarks()
                } label: {
                    TodayNavigationRow(
                        title: "Marks",
                        subtitle: "Averages, subjects, trends, and calculator",
                        systemImage: "checkmark.seal.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayMarksShortcut")

                timetableCard
                absenceRiskCard
                absencePredictorCard
                lunchCard
                recentMarksCard

                NavigationLink {
                    GradeTrendsView(trends: viewModel.snapshot.gradeHistory.trends)
                } label: {
                    TodayNavigationRow(
                        title: "Grade trends",
                        subtitle: "30 days, 90 days, and school year movement",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayGradeTrendsLink")
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.gradelyGroupedBackground.ignoresSafeArea())
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
            await absenceViewModel.refresh(forceRefresh: false)
        }
        .accessibilityIdentifier("todayScrollView")
    }

    @ViewBuilder
    private var accountSwitcher: some View {
        if !viewModel.snapshot.linkedSchoolAccounts.isEmpty {
            Card(padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Brand.primary)
                        .frame(width: 34, height: 34)
                        .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(viewModel.snapshot.activeAccount?.displayName ?? "School account")
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.snapshot.activeAccount?.subtitle ?? "Linked accounts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Menu {
                        ForEach(viewModel.snapshot.linkedSchoolAccounts) { account in
                            Button {
                                Task { await viewModel.activateAccount(account) }
                            } label: {
                                Label(account.displayName, systemImage: account.id == viewModel.snapshot.activeAccount?.id ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: {
                        if viewModel.isActivatingAccountID != nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Brand.primary)
                                .frame(width: 34, height: 34)
                                .background(Brand.primary.opacity(0.12), in: Circle())
                        }
                    }
                    .accessibilityIdentifier("todayAccountSwitcher")
                }
            }
        }
    }

    private var timetableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Now and next")
                if let summary = viewModel.snapshot.timetableSummary {
                    if let current = summary.currentLesson {
                        TodayInfoRow(
                            title: current.title.isEmpty ? "Current lesson" : current.title,
                            subtitle: current.subjectName ?? current.hour.caption,
                            systemImage: "play.circle.fill",
                            tint: Brand.primary
                        )
                    } else if let next = summary.nextLesson {
                        TodayInfoRow(
                            title: next.title.isEmpty ? "Next lesson" : next.title,
                            subtitle: next.subjectName ?? next.hour.caption,
                            systemImage: "clock.fill",
                            tint: Brand.secondary
                        )
                    } else {
                        TodayInfoRow(title: "No more lessons", subtitle: "The school day is clear.", systemImage: "checkmark.circle.fill", tint: Brand.primary)
                    }

                    if summary.hasChanges {
                        Divider()
                        ForEach(summary.changedLessons.prefix(3)) { lesson in
                            TodayInfoRow(
                                title: lesson.changeKind.localizedLabel ?? "Timetable change",
                                subtitle: lesson.subjectName ?? lesson.title,
                                systemImage: "exclamationmark.triangle.fill",
                                tint: .gradelySystemOrange
                            )
                        }
                    }
                } else {
                    TodayInfoRow(title: "Timetable unavailable", subtitle: "Pull to refresh or open Timetable.", systemImage: "calendar", tint: .secondary)
                }
            }
        }
        .accessibilityIdentifier("todayTimetableCard")
    }

    private var absenceRiskCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    SectionHeader("Absence risk")
                    Spacer()
                    Button("Open") {
                        onOpenAbsence()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                }

                if let risk = viewModel.snapshot.absenceRisk, let highest = risk.highestRisk {
                    TodayRiskRow(subject: highest)
                    ForEach(risk.subjects.dropFirst().prefix(2)) { subject in
                        TodayRiskRow(subject: subject)
                    }
                    if risk.isThresholdUnavailable {
                        Text("School limit unavailable. Current percentages are shown without guessing a threshold.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TodayInfoRow(title: "No absence risk yet", subtitle: "Absence data will appear here after refresh.", systemImage: "calendar.badge.exclamationmark", tint: .secondary)
                }
            }
        }
        .accessibilityIdentifier("todayAbsenceRiskCard")
    }

    private var absencePredictorCard: some View {
        AbsencePredictorCard(
            result: absenceViewModel.predictionResult,
            onOpen: {
                absenceViewModel.openPredictionSheet()
            },
            onClear: {
                absenceViewModel.clearPredictionSelections()
            }
        )
    }

    private var lunchCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Lunch")
                if let meal = viewModel.snapshot.orderedMeal {
                    TodayInfoRow(title: meal.name, subtitle: meal.formattedPrice, systemImage: "fork.knife", tint: Brand.primary)
                } else if viewModel.snapshot.stravaSession != nil {
                    TodayInfoRow(title: "No ordered meal", subtitle: "Open Meals to order or check the menu.", systemImage: "fork.knife.circle", tint: .secondary)
                } else {
                    TodayInfoRow(title: "Meals not connected", subtitle: "Connect Strava.cz from Account.", systemImage: "fork.knife", tint: .secondary)
                }
            }
        }
        .accessibilityIdentifier("todayLunchCard")
    }

    private var recentMarksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("New marks and trends")
                if !viewModel.snapshot.gradeHistory.recentNewMarkEvents.isEmpty {
                    ForEach(viewModel.snapshot.gradeHistory.recentNewMarkEvents.prefix(3)) { event in
                        TodayInfoRow(
                            title: "\(event.markText) in \(event.subjectAbbrev ?? event.subjectName ?? "school")",
                            subtitle: event.createdAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "checkmark.seal.fill",
                            tint: Brand.primary
                        )
                    }
                    if !viewModel.snapshot.topTrends.isEmpty {
                        Divider()
                    }
                }

                if viewModel.snapshot.topTrends.isEmpty && viewModel.snapshot.gradeHistory.recentNewMarkEvents.isEmpty {
                    TodayInfoRow(title: "No cloud history yet", subtitle: "Trends start after Gradey records new grade snapshots.", systemImage: "chart.line.uptrend.xyaxis", tint: .secondary)
                } else {
                    ForEach(viewModel.snapshot.topTrends) { trend in
                        TrendRow(trend: trend)
                    }
                }
            }
        }
        .accessibilityIdentifier("todayGradeMovementCard")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}

private struct TodayHero: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(snapshot.user?.fullName ?? snapshot.activeAccount?.displayName ?? "Gradey")
                .font(.title2.weight(.bold))
                .foregroundStyle(Brand.onAccent)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Overall average")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.onAccent.opacity(0.7))
                    Text(GradeMath.formattedAverage(snapshot.overallAverage))
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.onAccent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("\(snapshot.subjects.count) subjects")
                    Text("\(snapshot.totalMarks) marks")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.onAccent.opacity(0.72))
            }
        }
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.24), radius: 16, x: 0, y: 8)
        .accessibilityIdentifier("todayHeroCard")
    }
}

private struct TodayNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Card(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .foregroundStyle(Brand.primary)
                    .frame(width: 38, height: 38)
                    .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TodayInfoRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TodayRiskRow: View {
    let subject: AbsenceRiskSubject

    var body: some View {
        HStack(spacing: Spacing.md) {
            Gauge(value: min(subject.percentage, subject.threshold ?? max(subject.percentage, 1)), in: 0...(subject.threshold ?? max(subject.percentage, 1))) {}
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subject.subjectName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f%%", subject.percentage))
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private var subtitle: String {
        guard let misses = subject.missesUntilLimit else {
            return "\(subject.missedLessons) / \(subject.totalLessons) missed lessons"
        }
        if misses == 0 {
            return "At or over the school limit"
        }
        return "\(misses) more missed lessons reaches the limit"
    }

    private var tint: Color {
        switch subject.level {
        case .overLimit, .high: .red
        case .watch: .gradelySystemOrange
        case .safe: Brand.primary
        case .unavailable: .secondary
        }
    }
}

struct TrendRow: View {
    let trend: SubjectGradeTrend

    var body: some View {
        HStack(spacing: Spacing.md) {
            TrendSparkline(events: trend.events)
                .frame(width: 76, height: 34)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(trend.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let delta = trend.averageDelta {
                Text(String(format: "%+.2f", delta))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(delta <= 0 ? Brand.primary : .red)
            }
        }
    }

    private var detail: String {
        let marks = trend.latestMarkCount - trend.firstMarkCount
        if marks > 0 {
            return "\(marks) new marks"
        }
        return "Average movement"
    }
}

struct TrendSparkline: View {
    let events: [GradeHistoryEvent]

    var body: some View {
        GeometryReader { proxy in
            let values = events.compactMap(\.averageValue)
            Path { path in
                guard values.count > 1,
                      let minValue = values.min(),
                      let maxValue = values.max()
                else { return }
                let range = max(maxValue - minValue, 0.01)
                for index in values.indices {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let yRatio = (values[index] - minValue) / range
                    let y = proxy.size.height - (proxy.size.height * CGFloat(yRatio))
                    if index == values.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Brand.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .padding(6)
        .background(Brand.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

struct GradeTrendsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case thirty = "30 days"
        case ninety = "90 days"
        case schoolYear = "School year"

        var id: String { rawValue }
    }

    let trends: [SubjectGradeTrend]
    @State private var selectedRange: Range = .ninety

    var body: some View {
        List {
            Picker("Range", selection: $selectedRange) {
                ForEach(Range.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if trends.isEmpty {
                ContentUnavailableView("No grade history", systemImage: "chart.line.uptrend.xyaxis", description: Text("Cloud trends start after Gradey records grade snapshots."))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTrends) { trend in
                    TrendRow(trend: trend)
                }
            }
        }
        .navigationTitle("Grade trends")
        .gradelyNavigationTitleDisplayMode(.inline)
    }

    private var filteredTrends: [SubjectGradeTrend] {
        let cutoff: Date?
        switch selectedRange {
        case .thirty:
            cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .ninety:
            cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())
        case .schoolYear:
            cutoff = nil
        }

        guard let cutoff else { return trends }
        return trends.compactMap { trend in
            let events = trend.events.filter { $0.capturedAt >= cutoff }
            guard !events.isEmpty else { return nil }
            return SubjectGradeTrend.make(from: events).first
        }
    }
}
