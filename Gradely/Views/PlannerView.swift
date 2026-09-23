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
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(group.title)
                                .font(.footnote.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .kerning(0.6)
                                .padding(.horizontal, Spacing.xs)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.items) { item in
                                row(item)
                                    .gradeySiriContext(.planner(item))                            }
                        }
                    }
                }

                Text("planner.private")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)
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
        HStack(spacing: Spacing.sm) {
            filterChip(AppL10n.string("planner.upcoming"), isSelected: !showsCompleted, id: "plannerFilterUpcoming") {
                showsCompleted = false
            }
            filterChip(AppL10n.string("planner.completed"), isSelected: showsCompleted, id: "plannerFilterCompleted") {
                showsCompleted = true
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel(AppL10n.string("planner.filter"))
    }

    private func filterChip(_ title: String, isSelected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Brand.onAccent) : AnyShapeStyle(Color.primary))
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm + 2)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.gradelySecondaryGroupedBackground))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    // MARK: - Rows

    private func row(_ item: PlannerItem) -> some View {
        SettingsModalSurface(padding: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button {
                    perform { try await store.setCompleted(!item.isCompleted, id: item.id) }
                } label: {
                    GradelyIcon(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle", size: 22)
                        .foregroundStyle(Brand.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.string(item.isCompleted ? "planner.markIncomplete" : "planner.markComplete"))
                .accessibilityIdentifier("plannerComplete-\(item.id)")

                Button { editorItem = item } label: {
                    HStack(spacing: Spacing.sm) {
                        PlannerItemSummary(item: item)
                        Spacer(minLength: 0)
                        SettingsModalDisclosureIcon()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plannerItem-\(item.id)")
            }
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
        SettingsModalSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    SettingsModalSystemIcon(systemName: systemImage)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button(action: onAction) {
                    Text(action)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .disabled(!isEnabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        SettingsModalSurface {
            VStack(spacing: Spacing.md) {
                GradelyIcon(systemName: "checklist", size: 22)
                    .foregroundStyle(Brand.primary.opacity(0.7))
                Text(AppL10n.string(showsCompleted ? "planner.empty.completed.title" : "planner.empty.title"))
                    .font(.headline)
                Text(AppL10n.string(showsCompleted ? "planner.empty.completed.message" : "planner.empty.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
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
                else { title = date.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).weekday(.wide).day().month(.abbreviated).year()) }
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
                .font(.headline)
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
            .font(.caption)
            .foregroundStyle(.secondary)

            if let schedule = item.scheduleSummary {
                GradelyLabel(schedule, systemImage: "clock", iconSize: 12)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlannerItem {
    /// One-line day (and time, when the item has one) in the app's language.
    var scheduleSummary: String? {
        guard let date = orderingDate else { return nil }
        let style = Date.FormatStyle(locale: AppLanguageOverride.locale, timeZone: calendar.timeZone)
        if let due = dueDate, dueHasTime {
            return due.formatted(style.day().month(.abbreviated).year().hour().minute())
        }
        return date.formatted(style.day().month(.abbreviated).year())
    }
}
