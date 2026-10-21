import SwiftUI

struct TimetableView: View {
    @State private var viewModel: TimetableViewModel
    @State private var selectedLesson: PlannerLessonSelection?
    @State private var plannerStore: PlannerStore
    private let plannerResolver: PlannerLessonResolver
    private let siriTarget: GradeySiriDestination?
    @Environment(\.gradeySiriService) private var siriService
    private let accountHub: AnyView?
    private let onOpenGradeyAI: () -> Void
    private let vavruska: VavruskaViewModel?
    private let friends: FriendsViewModel?
    @State private var isDancePresented = false
    @State private var selectedFriendID: UUID?
    @State private var friendViewModels: [UUID: TimetableViewModel] = [:]
    @State private var isAddFriendPresented = false

    init(
        repository: SchoolRepository,
        plannerStore: PlannerStore? = nil,
        vavruska: VavruskaViewModel? = nil,
        friends: FriendsViewModel? = nil,
        accountHub: AnyView? = nil,
        onOpenGradeyAI: @escaping () -> Void = {},
        siriTarget: GradeySiriDestination? = nil
    ) {
        _viewModel = State(initialValue: TimetableViewModel(repository: repository))
        _plannerStore = State(initialValue: plannerStore ?? PlannerStore(
            persistence: InMemoryPlannerPersistence(), calendarService: UnavailablePlannerCalendarService()
        ))
        plannerResolver = PlannerLessonResolver(repository: repository)
        self.siriTarget = siriTarget
        self.accountHub = accountHub
        self.onOpenGradeyAI = onOpenGradeyAI
        self.vavruska = vavruska
        self.friends = friends
    }

    /// The friend on screen, or nil for your own timetable.
    private var selectedFriend: Friend? {
        friends?.friend(id: selectedFriendID)
    }

    private var activeViewModel: TimetableViewModel {
        selectedFriend.flatMap { friendViewModels[$0.id] } ?? viewModel
    }

