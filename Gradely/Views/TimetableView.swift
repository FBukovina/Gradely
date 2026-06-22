import SwiftUI

struct TimetableView: View {
    @State private var viewModel: TimetableViewModel
    @State private var selectedLesson: ScheduledLesson?
    private let repository: SchoolRepository
    private let supportTipProvider: any SupportTipProviding
    let onSignedOut: () -> Void

    init(
        repository: SchoolRepository,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        onSignedOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: TimetableViewModel(repository: repository))
        self.repository = repository
        self.supportTipProvider = supportTipProvider
        self.onSignedOut = onSignedOut
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "rozvrh.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .gradelyTopBarLeading) {
                        CreditsToolbarButton()
                    }

                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                        }
                        .disabled(viewModel.isLoading || viewModel.isRefreshing)
                        .accessibilityLabel(String(localized: "action.refresh"))
                        .accessibilityIdentifier("timetableRefreshButton")
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
                .sheet(item: $selectedLesson) { lesson in
                    LessonDetailSheet(lesson: lesson)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.week == nil {
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text("timetable.loading")
            }
            .accessibilityIdentifier("timetableLoadingView")
        } else if let errorMessage = viewModel.errorMessage, viewModel.week == nil {
            ContentUnavailableView {
                Label(String(localized: "error.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(String(localized: "action.retry")) {
                    Task { await viewModel.refresh() }
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
            WeekNavBar(viewModel: viewModel)
            DayStrip(viewModel: viewModel)
            Divider()
            dayContent
        }
        .background(Color.gradelyGroupedBackground.ignoresSafeArea())
    }

    private var dayContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("timetable.refreshing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, Spacing.xs)
                }

                if let day = viewModel.selectedDay, day.hasLessons {
                    ForEach(day.lessons) { lesson in
                        LessonRow(lesson: lesson, isToday: day.isToday) {
                            selectedLesson = lesson
                        }
                        .accessibilityIdentifier("lessonRow-\(lesson.id)")
                    }
                } else {
                    EmptyDayView(day: viewModel.selectedDay)
                        .padding(.top, Spacing.xxl)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("timetableList")
    }
}

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
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !viewModel.isViewingCurrentWeek {
                    Button {
                        Task { await viewModel.goToToday() }
                    } label: {
                        Text("timetable.today")
                            .font(.caption.weight(.semibold))
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
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Brand.primary)
                .frame(width: 40, height: 40)
                .background(Brand.primary.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(String(localized: label))
        .accessibilityIdentifier(id)
    }
}

private struct DayStrip: View {
    let viewModel: TimetableViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.days) { day in
                    DayChip(day: day, isSelected: day.id == viewModel.selectedDay?.id) {
                        viewModel.select(dayID: day.id)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)
        }
    }
}

