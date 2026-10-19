import SwiftUI

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @State private var reconnectAccount: LinkedAccount?
    @Environment(\.scenePhase) private var scenePhase
    private let accountHub: AnyView?
    private let repository: SchoolRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let onOpenGradeyAI: () -> Void
    private let onOpenTimetable: (() -> Void)?
    private let onOpenMarks: (() -> Void)?
    private let snapshotStore: SchoolSnapshotStore?
    private let vavruska: VavruskaViewModel?
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
        vavruska: VavruskaViewModel? = nil,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {},
        onOpenTimetable: (() -> Void)? = nil,
        onOpenMarks: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        self.onOpenTimetable = onOpenTimetable
        self.onOpenMarks = onOpenMarks
        self.snapshotStore = snapshotStore
        self.vavruska = vavruska
        _viewModel = State(initialValue: TodayViewModel(
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: historyRepository,
            accountSettingsClient: accountSettingsClient,
            gradeyAuthClient: gradeyAuthClient,
            snapshotStore: snapshotStore,
            vavruska: vavruska
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
                #if !os(macOS)
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    AccountSettingsButton(accountHub: accountHub)
                }
                #endif
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .gradelyOnRefreshCommand { await viewModel.refresh(forceRefresh: true) }
            .onChange(of: snapshotStore?.revision) { _, _ in viewModel.applySharedSnapshot() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshTime()
                    Task { await viewModel.refresh(forceRefresh: false) }
                }
            }
            .navigationDestination(for: TodayDestination.self) { destination in
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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let account = viewModel.accountRequiringReconnect {
                    schoolConnectionNotice(account)
                }
                TodayHero(snapshot: viewModel.snapshot, now: now)
                if viewModel.isLoading {
                    loadingRow
                }
                dayCard(at: now)
                if let vavruska, let rows = danceRows(vavruska, at: now), rows.isDanceDay {
                    danceCard(rows, at: now)
                }
                recentMarksCard
                plannerCard(at: now)
                if showMealsTab, viewModel.snapshot.stravaSession != nil {
                    lunchCard
                }
                if let vavruska, let rows = danceRows(vavruska, at: now), !rows.isDanceDay {
                    danceCard(rows, at: now)
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
                .font(.gradely(.caption))
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
                        .font(.gradely(.title3).weight(.semibold))
                        .foregroundStyle(Color.gradelySystemOrange)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("School connection needs attention")
                            .font(.gradely(.headline))
                        Text(account.displayName)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Text(account.actionRequiredReason ?? AppL10n.string("today.reconnect.fallback"))
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    reconnectAccount = account
                } label: {
                    GradelyLabel("settings.connected.reconnect", systemImage: "arrow.clockwise")
                        .font(.gradely(.headline))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ControlMetrics.minHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gradelySystemOrange)
                .accessibilityIdentifier("todaySchoolReconnectButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todaySchoolConnectionNotice")
    }

    // MARK: - Now and next

    private func dayCard(at now: Date) -> some View {
        let snapshot = viewModel.snapshot
        return TodaySection(
            "Now and next",
            link: onOpenTimetable.map { .action(id: "todayOpenTimetableButton", perform: $0) },
            footer: isTimetableStale(at: now) ? "today.cached.warning" : nil
        ) {
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
                        TodayInfoRow(title: Text("timetable.summary.empty.title"), icon: "sun-01", tint: Brand.primary)
                    } else {
                        TodayInfoRow(title: Text("today.noMoreLessons"), icon: "checkmark-circle-02", tint: Brand.primary)
                    }
                }

                if summary.hasChanges {
                    HStack(spacing: Spacing.sm) {
                        GradelyIcon("alert-02", size: 14)
                        Text(verbatim: changeSummary(summary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.gradely(.caption).weight(.bold))
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
                TodayInfoRow(title: Text("today.timetableUnavailable"), icon: "calendar-03", tint: .secondary)
            }
        }
        .accessibilityIdentifier("todayTimetableCard")
    }

    private func isTimetableStale(at now: Date) -> Bool {
        guard let snapshotStore, snapshotStore.cachedWeek(containing: now) != nil else { return false }
        let source = "timetable-\(TimetableDates.apiDateString(TimetableDates.monday(of: now)))"
        return snapshotStore.sourceState(source).isStale(at: now, interval: 900)
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

    // MARK: - Recent marks

    private var recentMarksCard: some View {
        let marks = viewModel.snapshot.recentMarks(limit: 3)
        return TodaySection(
            "today.recentGrades.title",
            link: onOpenMarks.map { .action(id: "todayOpenMarksButton", perform: $0) },
            footer: snapshotStore?.sourceState("marks").error != nil ? "today.cached.warning" : nil
        ) {
            if marks.isEmpty {
                TodayInfoRow(title: Text("today.recentGrades.none"), icon: "checkmark-badge-02", tint: .secondary)
            } else {
                ForEach(marks) { mark in
                    NavigationLink(value: TodayDestination.subject(mark.subjectID)) {
                        TodayMarkRow(mark: mark)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todayRecentMark-\(mark.id)")
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
            TodaySection("planner.title", link: .destination(id: "todayOpenPlannerButton", .planner)) {
                if events.isEmpty {
                    TodayInfoRow(title: Text("today.planner.none"), icon: "check-list", tint: .secondary)
                } else {
                    ForEach(Array(events)) { event in
                        NavigationLink(value: TodayDestination.plannerItem(event.id)) {
                            TodayPlannerRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayPlannerEvent-\(event.id.uuidString)")
                    }
                }
            }
            .accessibilityIdentifier("todayPlannerCard")
        }
    }

    // MARK: - Lunch

    private var lunchCard: some View {
        TodaySection("Lunch") {
            if let meal = viewModel.snapshot.orderedMeal {
                TodayInfoRow(
                    title: Text(verbatim: meal.name),
                    subtitle: Text(verbatim: meal.formattedPrice),
                    icon: "restaurant-02",
                    tint: Brand.primary
                )
            } else {
                TodayInfoRow(title: Text("today.noMeal"), icon: "restaurant-02", tint: .secondary)
            }
        }
        .accessibilityIdentifier("todayLunchCard")
    }

    // MARK: - Dance

    private struct DanceRows {
        var needsReconnect = false
        var nextEvent: VavruskaEvent?
        var sale: VavruskaTicketSale?
        var hasUnreadNotices = false
        var isDanceDay = false
    }

    /// Nil hides the section: integration off, no course, or nothing worth a row.
    private func danceRows(_ vavruska: VavruskaViewModel, at now: Date) -> DanceRows? {
        guard vavruska.isActive else { return nil }
        var rows = DanceRows()
        rows.needsReconnect = vavruska.phase == .needsReconnect
        rows.nextEvent = vavruska.upcomingEvents(after: now)
            .first { $0.start < now.addingTimeInterval(14 * 24 * 60 * 60) }
        rows.sale = vavruska.relevantTicketSales(now: now).first
        rows.hasUnreadNotices = vavruska.hasUnreadNotices
        rows.isDanceDay = rows.nextEvent.map { Calendar.current.isDate($0.start, inSameDayAs: now) } ?? false
        guard rows.needsReconnect || rows.nextEvent != nil || rows.sale != nil || rows.hasUnreadNotices else { return nil }
        return rows
    }

    private func danceCard(_ rows: DanceRows, at now: Date) -> some View {
        TodaySection(
            "vavruska.today.title",
            link: .destination(id: "todayOpenVavruskaButton", .vavruska),
            footer: vavruska?.lastRefreshFailed == true ? "today.cached.warning" : nil
        ) {
            if rows.needsReconnect {
                NavigationLink(value: TodayDestination.vavruskaReconnect) {
                    HStack(spacing: Spacing.sm) {
                        TodayInfoRow(title: Text("vavruska.today.reconnect"), icon: "alert-01", tint: .gradelySystemOrange)
                        TodayDisclosureIcon()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayDanceReconnect")
            }
            if let event = rows.nextEvent {
                TodayInfoRow(
                    title: Text(verbatim: event.title),
                    subtitle: Text(verbatim: danceSubtitle(event, now: now)),
                    icon: event.kind.iconName,
                    tint: event.kind.tint
                )
                .accessibilityIdentifier("todayDanceNextEvent")
            }
            if let sale = rows.sale {
                TodayInfoRow(
                    title: Text(verbatim: sale.eventTitle),
                    subtitle: Text(verbatim: VavruskaFormatting.saleLine(sale, now: now)),
                    icon: "ticket-01",
                    tint: .gradelySystemPurple
                )
                .accessibilityIdentifier("todayDanceTicketSale")
            }
            if rows.hasUnreadNotices {
                TodayInfoRow(title: Text("vavruska.today.notices"), icon: "news", tint: Brand.primary)
                    .accessibilityIdentifier("todayDanceNotices")
            }
        }
        .accessibilityIdentifier("todayDanceCard")
    }

    /// "Dnes · 16:30–18:10 · Obecní dům", "Zítra · …" or "ne 25. 10. · …".
    private func danceSubtitle(_ event: VavruskaEvent, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(event.start, inSameDayAs: now) {
            day = AppL10n.string("timetable.today")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.start, inSameDayAs: tomorrow) {
            day = AppL10n.string("planner.tomorrow")
        } else {
            day = SchoolDateFormatting.weekdayShortDate(event.start)
        }
        return ([day, VavruskaFormatting.timeRange(event)] + [event.venue].compactMap { $0 }).joined(separator: " · ")
    }

    // MARK: - Navigation

    @ViewBuilder private func insightDestination(_ destination: TodayDestination) -> some View {
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
        case .vavruska:
            if let vavruska {
                VavruskaView(viewModel: vavruska)
            } else { ContentUnavailableView("today.destination.unavailable", systemImage: "music.note") }
        case .vavruskaReconnect:
            if let vavruska {
                VavruskaConnectView(viewModel: vavruska, dismissesOnConnect: true)
            } else { ContentUnavailableView("today.destination.unavailable", systemImage: "music.note") }
        }
    }

    private var plannerSubjects: [PlannerSubjectReference] {
        guard let scope = snapshotStore?.scope else { return [] }
        return viewModel.snapshot.subjects.map {
            PlannerSubjectReference(scope: scope, id: $0.id, name: $0.trimmedName, abbreviation: $0.trimmedAbbrev)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
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
        .gradelyMacSheetSize(minWidth: 560, idealWidth: 640, minHeight: 600, idealHeight: 700)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: greeting)
                .font(.gradelyDisplay(size: 30, relativeTo: .title))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            statTiles
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayHeroCard")
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
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 30)
            .accessibilityHidden(true)
    }

    private var averageTile: some View {
        StatTile(
            title: AppL10n.string("today.hero.average"),
            value: GradeMath.formattedAverage(snapshot.overallAverage)
        )
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
                .font(.gradely(.caption2).weight(.bold).monospacedDigit())
                .opacity(0.8)
            Text(verbatim: TodayLessonCopy.shortSubject(for: lesson))
                .font(.gradely(.subheadline).weight(.bold))
                .strikethrough(state == .cancelled)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 54, minHeight: ControlMetrics.minHeight)
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
                .font(.gradely(.headline).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(roleTitle)
                        .font(.gradely(.caption2).weight(.bold))
                        .textCase(.uppercase)
                        .kerning(0.4)
                        .foregroundStyle(tint)
                    if let minutesText {
                        Text(verbatim: minutesText)
                            .font(.gradely(.caption2).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: TodayLessonCopy.subject(for: lesson))
                    .font(.gradely(.subheadline).weight(.bold))
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
        .font(.gradely(.caption))
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

private struct TodayMarkRow: View {
    let mark: TodayNewMark

    var body: some View {
        HStack(spacing: Spacing.md) {
            GradeBadge(text: mark.markText, band: mark.band, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs + 2) {
                    Text(verbatim: mark.subjectTitle)
                        .font(.gradely(.subheadline).weight(.bold))
                        .lineLimit(1)
                    if mark.isNew {
                        Circle()
                            .fill(Brand.primary)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: mark.caption ?? mark.subjectName)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(verbatim: dateText)
                .font(.gradely(.caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TodayDisclosureIcon()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        mark.detectedAt.map { SchoolDateFormatting.shortDate($0) } ?? "–"
    }
}

private struct TodayPlannerRow: View {
    let event: SchoolEvent

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(spacing: 0) {
                Text(verbatim: event.date.formatted(dateStyle.day()))
                    .font(.gradely(.title3).weight(.bold).monospacedDigit())
                Text(verbatim: event.date.formatted(dateStyle.month(.abbreviated)))
                    .font(.gradely(.caption2).weight(.bold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title)
                    .font(.gradely(.subheadline).weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: detail)
                    .font(.gradely(.caption))
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

private enum TodaySectionLink {
    case action(id: String, perform: () -> Void)
    case destination(id: String, TodayDestination)
}

/// A Today section: a `PlainSection` whose title links to the full screen.
private struct TodaySection<Content: View>: View {
    let title: LocalizedStringKey
    let link: TodaySectionLink?
    let footer: LocalizedStringKey?
    let content: Content

    init(
        _ title: LocalizedStringKey,
        link: TodaySectionLink? = nil,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.link = link
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        PlainSection(footer: footer) {
            switch link {
            case .action(let id, let perform):
                Button(action: perform) { PlainSectionTitle(title, showsChevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(id)
            case .destination(let id, let destination):
                NavigationLink(value: destination) { PlainSectionTitle(title, showsChevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(id)
            case nil:
                PlainSectionTitle(title)
            }
        } content: {
            content
        }
    }
}

private struct TodayInfoRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: Text
    var subtitle: Text?
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
                    .font(.gradely(.subheadline).weight(.bold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    subtitle
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
