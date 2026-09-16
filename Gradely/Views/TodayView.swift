import SwiftUI

struct TodayView: View {
    @Environment(\.requestGradeyAIAction) private var requestAI
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: TodayViewModel
    @State private var reconnectAccount: LinkedAccount?
    @Environment(\.scenePhase) private var scenePhase
    private let accountHub: AnyView?
    private let repository: SchoolRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let onOpenGradeyAI: () -> Void
    private let onOpenAbsence: () -> Void
    private let onOpenTimetable: (() -> Void)?
    private let onOpenMarks: (() -> Void)?
    private let snapshotStore: SchoolSnapshotStore?
    @AppStorage("settings.showMealsTab") private var showMealsTab = true

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository,
        historyRepository: GradeyHistoryRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        accountSettingsClient: (any GradeyAccountSettingsClient)? = nil,
        gradeyAuthClient: (any GradeyAuthClient)? = nil,
        snapshotStore: SchoolSnapshotStore? = nil,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {},
        onOpenAbsence: @escaping () -> Void,
        onOpenTimetable: (() -> Void)? = nil,
        onOpenMarks: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        self.onOpenAbsence = onOpenAbsence
        self.onOpenTimetable = onOpenTimetable
        self.onOpenMarks = onOpenMarks
        self.snapshotStore = snapshotStore
        _viewModel = State(initialValue: TodayViewModel(
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: historyRepository,
            accountSettingsClient: accountSettingsClient,
            gradeyAuthClient: gradeyAuthClient,
            snapshotStore: snapshotStore
        ))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(at: context.date)
                    .task(id: context.date) { viewModel.refreshTime(at: context.date) }
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
            .onChange(of: snapshotStore?.revision) { _, _ in viewModel.applySharedSnapshot() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshTime()
                    Task { await viewModel.refresh(forceRefresh: false) }
                }
            }
            .navigationDestination(for: TodayInsight.Destination.self) { destination in
                insightDestination(destination)
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

    // MARK: - Layout

    private func content(at now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let account = viewModel.accountRequiringReconnect {
                    schoolConnectionNotice(account)
                }
                TodayHero(
                    snapshot: viewModel.snapshot,
                    now: now,
                    isRefreshing: viewModel.isRefreshing,
                    isActivatingAccount: viewModel.isActivatingAccountID != nil,
                    selectedAccountID: selectedSchoolAccountID
                )
                if viewModel.isLoading {
                    loadingRow
                }
                dayCard(at: now)
                attentionCard(at: now)
                gradeyActions
                recentMarksCard
                plannerCard(at: now)
                if let risk = viewModel.snapshot.absenceRisk, let highest = risk.highestRisk {
                    absenceRiskCard(risk, highest: highest)
                }
                if showMealsTab, viewModel.snapshot.stravaSession != nil {
                    lunchCard
                }
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

    private var loadingRow: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("today.refreshing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("todayLoadingIndicator")
    }

    // MARK: - School connection

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

                Text(account.actionRequiredReason ?? AppL10n.string("today.reconnect.fallback"))
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

    // MARK: - Day card

    private func dayCard(at now: Date) -> some View {
        let snapshot = viewModel.snapshot
        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Now and next")
                    if let onOpenTimetable {
                        Button(action: onOpenTimetable) {
                            TodayLinkLabel(title: "rozvrh.title")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayOpenTimetableButton")
                    }
                }

                if let summary = snapshot.timetableSummary {
                    if !snapshot.todayLessons.isEmpty {
                        TodayLessonStrip(lessons: snapshot.todayLessons, summary: summary, now: now)
                    }

                    if let current = summary.currentLesson {
                        TodayLessonRow(lesson: current, role: .current, minutes: summary.minutesRemainingInCurrent)
                    }
                    if let next = summary.nextLesson {
                        TodayLessonRow(
                            lesson: next,
                            role: .next,
                            minutes: summary.currentLesson == nil ? summary.minutesUntilNext : nil
                        )
                    }
                    if summary.currentLesson == nil, summary.nextLesson == nil {
                        if summary.state == .empty {
                            TodayInfoRow(
                                title: Text("timetable.summary.empty.title"),
                                subtitle: Text("timetable.summary.empty.message"),
                                icon: "sun-01",
                                tint: Brand.primary
                            )
                        } else {
                            TodayInfoRow(
                                title: Text("today.noMoreLessons"),
                                subtitle: Text("today.noMoreLessons.subtitle"),
                                icon: "checkmark-circle-02",
                                tint: Brand.primary
                            )
                        }
                    }

                    if summary.hasChanges {
                        Divider()
                        HStack(spacing: Spacing.sm) {
                            GradelyIcon("alert-02", size: 14)
                            Text(verbatim: changeSummary(summary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LessonChangeKind.canceled.color)
                        ForEach(summary.changedLessons.prefix(3)) { lesson in
                            TodayInfoRow(
                                title: Text(verbatim: lesson.changeKind.localizedLabel ?? AppL10n.string("today.timetableChange")),
                                subtitle: Text(verbatim: changeSubtitle(for: lesson)),
                                icon: "alert-02",
                                tint: lesson.changeKind.color
                            )
                            .accessibilityIdentifier("todayTimetableChange-\(lesson.id)")
                        }
                    }
                } else {
                    TodayInfoRow(
                        title: Text("today.timetableUnavailable"),
                        subtitle: Text("today.timetableUnavailable.subtitle"),
                        icon: "calendar-03",
                        tint: .secondary
                    )
                }

                if let snapshotStore, snapshotStore.cachedWeek(containing: now) != nil,
                   snapshotStore.sourceState("timetable-\(TimetableDates.apiDateString(TimetableDates.monday(of: now)))").isStale(at: now, interval: 900) {
                    Text("today.cached.warning").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("todayTimetableCard")
    }

    private func changeSummary(_ summary: TimetableTodaySummary) -> String {
        let count = summary.changedLessons.count
        if count == 1, let lesson = summary.changedLessons.first {
            return String(format: AppL10n.string("timetable.summary.changes.one"), TodayLessonCopy.subject(for: lesson))
        }
        let key: String.LocalizationValue = (2...4).contains(count)
            ? "timetable.summary.changes.few"
            : "timetable.summary.changes.many"
        return String(format: AppL10n.string(key), count)
    }

    /// Cancelled atoms often carry the subject only inside the change payload,
    /// so the row falls back to it before showing a bare period number.
    private func changeSubtitle(for lesson: ScheduledLesson) -> String {
        var parts: [String] = []
        if let subject = TodayLessonCopy.optionalSubject(for: lesson) {
            parts.append(subject)
        } else if let description = lesson.change?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !description.isEmpty {
            parts.append(description)
        }
        parts.append(TodayLessonCopy.period(for: lesson))
        if let room = TodayLessonCopy.room(for: lesson) {
            parts.append(room)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Attention

    private func attentionCard(at now: Date) -> some View {
        let insights = snapshotStore?.todayInsights(at: now) ?? []
        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("today.attention.title")
                    if !insights.isEmpty {
                        StatusChip(text: "\(insights.count)", color: Brand.primary)
                    }
                }
                if insights.isEmpty {
                    TodayInfoRow(
                        title: Text("today.attention.emptyTitle"),
                        subtitle: Text("today.attention.empty"),
                        icon: "checkmark-circle-02",
                        tint: Brand.primary
                    )
                } else {
                    ForEach(insights) { insight in
                        NavigationLink(value: insight.destination) {
                            TodayInsightRow(insight: insight, subtitle: insightSubtitle(insight))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { snapshotStore?.markSeen([insight]) })
                        .accessibilityIdentifier("todayInsight-\(insight.id)")
                    }
                }
                if let snapshotStore, snapshotStore.sourceState("marks").error != nil {
                    Text("today.cached.warning").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("todayAttentionCard")
    }

    // MARK: - Gradey AI

    private var gradeyActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("today.ai.title")
                .padding(.horizontal, Spacing.xs)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.sm) {
                    studyPrioritiesAction(expandsVertically: false)
                    weekSummaryAction(expandsVertically: false)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    studyPrioritiesAction(expandsVertically: true)
                    weekSummaryAction(expandsVertically: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func studyPrioritiesAction(expandsVertically: Bool) -> some View {
        gradeyAction(
            .studyPriorities,
            title: "gradey.ai.action.study_priorities",
            subtitle: "today.ai.studyPriorities.subtitle",
            icon: "target-02",
            identifier: "todayStudyPrioritiesButton",
            expandsVertically: expandsVertically
        )
    }

    private func weekSummaryAction(expandsVertically: Bool) -> some View {
        gradeyAction(
            .weekSummary,
            title: "gradey.ai.action.week_summary",
            subtitle: "today.ai.weekSummary.subtitle",
            icon: "calendar-check-in-02",
            identifier: "todayWeekSummaryButton",
            expandsVertically: expandsVertically
        )
    }

    private func gradeyAction(
        _ action: GradeyAIAction,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String,
        identifier: String,
        expandsVertically: Bool
    ) -> some View {
        Button { requestAI(action, nil, nil) } label: {
            TodayActionCardLabel(title: title, subtitle: subtitle, icon: icon, expandsVertically: expandsVertically)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Recent marks

    private var recentMarksCard: some View {
        let marks = viewModel.snapshot.recentMarks(limit: 3)
        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("today.recentGrades.title")
                    if let onOpenMarks {
                        Button(action: onOpenMarks) {
                            TodayLinkLabel(title: "subjects.title")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayOpenMarksButton")
                    }
                }
                if marks.isEmpty {
                    TodayInfoRow(
                        title: Text("today.recentGrades.title"),
                        subtitle: Text("today.recentGrades.empty"),
                        icon: "checkmark-badge-02",
                        tint: .secondary
                    )
                } else {
                    ForEach(marks) { mark in
                        NavigationLink(value: TodayInsight.Destination.subject(mark.subjectID)) {
                            TodayMarkRow(mark: mark)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayRecentMark-\(mark.id)")
                    }
                }
            }
        }
        .accessibilityIdentifier("todayGradeMovementCard")
    }

    // MARK: - Planner

    @ViewBuilder private func plannerCard(at now: Date) -> some View {
        if let snapshotStore {
            let events = snapshotStore.events
                .filter { $0.expiresAt > now }
                .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
                .prefix(3)
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("planner.title")
                        NavigationLink(value: TodayInsight.Destination.planner) {
                            TodayLinkLabel(title: "action.open")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayOpenPlannerButton")
                    }
                    if events.isEmpty {
                        TodayInfoRow(
                            title: Text("planner.title"),
                            subtitle: Text("today.planner.empty"),
                            icon: "check-list",
                            tint: .secondary
                        )
                    } else {
                        ForEach(Array(events)) { event in
                            NavigationLink(value: TodayInsight.Destination.plannerItem(event.id)) {
                                TodayPlannerRow(event: event)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("todayPlannerEvent-\(event.id.uuidString)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("todayPlannerCard")
        }
    }

    // MARK: - Absence & lunch

    private func absenceRiskCard(_ risk: AbsenceRiskSummary, highest: AbsenceRiskSubject) -> some View {
        let others = risk.subjects.filter { $0.id != highest.id }.prefix(2)
        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Absence risk")
                    Button(action: onOpenAbsence) {
                        TodayLinkLabel(title: "action.open")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todayOpenAbsenceButton")
                }

                TodayRiskRow(subject: highest)
                ForEach(Array(others)) { subject in
                    TodayRiskRow(subject: subject)
                }
                if risk.isThresholdUnavailable {
                    Text("School limit unavailable. Current percentages are shown without guessing a threshold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    TodayInfoRow(
                        title: Text(verbatim: meal.name),
                        subtitle: Text(verbatim: meal.formattedPrice),
                        icon: "restaurant-02",
                        tint: Brand.primary
                    )
                } else {
                    TodayInfoRow(
                        title: Text("today.noMeal"),
                        subtitle: Text("today.noMeal.subtitle"),
                        icon: "restaurant-02",
                        tint: .secondary
                    )
                }
            }
        }
        .accessibilityIdentifier("todayLunchCard")
    }

    // MARK: - Navigation

    @ViewBuilder private func insightDestination(_ destination: TodayInsight.Destination) -> some View {
        switch destination {
        case .subject(let id):
            if let subject = viewModel.snapshot.subjects.first(where: { $0.id == id }) {
                SubjectDetailView(viewModel: SubjectDetailViewModel(subject: subject, absence: nil,
                    repository: repository, prepared: snapshotStore?.preparedCalculations[id]), snapshotStore: snapshotStore)
            } else { ContentUnavailableView("today.destination.unavailable", systemImage: "book.closed") }
        case .plannerItem(let id):
            if let snapshotStore, let item = snapshotStore.plannerStore.items.first(where: { $0.id == id }) {
                PlannerItemEditorView(item: item, store: snapshotStore.plannerStore, resolver: PlannerLessonResolver(repository: repository),
                    displayedWeek: snapshotStore.cachedWeek(containing: item.orderingDate ?? Date()), subjects: plannerSubjects)
            } else { ContentUnavailableView("today.destination.unavailable", systemImage: "checklist") }
        case .planner:
            if let snapshotStore {
                PlannerView(store: snapshotStore.plannerStore, resolver: PlannerLessonResolver(repository: repository),
                    displayedWeek: snapshotStore.cachedWeek(containing: Date()), subjects: plannerSubjects)
            } else { ContentUnavailableView("today.destination.unavailable", systemImage: "checklist") }
        }
    }

    private var plannerSubjects: [PlannerSubjectReference] {
        guard let scope = snapshotStore?.scope else { return [] }
        return viewModel.snapshot.subjects.map {
            PlannerSubjectReference(scope: scope, id: $0.id, name: $0.trimmedName, abbreviation: $0.trimmedAbbrev)
        }
    }

    private func insightSubtitle(_ insight: TodayInsight) -> String {
        if let eventID = insight.eventIDs.first {
            if let event = snapshotStore?.events.first(where: { $0.id == eventID }) {
                return SchoolDateFormatting.eventDate(event, includeTime: false)
            }
            return SchoolDateFormatting.date(insight.relevantAt)
        }
        return AppL10n.string("today.insight.recordedAverage")
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

// MARK: - Lesson copy helpers

/// Shared wording for lessons on Today so the hero, strip and rows agree.
private enum TodayLessonCopy {
    static func subject(for lesson: ScheduledLesson) -> String {
        optionalSubject(for: lesson) ?? AppL10n.string("timetable.summary.lessonFallback")
    }

    static func optionalSubject(for lesson: ScheduledLesson) -> String? {
        if let name = lesson.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if !lesson.title.isEmpty { return lesson.title }
        if let changeSubject = lesson.change?.changeSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !changeSubject.isEmpty {
            return changeSubject
        }
        return nil
    }

    static func shortSubject(for lesson: ScheduledLesson) -> String {
        if !lesson.title.isEmpty { return lesson.title }
        if let changeSubject = lesson.change?.changeSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !changeSubject.isEmpty {
            return changeSubject
        }
        return "–"
    }

    static func timeRange(for lesson: ScheduledLesson) -> String? {
        guard !lesson.hour.beginTime.isEmpty, !lesson.hour.endTime.isEmpty else { return nil }
        return "\(lesson.hour.beginTime)–\(lesson.hour.endTime)"
    }

    static func period(for lesson: ScheduledLesson) -> String {
        [lesson.hour.caption, timeRange(for: lesson)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func room(for lesson: ScheduledLesson) -> String? {
        let room = (lesson.roomAbbrev ?? lesson.roomName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let room, !room.isEmpty else { return nil }
        return room
    }

    static func teacher(for lesson: ScheduledLesson) -> String? {
        let teacher = (lesson.teacherName ?? lesson.teacherAbbrev)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let teacher, !teacher.isEmpty else { return nil }
        return teacher
    }

    /// Countdowns only help for the next couple of hours; further out the
    /// start time is easier to read than "in 436 min".
    static let countdownLimitMinutes = 120

    static func startsIn(_ lesson: ScheduledLesson, minutes: Int?) -> String? {
        if let minutes, minutes <= countdownLimitMinutes {
            return String(format: AppL10n.string("today.lesson.startsIn"), minutes)
        }
        guard !lesson.hour.beginTime.isEmpty else {
            return minutes.map { String(format: AppL10n.string("today.lesson.startsIn"), $0) }
        }
        return String(format: AppL10n.string("today.lesson.startsAt"), lesson.hour.beginTime)
    }

    static func nextLessonSummary(_ lesson: ScheduledLesson, minutes: Int?) -> String {
        let subject = subject(for: lesson)
        if let minutes, minutes <= countdownLimitMinutes {
            return String(format: AppL10n.string("timetable.summary.nextIn"), subject, minutes)
        }
        guard !lesson.hour.beginTime.isEmpty else {
            return String(format: AppL10n.string("timetable.summary.nextIs"), subject)
        }
        return String(format: AppL10n.string("today.lesson.nextAt"), subject, lesson.hour.beginTime)
    }
}

// MARK: - Hero

private struct TodayHero: View {
    let snapshot: TodaySnapshot
    let now: Date
    let isRefreshing: Bool
    let isActivatingAccount: Bool
    @Binding var selectedAccountID: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    accountChip
                    dateRow
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    dateRow
                    Spacer(minLength: Spacing.sm)
                    accountChip
                }
            }

            Text(verbatim: greeting)
                .font(.gradelyDisplay(size: 30, relativeTo: .title))
                .foregroundStyle(Brand.onAccent)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            statusPanel

            statTiles
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.24), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayHeroCard")
    }

    private var dateRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(verbatim: dateText)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Brand.onAccent.opacity(0.72))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Brand.onAccent)
            }
        }
    }

    // MARK: Account chip

    @ViewBuilder private var accountChip: some View {
        if let label = snapshot.accountChipLabel {
            let canSwitch = snapshot.linkedSchoolAccounts.count > 1
            let chip = HStack(spacing: Spacing.xs) {
                if !dynamicTypeSize.isAccessibilitySize {
                    GradelyIcon("user-group", size: 13)
                }
                Text(verbatim: label)
                    .lineLimit(1)
                if canSwitch {
                    GradelyIcon("arrow-data-transfer-vertical", size: 12)
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Brand.onAccent)
            .padding(.horizontal, Spacing.sm + 2)
            .frame(minHeight: 30)
            .background(.white.opacity(0.22), in: Capsule())
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : 190, alignment: .trailing)

            if canSwitch {
                Menu {
                    Picker(selection: $selectedAccountID) {
                        ForEach(snapshot.linkedSchoolAccounts) { account in
                            Text(verbatim: account.displayName)
                                .tag(account.id)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    if isActivatingAccount {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Brand.onAccent)
                            .frame(minHeight: 30)
                    } else {
                        chip
                    }
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .disabled(isActivatingAccount)
                .accessibilityLabel(snapshot.activeAccount?.displayName ?? AppL10n.string("today.schoolAccount"))
                .accessibilityIdentifier("todayAccountSwitcher")
            } else {
                chip
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(snapshot.activeAccount?.displayName ?? label)
                    .accessibilityIdentifier("todayAccountSwitcher")
            }
        }
    }

    // MARK: Status

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(statusIcon, size: 18)
                .foregroundStyle(Brand.onAccent)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.22), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: statusTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .fixedSize(horizontal: false, vertical: true)
                if let statusSubtitle {
                    Text(verbatim: statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.onAccent.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let progress = snapshot.currentLessonProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Brand.onAccent.opacity(0.14))
                            Capsule()
                                .fill(Brand.onAccent)
                                .frame(width: max(geo.size.width * progress, 6))
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, Spacing.xs)
                    .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("todayHeroStatus")
    }

    private var statusIcon: String {
        guard let summary = snapshot.timetableSummary else { return "calendar-03" }
        switch summary.state {
        case .empty: return "sun-01"
        case .beforeSchool: return "sunrise"
        case .current: return "play-circle"
        case .betweenLessons: return "coffee-02"
        case .afterSchool: return "checkmark-circle-02"
        }
    }

    private var statusTitle: String {
        guard let summary = snapshot.timetableSummary else {
            return AppL10n.string("today.timetableUnavailable")
        }
        switch summary.state {
        case .empty:
            return AppL10n.string("timetable.summary.empty.title")
        case .beforeSchool:
            return AppL10n.string("timetable.summary.beforeSchool.title")
        case .current:
            return String(
                format: AppL10n.string("timetable.summary.now.title"),
                summary.currentLesson.map { TodayLessonCopy.subject(for: $0) } ?? AppL10n.string("timetable.summary.lessonFallback")
            )
        case .betweenLessons:
            return AppL10n.string("timetable.summary.between.title")
        case .afterSchool:
            return AppL10n.string("timetable.summary.after.title")
        }
    }

    private var statusSubtitle: String? {
        guard let summary = snapshot.timetableSummary else {
            return AppL10n.string("today.timetableUnavailable.subtitle")
        }
        switch summary.state {
        case .empty:
            return AppL10n.string("timetable.summary.empty.message")
        case .beforeSchool, .betweenLessons:
            guard let next = summary.nextLesson else { return nil }
            return TodayLessonCopy.nextLessonSummary(next, minutes: summary.minutesUntilNext)
        case .current:
            guard let minutes = summary.minutesRemainingInCurrent else { return nil }
            return String(format: AppL10n.string("timetable.summary.remaining"), minutes)
        case .afterSchool:
            return AppL10n.string(summary.hasChanges ? "timetable.summary.after.changes" : "timetable.summary.after.done")
        }
    }

    // MARK: Stats

    @ViewBuilder private var statTiles: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.md) {
                averageTile
                lessonsTile
                newMarksTile
            }
        } else {
            HStack(alignment: .bottom, spacing: Spacing.md) {
                averageTile
                statDivider
                lessonsTile
                statDivider
                newMarksTile
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Brand.onAccent.opacity(0.14))
            .frame(width: 1, height: 30)
            .accessibilityHidden(true)
    }

    private var averageTile: some View {
        StatTile(title: AppL10n.string("today.hero.average"), value: GradeMath.formattedAverage(snapshot.overallAverage))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("todayStatAverage")
    }

    private var lessonsTile: some View {
        StatTile(
            title: AppL10n.string("today.hero.lessonsToday"),
            value: snapshot.timetableSummary == nil ? "–" : String(snapshot.activeLessonCount)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("todayStatLessons")
    }

    private var newMarksTile: some View {
        StatTile(title: AppL10n.string("today.hero.newMarks"), value: String(snapshot.newMarks.count))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("todayStatNewMarks")
    }

    // MARK: Copy

    private var dateText: String {
        now.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).weekday(.wide).day().month(.wide))
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let key: String.LocalizationValue
        switch hour {
        case 5..<12: key = "today.greeting.morning"
        case 12..<18: key = "today.greeting.afternoon"
        default: key = "today.greeting.evening"
        }
        guard let name = snapshot.greetingName, !name.isEmpty else { return AppL10n.string(key) }
        return AppL10n.string(key) + ", " + name
    }
}

// MARK: - Lesson strip

private struct TodayLessonStrip: View {
    let lessons: [ScheduledLesson]
    let summary: TimetableTodaySummary
    let now: Date

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(lessons) { lesson in
                        TodayLessonChip(lesson: lesson, state: state(for: lesson))
                            .id(lesson.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Spacing.lg, for: .scrollContent)
            .padding(.horizontal, -Spacing.lg)
            .onAppear {
                if let focusID {
                    proxy.scrollTo(focusID, anchor: .center)
                }
            }
        }
        .accessibilityIdentifier("todayLessonStrip")
    }

    private var focusID: String? {
        summary.currentLesson?.id ?? summary.nextLesson?.id
    }

    private func state(for lesson: ScheduledLesson) -> TodayLessonChip.State {
        if lesson.isCanceled { return .cancelled }
        if summary.currentLesson?.id == lesson.id { return .current }
        if let end = TimetableLessonTiming.date(lesson.hour.endTime, on: now), end <= now {
            return .past
        }
        return .upcoming
    }
}

private struct TodayLessonChip: View {
    enum State { case past, current, upcoming, cancelled }

    let lesson: ScheduledLesson
    let state: State

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: lesson.hour.caption)
                .font(.caption2.weight(.bold).monospacedDigit())
                .opacity(0.8)
            Text(verbatim: TodayLessonCopy.shortSubject(for: lesson))
                .font(.subheadline.weight(.bold))
                .strikethrough(state == .cancelled)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 54, minHeight: 44)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if lesson.changeKind != .none, lesson.changeKind != .canceled {
                Circle()
                    .fill(lesson.changeKind.color)
                    .frame(width: 7, height: 7)
                    .padding(5)
            }
        }
        .opacity(state == .past ? 0.62 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("todayLessonChip-\(lesson.id)")
    }

    private var foreground: Color {
        switch state {
        case .current: Brand.onAccent
        case .upcoming: .primary
        case .past: .secondary
        case .cancelled: LessonChangeKind.canceled.color
        }
    }

    private var background: AnyShapeStyle {
        switch state {
        case .current: AnyShapeStyle(Brand.gradient)
        case .upcoming: AnyShapeStyle(Brand.primary.opacity(0.10))
        case .past: AnyShapeStyle(Color.gradelyTertiaryFill)
        case .cancelled: AnyShapeStyle(LessonChangeKind.canceled.color.opacity(0.12))
        }
    }

    private var accessibilityText: String {
        [
            lesson.hour.caption,
            TodayLessonCopy.subject(for: lesson),
            TodayLessonCopy.timeRange(for: lesson),
            lesson.changeKind.localizedLabel,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

// MARK: - Rows

private struct TodayLessonRow: View {
    enum Role { case current, next }

    let lesson: ScheduledLesson
    let role: Role
    let minutes: Int?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text(verbatim: lesson.hour.caption)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(roleTitle)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .kerning(0.4)
                        .foregroundStyle(tint)
                    if let minutesText {
                        Text(verbatim: minutesText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: TodayLessonCopy.subject(for: lesson))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                detailRow
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(role == .current ? "todayCurrentLessonRow" : "todayNextLessonRow")
    }

    private var detailRow: some View {
        HStack(spacing: Spacing.sm + 2) {
            if let time = TodayLessonCopy.timeRange(for: lesson) {
                Text(verbatim: time)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            if let room = TodayLessonCopy.room(for: lesson) {
                detailItem(icon: "location-01", text: room)
                    .layoutPriority(1)
            }
            if let teacher = TodayLessonCopy.teacher(for: lesson) {
                detailItem(icon: "teacher", text: teacher)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func detailItem(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            GradelyIcon(icon, size: 11)
            Text(verbatim: text)
                .truncationMode(.tail)
        }
    }

    private var tint: Color {
        role == .current ? Brand.primary : Brand.secondary
    }

    private var roleTitle: LocalizedStringKey {
        role == .current ? "today.currentLesson" : "today.nextLesson"
    }

    private var minutesText: String? {
        switch role {
        case .current:
            guard let minutes else { return nil }
            return String(format: AppL10n.string("timetable.summary.remaining"), minutes)
        case .next:
            return TodayLessonCopy.startsIn(lesson, minutes: minutes)
        }
    }
}

private struct TodayInsightRow: View {
    let insight: TodayInsight
    let subtitle: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            GradelyIcon(icon, size: 16)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: insight.title)
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            TodayDisclosureIcon()
        }
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch insight.kind {
        case .assessment: "edit-02"
        case .busyTests: "task-daily-02"
        case .deadline: "check-list"
        case .averageChange: "chart-line-data-01"
        case .worseningTrend: "chart-down"
        case .recentGrade: "checkmark-badge-02"
        }
    }

    private var tint: Color {
        switch insight.kind {
        case .assessment, .busyTests: GradeBand.average.foregroundColor
        case .deadline: .gradelySystemPurple
        case .worseningTrend: GradeBand.poor.foregroundColor
        case .averageChange, .recentGrade: Brand.primary
        }
    }
}

private struct TodayMarkRow: View {
    let mark: TodayNewMark

    var body: some View {
        HStack(spacing: Spacing.md) {
            GradeBadge(text: mark.markText, band: mark.band, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs + 2) {
                    Text(verbatim: mark.subjectTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if mark.isNew {
                        Circle()
                            .fill(Brand.primary)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: mark.caption ?? mark.subjectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(verbatim: dateText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TodayDisclosureIcon()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        mark.detectedAt.map { SchoolDateFormatting.date($0) } ?? "–"
    }
}

private struct TodayPlannerRow: View {
    let event: SchoolEvent

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(spacing: 0) {
                Text(verbatim: event.date.formatted(dateStyle.day()))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(verbatim: event.date.formatted(dateStyle.month(.abbreviated)))
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            TodayDisclosureIcon()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        event.isAssessment ? GradeBand.average.foregroundColor : Brand.primary
    }

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: AppLanguageOverride.locale, timeZone: event.hasTime ? .current : event.calendar.timeZone)
    }

    private var detail: String {
        var parts: [String] = []
        if let kind = PlannerItemType(rawValue: event.kind.rawValue) {
            parts.append(kind.title)
        }
        if let subject = event.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            parts.append(subject)
        }
        if event.hasTime {
            parts.append(event.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguageOverride.locale)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct TodayDisclosureIcon: View {
    var body: some View {
        GradelyIcon("arrow-right-01", size: 13)
            .foregroundStyle(Color.secondary.opacity(0.6))
            .accessibilityHidden(true)
    }
}

private struct TodayLinkLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
            GradelyIcon("arrow-right-01", size: 11)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Brand.primary)
        .padding(.horizontal, Spacing.sm + 2)
        .frame(minHeight: 28)
        .background(Brand.primary.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct TodayActionCardLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let expandsVertically: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(icon, size: 16)
                .foregroundStyle(Brand.onAccent)
                .frame(width: 34, height: 34)
                .background(Brand.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .topLeading)
        .frame(minHeight: 44)
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.primary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

private struct TodayInfoRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: Text
    let subtitle: Text
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            GradelyIcon(icon, size: 16)
                .dynamicTypeSize(.medium)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .font(.subheadline.weight(.bold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
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
            return String(
                format: AppL10n.string("absence.risk.missed"),
                subject.missedLessons,
                subject.totalLessons
            )
        }
        if misses == 0 {
            return AppL10n.string("absence.risk.overLimit")
        }
        return String(format: AppL10n.string("absence.risk.untilLimit"), misses)
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
            return String(format: AppL10n.string("marks.trends.newMarks"), marks)
        }
        return AppL10n.string("marks.trends.movement")
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
        case thirty
        case ninety
        case schoolYear

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .thirty: "marks.trends.range30"
            case .ninety: "marks.trends.range90"
            case .schoolYear: "marks.trends.schoolYear"
            }
        }
    }

    let trends: [SubjectGradeTrend]
    @State private var selectedRange: Range = .ninety

    var body: some View {
        List {
            Picker("marks.trends.range", selection: $selectedRange) {
                ForEach(Range.allCases) { range in
                    Text(range.title).tag(range)
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
                    Text("today.trends.cloudSubtitle")
                }
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTrends) { trend in
                    TrendRow(trend: trend)
                }
            }
        }
        .navigationTitle("marks.trends.title")
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