    private func select(friendID: UUID?) {
        if let friendID, friendViewModels[friendID] == nil, let friends, let friend = friends.friend(id: friendID) {
            friendViewModels[friendID] = TimetableViewModel(source: friends.timetableSource(for: friend))
        }
        selectedFriendID = friendID
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gradelyScreenBackground()
                .navigationTitle(selectedFriend?.name ?? AppL10n.string("rozvrh.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                #if os(iOS)
                .toolbarTitleMenu {
                    if friends != nil { personMenuContent }
                    if activeViewModel.supportsPermanentTimetable { timetableKindPicker }
                }
                #endif
                .toolbar {
                    ToolbarItem(placement: .gradelyTopBarLeading) {
                        GradeyAIToolbarButton(onOpen: onOpenGradeyAI)
                    }

                    #if os(macOS)
                    if activeViewModel.supportsPermanentTimetable {
                        ToolbarItem(placement: .gradelyTopBarTrailing) {
                            timetableKindMenu
                        }
                    }
                    #endif

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        Button {
                            Task { await activeViewModel.refresh() }
                        } label: {
                            GradelyIcon(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeating, isActive: activeViewModel.isRefreshing)
                        }
                        .disabled(activeViewModel.isLoading || activeViewModel.isRefreshing)
                        .accessibilityLabel(AppL10n.string("action.refresh"))
                        .accessibilityIdentifier("timetableRefreshButton")
                    }

                    #if os(macOS)
                    if friends != nil {
                        ToolbarItem(placement: .gradelyTopBarTrailing) {
                            Menu {
                                personMenuContent
                            } label: {
                                GradelyIcon("user-group")
                                    .gradelyToolbarIconButton()
                            }
                            .accessibilityLabel(AppL10n.string("friends.menu.label"))
                            .accessibilityIdentifier("timetablePersonMenu")
                        }
                    }
                    #endif

                    // The Planner is yours; it isn't offered on a friend's timetable.
                    if selectedFriend == nil {
                        ToolbarItem(placement: .gradelyTopBarTrailing) {
                            NavigationLink {
                                PlannerView(store: plannerStore, resolver: plannerResolver, displayedWeek: viewModel.week, subjects: plannerSubjects)
                            } label: {
                                GradelyIcon(systemName: "checklist")
                            }
                            .accessibilityLabel(AppL10n.string("planner.title"))
                            .accessibilityIdentifier("timetablePlannerButton")
                        }
                    }

                    #if !os(macOS)
                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        AccountSettingsButton(accountHub: accountHub)
                    }
                    #endif
                }
                .task {
                    plannerStore.loadIfNeeded()
                    await viewModel.loadIfNeeded()
                }
                .task(id: selectedFriendID) {
                    await activeViewModel.loadIfNeeded()
                }
                .onChange(of: friends?.friends) {
                    // A friend removed in Settings: back to your own timetable.
                    if selectedFriendID != nil, selectedFriend == nil { selectedFriendID = nil }
                    friendViewModels = friendViewModels.filter { id, _ in friends?.friend(id: id) != nil }
                }
                .gradelyOnRefreshCommand { await activeViewModel.refresh() }
                .task(id: siriTarget?.requestID) {
                    guard let target = siriTarget, let day = target.day, let date = day.date, let lesson = target.lesson,
                          target.scope == viewModel.schoolScope else { return }
                    selectedFriendID = nil
                    await viewModel.showSiriDay(date)
                    guard target.scope == viewModel.schoolScope, let siriService else { return }
                    do { try siriService.validateDestination(target) } catch { return }
                    selectedLesson = PlannerLessonSelection(lesson: lesson, day: day)
                }
                .navigationDestination(isPresented: $isDancePresented) {
                    if let vavruska {
                        VavruskaView(viewModel: vavruska)
                    }
                }
                .sheet(isPresented: $isAddFriendPresented) {
                    if let friends {
                        AddFriendView(friends: friends) { friend in
                            select(friendID: friend.id)
                        }
                    }
                }
                .sheet(item: $selectedLesson) { selection in
                    LessonDetailSheet(
                        lesson: selection.lesson, day: selection.day, scope: activeViewModel.schoolScope,
                        plannerStore: plannerStore, resolver: plannerResolver,
                        displayedWeek: activeViewModel.week, subjects: plannerSubjects
                    )
                }
        }
    }

    /// You, then each friend, then Add friend.
    @ViewBuilder
    private var personMenuContent: some View {
        if let friends {
            Picker(AppL10n.string("friends.menu.label"), selection: Binding(
                get: { selectedFriendID },
                set: { select(friendID: $0) }
            )) {
                Text("friends.menu.me").tag(UUID?.none)
                ForEach(friends.friends) { friend in
                    Text(verbatim: friend.name).tag(UUID?.some(friend.id))
                }
            }
            .pickerStyle(.inline)

            Button {
                isAddFriendPresented = true
            } label: {
                GradelyLabel("friends.menu.add", systemImage: "plus")
            }
            .accessibilityIdentifier("timetableAddFriendButton")
        }
    }

    private var timetableKindPicker: some View {
        Picker(AppL10n.string("timetable.kind"), selection: Binding(
            get: { activeViewModel.kind },
            set: { kind in
                if activeViewModel.setKind(kind) {
                    Task { await activeViewModel.refresh() }
                }
            }
        )) {
            Text("timetable.kind.weekly").tag(TimetableKind.weekly)
            Text("timetable.kind.permanent").tag(TimetableKind.permanent)
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("timetableKindPicker")
    }

    /// On the Mac the weekly/permanent switch lives in the trailing toolbar so the
    /// timetable itself stays a single uninterrupted column. On iPhone it sits in
    /// the title menu next to whose timetable it is, because a fourth toolbar
    /// button next to the title menu pushes Planner and Settings into an overflow.
    private var timetableKindMenu: some View {
        Menu {
            timetableKindPicker
        } label: {
            GradelyIcon(systemName: activeViewModel.kind == .permanent ? "calendar.badge.clock" : "calendar")
                .gradelyToolbarIconButton()
        }
        .accessibilityLabel(AppL10n.string("timetable.kind"))
        .accessibilityIdentifier("timetableKindButton")
    }

    @ViewBuilder
    private var content: some View {
        if activeViewModel.isLoading && activeViewModel.week == nil {
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text("timetable.loading")
            }
            .accessibilityIdentifier("timetableLoadingView")
        } else if let errorMessage = activeViewModel.errorMessage, activeViewModel.week == nil {
            ContentUnavailableView {
                GradelyLabel(AppL10n.string("error.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(AppL10n.string("action.retry")) {
                    Task { await activeViewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("timetableErrorView")
        } else {
            timetable
        }
    }

    private var timetable: some View {
        VStack(spacing: 0) {
            if activeViewModel.kind == .weekly {
                WeekNavBar(viewModel: activeViewModel)
            } else {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    GradelyIcon(systemName: "calendar.badge.clock", size: 15)
                        .foregroundStyle(Brand.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("timetable.kind.permanent")
                            .font(.gradely(.subheadline).weight(.semibold))
                        Text("timetable.permanent.description")
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
            #if os(macOS)
            Divider()
            WeekGrid(
                viewModel: activeViewModel,
                plannerItems: attachedItems,
                afterSchool: afterSchool,
                onSelectDance: { isDancePresented = true }
            ) { lesson, day in
                selectedLesson = PlannerLessonSelection(lesson: lesson, day: day)
            }
            #else
            DayStrip(viewModel: activeViewModel)
            Divider()
            dayContent
            #endif
        }
    }

    private var dayContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if activeViewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("timetable.refreshing")
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, Spacing.xs)
                }

                let dance = activeViewModel.selectedDay.map(afterSchool) ?? []
                if let day = activeViewModel.selectedDay, day.hasLessons {
                    ForEach(day.lessons) { lesson in
                        if lesson.id != day.lessons.first?.id {
                            Divider()
                        }
                        LessonRow(lesson: lesson, isToday: day.isToday, plannerItems: attachedItems(lesson, day: day)) {
                            selectedLesson = PlannerLessonSelection(lesson: lesson, day: day)
                        }
                        .accessibilityIdentifier("lessonRow-\(lesson.id)")
                        .gradeySiriContext(.lesson(lesson, day, activeViewModel.schoolScope))
                    }
                } else if dance.isEmpty {
                    EmptyDayView(day: activeViewModel.selectedDay)
                        .padding(.top, Spacing.xxl)
                }

                if let vavruska, !dance.isEmpty {
                    VavruskaAfterSchoolBlock(events: dance, viewModel: vavruska)
                        .padding(.top, activeViewModel.selectedDay?.hasLessons == true ? Spacing.lg : 0)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await activeViewModel.refresh()
            await vavruska?.refreshIfNeeded(force: true)
        }
        .accessibilityIdentifier("timetableList")
    }

    /// Dance lessons on a school day of the weekly timetable (weekends never show here).
    private func afterSchool(_ day: ScheduledDay) -> [VavruskaEvent] {
        guard let vavruska, selectedFriend == nil, activeViewModel.kind == .weekly, let date = day.date else { return [] }
        return vavruska.events(on: date)
    }

    private func attachedItems(_ lesson: ScheduledLesson, day: ScheduledDay) -> [PlannerItem] {
        guard let scope = activeViewModel.schoolScope else { return [] }
        return plannerStore.attachedItems(to: lesson, on: day, scope: scope)
    }

    private var plannerSubjects: [PlannerSubjectReference] {
        guard let scope = viewModel.schoolScope else { return [] }
        var seen = Set<String>()
        return viewModel.days.flatMap(\.lessons).compactMap { lesson in
            guard let id = lesson.subjectID, seen.insert(id).inserted else { return nil }
            return PlannerSubjectReference(scope: scope, id: id, name: lesson.subjectName ?? lesson.title, abbreviation: lesson.subjectAbbrev)
        }
    }
}

private struct PlannerLessonSelection: Identifiable {
    let lesson: ScheduledLesson
    let day: ScheduledDay
    var id: String { lesson.id }
}

// MARK: - Today summary

// MARK: - Week navigation

private struct WeekNavBar: View {
    let viewModel: TimetableViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            navButton(systemImage: "chevron.left", id: "weekPrev", label: "timetable.previousWeek") {
                await viewModel.goToPreviousWeek()
            }

            VStack(spacing: 2) {
                Text(viewModel.weekTitle)
                    .font(.gradely(.headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !viewModel.isViewingCurrentWeek {
                    Button {
                        Task { await viewModel.goToToday() }
                    } label: {
                        Text("timetable.today")
                            .font(.gradely(.caption).weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .accessibilityIdentifier("weekToday")
                }
            }
            .frame(maxWidth: .infinity)

            navButton(systemImage: "chevron.right", id: "weekNext", label: "timetable.nextWeek") {
                await viewModel.goToNextWeek()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    private func navButton(
        systemImage: String,
        id: String,
        label: String.LocalizationValue,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            GradelyIcon(systemName: systemImage, size: 14)
                .foregroundStyle(Brand.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        #if os(macOS)
        .keyboardShortcut(systemImage == "chevron.left" ? .leftArrow : .rightArrow, modifiers: .command)
        #endif
        .accessibilityLabel(AppL10n.string(label))
        .accessibilityIdentifier(id)
    }
}

#if os(macOS)
// MARK: - Week grid

/// The whole week at once on the Mac: a column per day, a row per lesson
/// period. Clicking a lesson opens the same detail sheet as on iOS.
private struct WeekGrid: View {
    let viewModel: TimetableViewModel
    let plannerItems: (ScheduledLesson, ScheduledDay) -> [PlannerItem]
    let afterSchool: (ScheduledDay) -> [VavruskaEvent]
    let onSelectDance: () -> Void
    let onSelect: (ScheduledLesson, ScheduledDay) -> Void

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.md, verticalSpacing: 0) {
                GridRow {
                    Color.clear
                        .frame(width: 52, height: 1)
                    ForEach(viewModel.days) { day in
                        WeekGridDayHeader(day: day)
                    }
                }
                .padding(.bottom, Spacing.sm)

                ForEach(hours) { hour in
                    Divider()
                    GridRow {
                        WeekGridHour(hour: hour, isNow: viewModel.days.contains { day in
                            day.lessons.contains { $0.hour.id == hour.id && !$0.isCanceled }
                                && LessonClock.isCurrent(hour, isToday: day.isToday)
                        })
                        ForEach(viewModel.days) { day in
                            cell(day: day, hour: hour)
                        }
                    }
                }

                if viewModel.days.contains(where: { !afterSchool($0).isEmpty }) {
                    Divider()
                    GridRow {
                        VavruskaWeekGridLabel()
                        ForEach(viewModel.days) { day in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(afterSchool(day)) { event in
                                    VavruskaWeekGridEvent(event: event, onSelect: onSelectDance)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.vertical, Spacing.sm)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .accessibilityIdentifier("timetableList")
    }

    /// Periods that have a lesson on any day, in the school's order.
    private var hours: [TimetableHour] {
        let lessonHours = viewModel.days.flatMap { $0.lessons.map(\.hour) }
        let used = Set(lessonHours.map(\.id))
        var ordered = (viewModel.week?.hours ?? []).filter { used.contains($0.id) }
        let known = Set(ordered.map(\.id))
        for hour in lessonHours where !known.contains(hour.id) && !ordered.contains(where: { $0.id == hour.id }) {
            ordered.append(hour)
        }
        return ordered
    }

    private func cell(day: ScheduledDay, hour: TimetableHour) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(day.lessons.filter { $0.hour.id == hour.id }) { lesson in
                WeekGridLesson(
                    lesson: lesson,
                    isNow: !lesson.isCanceled && LessonClock.isCurrent(hour, isToday: day.isToday),
                    plannerItems: plannerItems(lesson, day)
                ) {
                    onSelect(lesson, day)
                }
                .accessibilityIdentifier("lessonRow-\(lesson.id)")
                .gradeySiriContext(.lesson(lesson, day, viewModel.schoolScope))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, Spacing.sm)
    }
}

private struct WeekGridDayHeader: View {
    let day: ScheduledDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                dayLabel
            }
            if !day.hasLessons {
                Text(EmptyDayView.title(for: day))
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dayChip-\(day.dayOfWeek)")
    }

    @ViewBuilder
    private var dayLabel: some View {
        if let date = day.date {
            Text(TimetableDates.weekdayAbbreviation(date))
                .font(.gradely(.caption).weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(day.isToday ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.secondary))
            Text(TimetableDates.dayNumber(date))
                .font(.gradely(.title3).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.primary))
        } else {
            Text(TimetableDates.weekdayAbbreviation(dayOfWeek: day.dayOfWeek))
                .font(.gradely(.subheadline).weight(.bold))
                .textCase(.uppercase)
        }
    }
}

private struct WeekGridHour: View {
    let hour: TimetableHour
    let isNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(hour.caption)
                .font(.gradely(.headline).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isNow ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.primary))
            if !hour.beginTime.isEmpty {
                Text(hour.beginTime)
                    .font(.gradely(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(isNow ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.secondary))
                Text(hour.endTime)
                    .font(.gradely(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 52, alignment: .leading)
        .padding(.vertical, Spacing.sm)
    }
}

private struct WeekGridLesson: View {
    let lesson: ScheduledLesson
    let isNow: Bool
    let plannerItems: [PlannerItem]
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Capsule()
                    .fill(accent.opacity(lesson.isCanceled ? 0.45 : 1))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LessonText.subject(for: lesson))
                        .font(.gradely(.subheadline).weight(.semibold))
                        .foregroundStyle(lesson.isCanceled ? AnyShapeStyle(.secondary) : isNow ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.primary))
                        .strikethrough(lesson.isCanceled, color: LessonChangeKind.canceled.color.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Text(detail)
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let label = lesson.changeKind.localizedLabel {
                        Text(label)
                            .font(.gradely(.caption).weight(.semibold))
                            .foregroundStyle(lesson.changeKind.color)
                            .lineLimit(1)
                    }

                    if let first = plannerItems.first {
                        GradelyLabel(first.type.title, systemImage: first.type.systemImage, iconSize: 11)
                            .font(.gradely(.caption).weight(.semibold))
                            .foregroundStyle(Brand.primary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Brand.primary.opacity(isHovering ? 0.08 : 0))
                    .padding(-Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(LessonText.subject(for: lesson))
    }

    /// "12 · Novák": room, then the teacher's abbreviation or name.
    private var detail: String {
        guard !lesson.isCanceled else { return "" }
        return [lesson.roomAbbrev, lesson.teacherAbbrev ?? lesson.teacherName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var accent: Color {
        lesson.changeKind == .none ? Brand.primary : lesson.changeKind.color
    }
}
#endif

private struct DayStrip: View {
    let viewModel: TimetableViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.days) { day in
                DayChip(day: day, isSelected: day.id == viewModel.selectedDay?.id) {
                    viewModel.select(dayID: day.id)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }
}

/// One day of the week row: plain weekday and date, the selected date in a
/// solid circle, today in the brand colour, and a dot when lessons changed.
private struct DayChip: View {
    let day: ScheduledDay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if day.date != nil {
                    Text(weekdaySymbol)
                        .font(.gradely(.caption2).weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(day.isToday ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.secondary))
                    Text(dayNumber)
                        .font(.gradely(.headline).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(numberStyle)
                        .frame(width: 38, height: 38)
                        .background {
                            if isSelected { Circle().fill(Brand.primary) }
                        }
                    Circle()
                        .frame(width: 5, height: 5)
                        .foregroundStyle(LessonChangeKind.canceled.color)
                        .opacity(day.hasChanges ? 1 : 0)
                } else {
                    // Permanent timetable: weekdays only, no dates.
                    Text(weekdaySymbol)
                        .font(.gradely(.subheadline).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(numberStyle)
                        .padding(.horizontal, Spacing.sm + 2)
                        .frame(height: 34)
                        .background {
                            if isSelected { Capsule().fill(Brand.primary) }
                        }
                }
            }
            .frame(maxWidth: .infinity, minHeight: ControlMetrics.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("dayChip-\(day.dayOfWeek)")
    }

    private var numberStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Brand.onAccent) }
        return day.isToday ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.primary)
    }

    private var weekdaySymbol: String {
        if let date = day.date {
            return TimetableDates.weekdayAbbreviation(date)
        }
        return TimetableDates.weekdayAbbreviation(dayOfWeek: day.dayOfWeek)
    }

    private var dayNumber: String {
        guard let date = day.date else { return "" }
        return TimetableDates.dayNumber(date)
    }
}

// MARK: - Lesson row

private struct LessonRow: View {
    let lesson: ScheduledLesson
    let isToday: Bool
    let plannerItems: [PlannerItem]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                hourRail
                LessonCard(lesson: lesson, plannerItems: plannerItems)
            }
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A cancelled hour is not "happening now", so it never takes the live highlight.
    private var isCurrent: Bool {
        !lesson.isCanceled && LessonClock.isCurrent(lesson.hour, isToday: isToday)
    }

    private var hourRail: some View {
        VStack(spacing: 2) {
            Text(lesson.hour.caption)
                .font(.gradely(.headline).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? AnyShapeStyle(Brand.primary) : lesson.isCanceled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if !lesson.hour.beginTime.isEmpty {
                Text(lesson.hour.beginTime)
                    .font(.gradely(.caption2))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Brand.primary) : lesson.isCanceled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                Text(lesson.hour.endTime)
                    .font(.gradely(.caption2))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(width: 44)
    }
}

private struct LessonCard: View {
    let lesson: ScheduledLesson
    let plannerItems: [PlannerItem]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            LessonTile(lesson: lesson)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(LessonText.subject(for: lesson))
                        .font(.gradely(.headline))
                        .lineLimit(1)
                        .strikethrough(lesson.isCanceled, color: LessonChangeKind.canceled.color.opacity(0.8))
                        .foregroundStyle(lesson.isCanceled ? .secondary : .primary)

                    Spacer(minLength: Spacing.xs)

                    if let label = lesson.changeKind.localizedLabel {
                        StatusChip(text: label, color: lesson.changeKind.color)
                            .fixedSize()
                    }
                }

                // A cancelled hour has no room or teacher worth reading; the
                // school's note on why it was cancelled matters more.
                if !lesson.isCanceled, lesson.roomAbbrev != nil || teacher != nil {
                    HStack(spacing: Spacing.md) {
                        if let room = lesson.roomAbbrev {
                            inlineLabel(room, systemImage: "door.left.hand.open")
                        }
                        if let teacher {
                            inlineLabel(teacher, systemImage: "person.fill")
                        }
                    }
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                }

                if let note = LessonText.distinctChangeNote(for: lesson) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs + 2) {
                        GradelyIcon(systemName: "info.circle", size: 12)
                            .foregroundStyle(lesson.changeKind.color)
                        Text(note)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.gradely(.caption))
                }

                if !lesson.isCanceled, !lesson.cycles.isEmpty {
                    Text(lesson.cycles.joined(separator: ", "))
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !lesson.isCanceled, let theme = lesson.theme {
                    Text(theme)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let first = plannerItems.first {
                    GradelyLabel(
                        plannerItems.count == 1 ? first.type.title : String(format: AppL10n.string("planner.indicator.multiple"), first.type.title, plannerItems.count - 1),
                        systemImage: first.type.systemImage, iconSize: 12
                    )
                    .font(.gradely(.caption).weight(.semibold))
                    .foregroundStyle(Brand.primary)
                    .lineLimit(1)
                }
            }
        }
    }

    private var teacher: String? {
        lesson.teacherName ?? lesson.teacherAbbrev
    }

    private func inlineLabel(_ text: String, systemImage: String) -> some View {
        GradelyLabel(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .lineLimit(1)
    }
}

/// Subject abbreviation tile; tinted by the change, and struck through with a
/// calendar-remove fallback when a cancelled hour carries no subject at all.
private struct LessonTile: View {
    let lesson: ScheduledLesson

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(accent.opacity(lesson.isCanceled ? 0.10 : 0.14))
            .frame(width: 40, height: 40)
            .overlay {
                if let abbreviation = LessonText.abbreviation(for: lesson) {
                    Text(abbreviation)
                        .font(.gradely(.subheadline).weight(.bold))
                        .strikethrough(lesson.isCanceled, color: accent)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                } else {
                    GradelyIcon(systemName: lesson.isCanceled ? "calendar.badge.exclamationmark" : "calendar", size: 18)
                        .foregroundStyle(accent)
                }
            }
    }

    private var accent: Color {
        lesson.changeKind == .none ? Brand.primary : lesson.changeKind.color
    }
}

/// Display strings shared by the lesson card and its detail sheet. Cancelled
/// hours often arrive without a subject id, so the change's own subject is the
/// fallback before the generic "unknown lesson".
private enum LessonText {
    static func subject(for lesson: ScheduledLesson) -> String {
        lesson.subjectName ?? lesson.subjectAbbrev ?? changeSubject(for: lesson)
            ?? AppL10n.string("timetable.lesson.unknown")
    }

    static func abbreviation(for lesson: ScheduledLesson) -> String? {
        lesson.title.isEmpty ? changeSubject(for: lesson) : lesson.title
    }

    static func changeNote(for lesson: ScheduledLesson) -> String? {
        guard lesson.changeKind != .none,
              let description = lesson.change?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty
        else { return nil }
        return description
    }

    /// The school's note, unless it only restates the change chip and the room or
    /// teacher the card already shows ("Změna učebny: Aula." next to room Aula).
    static func distinctChangeNote(for lesson: ScheduledLesson) -> String? {
        guard let note = changeNote(for: lesson) else { return nil }
        guard !lesson.isCanceled else { return note }
        func normalized(_ text: String?) -> String? {
            guard let text else { return nil }
            let value = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
            return value.isEmpty ? nil : value
        }
        let shown = Set([lesson.roomAbbrev, lesson.roomName, lesson.teacherName, lesson.teacherAbbrev,
                         lesson.changeKind.localizedLabel].compactMap(normalized))
        let detail = note.split(separator: ":", maxSplits: 1).last.map(String.init)
        if let whole = normalized(note), shown.contains(whole) { return nil }
        if note.contains(":"), normalized(detail).map(shown.contains) ?? true { return nil }
        return note
    }

    private static func changeSubject(for lesson: ScheduledLesson) -> String? {
        guard let subject = lesson.change?.changeSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subject.isEmpty
        else { return nil }
        return subject
    }
}

// MARK: - Empty / holiday state

private struct EmptyDayView: View {
    let day: ScheduledDay?

    var body: some View {
        VStack(spacing: Spacing.md) {
            GradelyIcon(systemName: icon, size: 20)
                .foregroundStyle(Brand.primary.opacity(0.6))
            Text(title)
                .font(.gradely(.headline))
            if let message {
                Text(message)
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
        .accessibilityIdentifier("timetableEmptyDay")
    }

    private var icon: String {
        switch day?.dayType {
        case .holiday, .celebration, .directorDay: "sparkles"
        case .weekend: "sun.max"
        default: "calendar.badge.checkmark"
        }
    }

    private var title: String { Self.title(for: day) }

    static func title(for day: ScheduledDay?) -> String {
        switch day?.dayType {
        case .holiday, .celebration, .directorDay: AppL10n.string("timetable.holiday")
        case .weekend: AppL10n.string("timetable.weekend")
        default: AppL10n.string("timetable.empty.title")
        }
    }

    private var message: String? {
        if let description = day?.dayDescription, !description.isEmpty {
            return description
        }
        switch day?.dayType {
        case .holiday, .celebration, .directorDay, .weekend: return nil
        default: return AppL10n.string("timetable.empty.message")
        }
    }
}

// MARK: - Lesson detail

private struct LessonDetailSheet: View {
    let lesson: ScheduledLesson
    let day: ScheduledDay
    let scope: SchoolDataScope?
    let plannerStore: PlannerStore
    let resolver: PlannerLessonResolver
    let displayedWeek: TimetableWeek?
    let subjects: [PlannerSubjectReference]
    @State private var plannerItem: PlannerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        sheetContent
            .presentationDetents([.medium, .large])
            .gradelyMacSheetSize(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 460)
            .sheet(item: $plannerItem) { item in
                PlannerItemEditorView(item: item, store: plannerStore, resolver: resolver,
                                      displayedWeek: displayedWeek, subjects: subjects)
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(macOS)
        // The header names the lesson and carries the close button; a
        // NavigationStack would only add a grey title strip repeating it.
        detailScroll
        #else
        NavigationStack {
            detailScroll
                .navigationTitle(LessonText.subject(for: lesson))
                .gradelyNavigationTitleDisplayMode(.inline)
                .gradelyModalDismissButton {
                    dismiss()
                }
        }
        #endif
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                // The change is the news: show it before the regular details.
                if let change = lesson.change, lesson.changeKind != .none {
                    changeCard(change)
                }

                SettingsSurface {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        DetailRow(systemImage: "clock", title: "timetable.detail.time", value: timeText)
                        if let teacher = lesson.teacherName ?? lesson.teacherAbbrev {
                            DetailRow(systemImage: "person.fill", title: "timetable.detail.teacher", value: teacher)
                        }
                        if let room = lesson.roomName ?? lesson.roomAbbrev {
                            DetailRow(systemImage: "door.left.hand.open", title: "timetable.detail.room", value: room)
                        }
                        if !lesson.groups.isEmpty {
                            DetailRow(
                                systemImage: "person.3.fill",
                                title: "timetable.detail.group",
                                value: lesson.groups.joined(separator: ", ")
                            )
                        }
                        if !lesson.cycles.isEmpty {
                            DetailRow(
                                systemImage: "calendar",
                                title: "timetable.detail.cycles",
                                value: lesson.cycles.joined(separator: ", ")
                            )
                        }
                        if let theme = lesson.theme {
                            DetailRow(systemImage: "text.book.closed.fill", title: "timetable.detail.theme", value: theme)
                        }
                        if lesson.hasHomework {
                            DetailRow(
                                systemImage: "checklist",
                                title: "timetable.detail.homework",
                                value: AppL10n.string("timetable.detail.homework.has")
                            )
                        }
                    }
                }

                if let scope {
                    plannerSection(scope: scope)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background {
            SettingsBackground()
        }
    }

    /// Planning starts here: the hour's detail is the only place an item can be
    /// attached to a lesson or a day.
    @ViewBuilder
    private func plannerSection(scope: SchoolDataScope) -> some View {
        let attached = plannerStore.attachedItems(to: lesson, on: day, scope: scope)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: "planner.title")

            if !attached.isEmpty {
                SettingsSurface(padding: Spacing.md) {
                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(attached.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                            }
                            Button { plannerItem = item } label: {
                                HStack(spacing: Spacing.sm) {
                                    PlannerItemSummary(item: item)
                                    SettingsDisclosureIcon()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("lessonPlannerItem-\(item.id)")
                        }
                    }
                }
            }

            Button {
                plannerItem = PlannerItem.linked(to: lesson, on: day, scope: scope)
            } label: {
                GradelyLabel(AppL10n.string("planner.addFromLesson"), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!plannerStore.isLoaded)
            .accessibilityIdentifier("lessonAddPlannerButton")
        }
    }

    /// macOS has no navigation bar here, so the sheet names the lesson itself and
    /// carries the close button.
    @ViewBuilder private var header: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(LessonText.subject(for: lesson))
                .font(.gradely(.title2).bold())
                .strikethrough(lesson.isCanceled)
                .lineLimit(2)
            Spacer(minLength: Spacing.sm)
            Button {
                dismiss()
            } label: {
                GradelyModalCloseLabel()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(AppL10n.string("action.done"))
            .accessibilityIdentifier("modalDismissButton")
        }
        #endif
    }

    private var timeText: String {
        lesson.hour.beginTime.isEmpty
            ? lesson.hour.caption
            : "\(lesson.hour.beginTime) – \(lesson.hour.endTime)"
    }

    private func changeCard(_ change: TimetableChange) -> some View {
        SettingsSurface {
            HStack(alignment: .top, spacing: Spacing.md) {
                GradelyIcon(systemName: lesson.isCanceled ? "calendar.badge.exclamationmark" : "exclamationmark.triangle.fill", size: 20)
                    .foregroundStyle(lesson.changeKind.color)
                    .frame(width: 36, height: 36)
                    .background(lesson.changeKind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(lesson.changeKind.localizedLabel ?? AppL10n.string("timetable.detail.change"))
                        .font(.gradely(.headline))
                        .foregroundStyle(lesson.changeKind.color)

                    if let description = change.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        Text(description)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DetailRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(systemName: systemImage)
                .font(.gradely(.subheadline))
                .foregroundStyle(Brand.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gradely(.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.gradely(.subheadline))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Helpers

private enum LessonClock {
    /// Whether `now` falls inside the lesson's time window on a day that is today.
    static func isCurrent(_ hour: TimetableHour, isToday: Bool, now: Date = Date()) -> Bool {
        guard
            isToday,
            !hour.beginTime.isEmpty, !hour.endTime.isEmpty,
            let start = TimetableLessonTiming.date(hour.beginTime, on: now),
            let end = TimetableLessonTiming.date(hour.endTime, on: now)
        else {
            return false
        }
        return now >= start && now <= end
    }

}

// MARK: - Previews

#Preview("Light") {
    TimetableView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache()
        )
    )
}

#Preview("Dark") {
    TimetableView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache()
        )
    )
    .preferredColorScheme(.dark)
}