private struct DayChip: View {
    let day: ScheduledDay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(weekdaySymbol)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                Text(dayNumber)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundStyle(isSelected ? Brand.onAccent : LessonChangeKind.canceled.color)
                    .opacity(day.hasChanges ? 1 : 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Brand.onAccent) : AnyShapeStyle(.primary))
            .frame(width: 52, height: 66)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.gradelySecondaryGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.primary, lineWidth: day.isToday && !isSelected ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dayChip-\(day.dayOfWeek)")
    }

    private var weekdaySymbol: String {
        if let date = day.date {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = day.dayOfWeek % 7 // API: 1 = Monday … 7 = Sunday; symbols[0] = Sunday
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private var dayNumber: String {
        guard let date = day.date else { return "" }
        return date.formatted(.dateTime.day())
    }
}

// MARK: - Lesson row

private struct LessonRow: View {
    let lesson: ScheduledLesson
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                hourRail
                LessonCard(lesson: lesson, isCurrent: LessonClock.isCurrent(lesson.hour, isToday: isToday))
            }
        }
        .buttonStyle(.plain)
    }

    private var hourRail: some View {
        VStack(spacing: 2) {
            Text(lesson.hour.caption)
                .font(.headline.weight(.bold))
                .monospacedDigit()
            if !lesson.hour.beginTime.isEmpty {
                Text(lesson.hour.beginTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(lesson.hour.endTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(width: 44)
        .padding(.top, Spacing.sm)
    }
}

private struct LessonCard: View {
    let lesson: ScheduledLesson
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(accent.opacity(0.14))
                .frame(width: 46, height: 46)
                .overlay {
                    Text(lesson.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subjectTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .strikethrough(lesson.isCanceled, color: .secondary)

                if lesson.roomAbbrev != nil || teacher != nil {
                    HStack(spacing: Spacing.md) {
                        if let room = lesson.roomAbbrev {
                            inlineLabel(room, systemImage: "door.left.hand.open")
                        }
                        if let teacher {
                            inlineLabel(teacher, systemImage: "person.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let theme = lesson.theme {
                    Text(theme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            if let label = lesson.changeKind.localizedLabel {
                StatusChip(text: label, color: lesson.changeKind.color)
            }
        }
        .padding(Spacing.md)
        .opacity(lesson.isCanceled ? 0.6 : 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.gradelySecondaryGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isCurrent ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var accent: Color {
        lesson.changeKind == .none ? Brand.primary : lesson.changeKind.color
    }

    private var borderColor: Color {
        isCurrent ? Brand.primary : Color.primary.opacity(0.05)
    }

    private var subjectTitle: String {
        lesson.subjectName ?? lesson.subjectAbbrev ?? String(localized: "timetable.lesson.unknown")
    }

    private var teacher: String? {
        lesson.teacherName ?? lesson.teacherAbbrev
    }

    private func inlineLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .lineLimit(1)
    }
}

// MARK: - Empty / holiday state

private struct EmptyDayView: View {
    let day: ScheduledDay?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Brand.primary.opacity(0.6))
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
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

    private var title: String {
        switch day?.dayType {
        case .holiday, .celebration, .directorDay: String(localized: "timetable.holiday")
        case .weekend: String(localized: "timetable.weekend")
        default: String(localized: "timetable.empty.title")
        }
    }

    private var message: String? {
        if let description = day?.dayDescription, !description.isEmpty {
            return description
        }
        switch day?.dayType {
        case .holiday, .celebration, .directorDay, .weekend: return nil
        default: return String(localized: "timetable.empty.message")
        }
    }
}

// MARK: - Lesson detail

private struct LessonDetailSheet: View {
    let lesson: ScheduledLesson
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header

                    Card {
                        VStack(alignment: .leading, spacing: Spacing.md) {
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
                            if let theme = lesson.theme {
                                DetailRow(systemImage: "text.book.closed.fill", title: "timetable.detail.theme", value: theme)
                            }
                            if lesson.hasHomework {
                                DetailRow(
                                    systemImage: "checklist",
                                    title: "timetable.detail.homework",
                                    value: String(localized: "timetable.detail.homework.has")
                                )
                            }
                        }
                    }

                    if let change = lesson.change, lesson.changeKind != .none {
                        changeCard(change)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.gradelyGroupedBackground.ignoresSafeArea())
            .navigationTitle(lesson.subjectName ?? lesson.title)
            .gradelyNavigationTitleDisplayMode(.inline)
        }
        .gradelyModalDismissButton {
            dismiss()
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(lesson.hour.beginTime.isEmpty
                 ? lesson.hour.caption
                 : "\(lesson.hour.beginTime) – \(lesson.hour.endTime)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(lesson.subjectName ?? lesson.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private func changeCard(_ change: TimetableChange) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(lesson.changeKind.localizedLabel ?? String(localized: "timetable.detail.change"))
                        .font(.headline)
                }
                .foregroundStyle(lesson.changeKind.color)

                if let description = change.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Brand.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
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
            let start = time(hour.beginTime, on: now),
            let end = time(hour.endTime, on: now)
        else {
            return false
        }
        return now >= start && now <= end
    }

    private static func time(_ string: String, on day: Date) -> Date? {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
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
    ) {}
}

#Preview("Dark") {
    TimetableView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache()
        )
    ) {}
    .preferredColorScheme(.dark)
}
