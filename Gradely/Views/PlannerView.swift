import SwiftUI

struct PlannerView: View {
    let store: PlannerStore
    let resolver: PlannerLessonResolver
    var displayedWeek: TimetableWeek?
    var subjects: [PlannerSubjectReference] = []
    var focusedDay: Date? = nil
    var initialItemID: UUID? = nil
    @State private var showsCompleted = false
    @State private var editorItem: PlannerItem?
    @State private var deletionItem: PlannerItem?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                filter

                if let storageError = store.storageError {
                    notice(
                        message: storageError,
                        systemImage: "exclamationmark.triangle.fill",
                        action: AppL10n.string("action.retry"),
                        isEnabled: true
                    ) {
                        store.loadIfNeeded()
                    }
                }

                if store.pendingCalendarCount > 0 {
                    notice(
                        message: store.calendarError ?? AppL10n.string("planner.calendar.pending"),
                        systemImage: "calendar",
                        action: AppL10n.string("planner.calendar.retry"),
                        isEnabled: !store.isSyncing
                    ) {
                        Task { await store.syncPending(requestAccess: true) }
                    }
                }

                if visibleItems.isEmpty {
                    if store.isLoaded {
                        emptyState
                    }
                } else {
                    ForEach(groups) { group in
                        PlainSection {
                            PlainSectionTitle(verbatim: group.title)
                        } content: {
                            ForEach(group.items) { item in
                                row(item)
                                    .gradeySiriContext(.planner(item))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .gradelyScreenBackground()
        .navigationTitle(AppL10n.string("planner.title"))
        .gradelyNavigationTitleDisplayMode(.inline)
        .accessibilityIdentifier("plannerList")
        .toolbar {
            ToolbarItem(placement: .gradelyTopBarTrailing) {
                Button { editorItem = PlannerItem() } label: {
                    GradelyIcon(systemName: "plus")
                        .gradelyToolbarIconButton()
                }
                .disabled(!store.isLoaded)
                .accessibilityLabel(AppL10n.string("planner.add"))
                .accessibilityIdentifier("plannerAddButton")
            }
        }
        .task {
            await store.activate()
            if let initialItemID { editorItem = store.items.first { $0.id == initialItemID } }
        }
        .sheet(item: $editorItem) { item in
            PlannerItemEditorView(item: item, store: store, resolver: resolver, displayedWeek: displayedWeek, subjects: subjects)
        }
        .confirmationDialog(AppL10n.string("planner.delete.confirm"), isPresented: Binding(
            get: { deletionItem != nil }, set: { if !$0 { deletionItem = nil } }
        ), titleVisibility: .visible) {
            Button(AppL10n.string("planner.delete"), role: .destructive) {
                if let item = deletionItem {
                    perform { try await store.delete(id: item.id) }
                }
                deletionItem = nil
            }
        }
        .alert(AppL10n.string("error.title"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(AppL10n.string("action.done")) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Filter

    private var filter: some View {
        Picker(AppL10n.string("planner.filter"), selection: $showsCompleted) {
            Text(AppL10n.string("planner.upcoming")).tag(false)
            Text(AppL10n.string("planner.completed")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("plannerFilter")
    }

    // MARK: - Rows

    private func row(_ item: PlannerItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Button {
                perform { try await store.setCompleted(!item.isCompleted, id: item.id) }
            } label: {
                // Leading-aligned so the circle lines up with the section title.
                GradelyIcon(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle", size: 22)
                    .foregroundStyle(Brand.primary)
                    .frame(width: 40, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string(item.isCompleted ? "planner.markIncomplete" : "planner.markComplete"))
            .accessibilityIdentifier("plannerComplete-\(item.id)")

            Button { editorItem = item } label: {
                HStack(spacing: Spacing.sm) {
                    PlannerItemSummary(item: item)
                    Spacer(minLength: 0)
                    SettingsDisclosureIcon()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plannerItem-\(item.id)")
        }
        .contextMenu {
            Button(AppL10n.string("planner.edit")) { editorItem = item }
            Button(AppL10n.string("planner.delete"), role: .destructive) { deletionItem = item }
        }
    }

    // MARK: - Notices & empty state

    private func notice(
        message: String,
        systemImage: String,
        action: String,
        isEnabled: Bool,
        onAction: @escaping () -> Void
    ) -> some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    SettingsModalSystemIcon(systemName: systemImage)
                    Text(message)
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button(action: onAction) {
                    Text(action)
                        .font(.gradely(.subheadline).weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .disabled(!isEnabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            GradelyIcon(systemName: "checklist", size: 22)
                .foregroundStyle(Brand.primary.opacity(0.7))
            Text(AppL10n.string(showsCompleted ? "planner.empty.completed.title" : "planner.empty.title"))
                .font(.gradely(.headline))
            Text(AppL10n.string(showsCompleted ? "planner.empty.completed.message" : "planner.empty.message"))
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plannerEmptyState")
    }

    // MARK: - Grouping

    private var visibleItems: [PlannerItem] {
        store.items.filter { item in
            guard item.isCompleted == showsCompleted else { return false }
            guard let focusedDay else { return true }
            guard let day = PlannerDayProjection.day(for: item) else { return false }
            return Calendar.current.isDate(day, inSameDayAs: focusedDay)
        }
    }

    private struct Group: Identifiable {
        let date: Date?
        let title: String
        let items: [PlannerItem]
        var id: String { date.map { String($0.timeIntervalSinceReferenceDate) } ?? "undated" }
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        let grouped = Dictionary(grouping: visibleItems) { item -> Date? in
            // Group by the item's civil day, preserving all-day dates when the device travels.
            return PlannerDayProjection.day(for: item, calendar: calendar)
        }
        return grouped.map { date, items in
            let title: String
            if let date {
                if date == today { title = AppL10n.string("timetable.today") }
                else if date == tomorrow { title = AppL10n.string("planner.tomorrow") }
                else {
                    let weekday = date.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).weekday(.wide))
                    title = weekday.prefix(1).uppercased() + weekday.dropFirst() + " " + SchoolDateFormatting.shortDate(date)
                }
            } else {
                title = AppL10n.string("planner.undated")
            }
            return Group(date: date, title: title, items: items)
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Shared item summary

/// Title, type/subject metadata and schedule line for a planner item. Shared by the
/// planner list and the lesson detail sheet so both read the same way.
struct PlannerItemSummary: View {
    let item: PlannerItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.title)
                .font(.gradely(.headline))
                .strikethrough(item.isCompleted)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: Spacing.sm) {
                GradelyLabel(item.type.title, systemImage: item.type.systemImage, iconSize: 12)
                if let subject = item.subject {
                    Text(subject.displayName)
                }
                if item.calendarSyncEnabled {
                    GradelyIcon(systemName: "calendar", size: 12)
                }
            }
            .font(.gradely(.caption))
            .foregroundStyle(.secondary)

            if let schedule = item.scheduleSummary {
                GradelyLabel(schedule, systemImage: "clock", iconSize: 12)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlannerItem {
    /// Short day ("19. 10.") plus the time when the item has one.
    var scheduleSummary: String? {
        guard let date = orderingDate else { return nil }
        if let due = dueDate, dueHasTime {
            let time = due.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguageOverride.locale, timeZone: calendar.timeZone))
            return SchoolDateFormatting.shortDate(due, timeZone: calendar.timeZone) + " " + time
        }
        return SchoolDateFormatting.shortDate(date, timeZone: calendar.timeZone)
    }
}
