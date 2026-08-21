import SwiftUI

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @State private var reconnectAccount: LinkedAccount?
    private let accountHub: AnyView?
    private let repository: SchoolRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let onOpenGradeyAI: () -> Void
    private let onOpenAbsence: () -> Void
    @AppStorage("settings.showMealsTab") private var showMealsTab = true

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        accountSettingsClient: (any GradeyAccountSettingsClient)? = nil,
        gradeyAuthClient: (any GradeyAuthClient)? = nil,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {},
        onOpenAbsence: @escaping () -> Void
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        self.onOpenAbsence = onOpenAbsence
        _viewModel = State(initialValue: TodayViewModel(
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: historyRepository,
            accountSettingsClient: accountSettingsClient,
            gradeyAuthClient: gradeyAuthClient
        ))
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
                    GradeyAIToolbarButton(onOpen: onOpenGradeyAI)
                }
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    Button {
                        Task {
                            await viewModel.refresh(forceRefresh: true)
                        }
                    } label: {
                        GradelyIcon(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                    }
                    .disabled(viewModel.isLoading || viewModel.isRefreshing)
                    .accessibilityLabel(AppL10n.string("action.refresh"))
                    .accessibilityIdentifier("todayRefreshButton")
                }
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    AccountSettingsButton(accountHub: accountHub)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
                Button(AppL10n.string("action.ok"), role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(item: $reconnectAccount) { account in
                TodaySchoolReconnectSheet(
                    account: account,
                    prefill: viewModel.loginPrefill(for: account),
                    repository: repository,
                    schoolDirectoryProvider: schoolDirectoryProvider
                ) { account in
                    let didReconnect = await viewModel.reconnect(account)
                    let reconnectError = didReconnect ? nil : viewModel.errorMessage
                    viewModel.clearError()
                    return reconnectError
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                accountSwitcher
                if let account = viewModel.accountRequiringReconnect {
                    schoolConnectionNotice(account)
                }
                TodayHero(snapshot: viewModel.snapshot)
                timetableCard
                absenceRiskCard
                if showMealsTab {
                    lunchCard
                }
                recentMarksCard
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
        }
        .accessibilityIdentifier("todayScrollView")
    }

    private func schoolConnectionNotice(_ account: LinkedAccount) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    GradelyIcon(systemName: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.gradelySystemOrange)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("School connection needs attention")
                            .font(.headline)
                        Text(account.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Text(account.actionRequiredReason ?? "Reconnect to keep marks and notifications up to date.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    reconnectAccount = account
                } label: {
                    GradelyLabel("settings.connected.reconnect", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gradelySystemOrange)
                .accessibilityIdentifier("todaySchoolReconnectButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todaySchoolConnectionNotice")
    }

    @ViewBuilder
    private var accountSwitcher: some View {
        if !viewModel.snapshot.linkedSchoolAccounts.isEmpty {
            Card(padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    GradelyIcon(systemName: "person.2.fill")
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
                        Picker(selection: selectedSchoolAccountID) {
                            ForEach(viewModel.snapshot.linkedSchoolAccounts) { account in
                                Text(verbatim: account.displayName)
                                    .tag(account.id)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    } label: {
                        if viewModel.isActivatingAccountID != nil {
                            ProgressView().controlSize(.small)
                        } else {
                            GradelyIcon(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Brand.primary)
                                .frame(width: 34, height: 34)
                                .background(Brand.primary.opacity(0.12), in: Circle())
                        }
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .disabled(viewModel.isActivatingAccountID != nil)
                    .accessibilityLabel(
                        viewModel.snapshot.activeAccount?.displayName ?? "School account"
                    )
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
        let newMarks = viewModel.snapshot.newMarks

        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("New marks and trends")
                if !newMarks.isEmpty {
                    ForEach(newMarks.prefix(3)) { mark in
                        TodayInfoRow(
                            title: "\(mark.markText) in \(mark.subjectName)",
                            subtitle: mark.detectedAt?.formatted(date: .abbreviated, time: .shortened) ?? "New from school",
                            systemImage: "checkmark.seal.fill",
                            tint: Brand.primary
                        )
                    }
                    if !viewModel.snapshot.topTrends.isEmpty {
                        Divider()
                    }
                }

                if viewModel.snapshot.topTrends.isEmpty {
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

    private var selectedSchoolAccountID: Binding<String> {
        Binding(
            get: { viewModel.snapshot.activeAccount?.id ?? "" },
            set: { id in
                guard let account = viewModel.snapshot.linkedSchoolAccounts.first(where: { $0.id == id }) else {
                    return
                }
                Task { await viewModel.activateAccount(account) }
            }
        )
    }

}

private struct TodaySchoolReconnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isCompletingReconnect = false
    @State private var errorMessage: String?

    let account: LinkedAccount
    let prefill: SchoolLoginPrefill?
    let repository: SchoolRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let onReconnect: (LinkedAccount) async -> String?

    var body: some View {
        LoginView(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            presentationContext: .reconnecting,
            prefill: prefill
        ) {
            isCompletingReconnect = true
            Task {
                errorMessage = await onReconnect(account)
                isCompletingReconnect = false
                if errorMessage == nil {
                    dismiss()
                }
            }
        }
        .disabled(isCompletingReconnect)
        .overlay {
            if isCompletingReconnect {
                ProgressView()
                    .controlSize(.large)
                    .padding(Spacing.xl)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
            Button(AppL10n.string("action.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("todaySchoolReconnectSheet")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
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
                GradelyIcon(systemName: systemImage)
                    .foregroundStyle(Brand.primary)
                    .frame(width: 38, height: 38)
                    .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                GradelyIcon(systemName: "chevron.right")
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
            GradelyIcon(systemName: systemImage)
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
        HStack(alignment: .center, spacing: Spacing.md) {
            AbsenceRiskRing(
                percentage: subject.percentage,
                threshold: subject.threshold,
                level: subject.level
            )
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subject.subjectName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(String(format: "%.0f%%", subject.percentage))
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(minHeight: 44)
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
                ContentUnavailableView {
                    GradelyLabel(
                        "No grade history",
                        systemImage: "chart.line.uptrend.xyaxis",
                        iconSize: 28
                    )
                } description: {
                    Text("Cloud trends start after Gradey records grade snapshots.")
                }
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
