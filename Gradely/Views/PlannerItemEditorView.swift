import SwiftUI

struct PlannerItemEditorView: View {
    let store: PlannerStore
    let resolver: PlannerLessonResolver
    var displayedWeek: TimetableWeek?
    var subjects: [PlannerSubjectReference] = []
    @State private var item: PlannerItem
    @State private var isSaving = false
    @State private var isFindingLesson = false
    @State private var nextLessonMessage: String?
    @State private var errorMessage: String?
    @State private var savedWithCalendarWarning = false
    @State private var isConfirmingDelete = false
    @State private var nextLessonTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(item: PlannerItem, store: PlannerStore, resolver: PlannerLessonResolver, displayedWeek: TimetableWeek? = nil, subjects: [PlannerSubjectReference] = []) {
        _item = State(initialValue: item)
        self.store = store
        self.resolver = resolver
        self.displayedWeek = displayedWeek
        self.subjects = subjects
    }

    private var isEditing: Bool { store.items.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    detailsSection
                    contextSection
                    dueSection
                    calendarSection
                    if isEditing { deleteButton }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .background { SettingsModalBackground() }
            .environment(\.timeZone, item.calendar.timeZone)
            .disabled(isSaving || isFindingLesson)
            .navigationTitle(AppL10n.string(isEditing ? "planner.edit" : "planner.add"))
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.string("action.cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("action.save")) {
                        Task { await save() }
                    }
                    .disabled(isSaving || isFindingLesson || !store.isLoaded
                              || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("plannerSaveButton")
                }
            }
            .overlay { if isSaving { ProgressView() } }
        }
        .tint(Brand.primary)
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.large])
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 560)
        #endif
        .onAppear { store.loadIfNeeded() }
        .onDisappear { nextLessonTask?.cancel() }
        .confirmationDialog(AppL10n.string("planner.delete.confirm"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(AppL10n.string("planner.delete"), role: .destructive) {
                Task { await delete() }
            }
        }
        .alert(AppL10n.string(savedWithCalendarWarning ? "planner.savedLocally" : "error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(AppL10n.string("action.done")) {
                if savedWithCalendarWarning { dismiss() }
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        section("planner.details") {
            LabeledContent(AppL10n.string("planner.field.type")) {
                Picker(AppL10n.string("planner.field.type"), selection: $item.type) {
                    ForEach(PlannerItemType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("plannerTypePicker")
            }

            TextField(AppL10n.string("planner.field.title"), text: $item.title)
                .textFieldStyle(.plain)
                .brandField()
                .accessibilityIdentifier("plannerTitleField")

            TextField(AppL10n.string("planner.field.notes"), text: Binding(
                get: { item.notes ?? "" }, set: { item.notes = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(3...8)
            .brandField()
            .accessibilityIdentifier("plannerNotesField")
        }
    }

    /// A lesson-linked item keeps the hour it was planned from; everything else
    /// picks a subject and an optional day.
    private var contextSection: some View {
        section("planner.context") {
            if let lesson = item.lesson {
                LabeledContent(AppL10n.string("planner.field.subject")) {
                    Text(item.subject?.name ?? AppL10n.string("planner.subject.none"))
                        .foregroundStyle(.secondary)
                }
                Divider()
                LabeledContent(AppL10n.string("planner.field.lesson")) {
                    Text(lesson.hourCaption)
                        .foregroundStyle(.secondary)
                }
                if let teacher = lesson.teacher {
                    GradelyLabel(teacher, systemImage: "person.fill", iconSize: 14)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let room = lesson.room {
                    GradelyLabel(room, systemImage: "door.left.hand.open", iconSize: 14)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if item.linkedDate == nil {
                    Text("planner.lesson.permanent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button(AppL10n.string("planner.lesson.unlink")) { item.lesson = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .accessibilityIdentifier("plannerUnlinkLessonButton")
            } else {
                if !subjectChoices.isEmpty {
                    LabeledContent(AppL10n.string("planner.field.subject")) {
                        Picker(AppL10n.string("planner.field.subject"), selection: Binding<String?>(
                            get: { item.subject.map(subjectKey) },
                            set: { key in item.subject = subjectChoices.first { subjectKey($0) == key } }
                        )) {
                            Text("planner.subject.none").tag(nil as String?)
                            ForEach(subjectChoices, id: \.selfKey) { subject in
                                Text(subject.name).tag(Optional(subjectKey(subject)))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("plannerSubjectPicker")
                    }

                    Divider()
                }

                Toggle(AppL10n.string("planner.field.linkDay"), isOn: Binding(
                    get: { item.linkedDate != nil },
                    set: { item.linkedDate = $0 ? item.calendar.startOfDay(for: Date()) : nil }
                ))
                .tint(Brand.primary)
                .accessibilityIdentifier("plannerLinkDayToggle")

                if item.linkedDate != nil {
                    DatePicker(AppL10n.string("planner.field.day"), selection: Binding(
                        get: { item.linkedDate ?? Date() }, set: { item.linkedDate = item.calendar.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                }
            }
        }
    }

    private var dueSection: some View {
        section("planner.due") {
            Toggle(AppL10n.string("planner.field.hasDueDate"), isOn: Binding(
                get: { item.dueDate != nil },
                set: {
                    item.dueDate = $0 ? (item.lesson?.start ?? item.linkedDate ?? Date()) : nil
                    if !$0 { item.dueHasTime = false }
                }
            ))
            .tint(Brand.primary)
            .accessibilityIdentifier("plannerDueToggle")

            if item.dueDate != nil {
                DatePicker(AppL10n.string("planner.field.dueDate"), selection: Binding(
                    get: { item.dueDate ?? Date() }, set: { item.dueDate = $0 }
                ), displayedComponents: item.dueHasTime ? [.date, .hourAndMinute] : [.date])

                Toggle(AppL10n.string("planner.field.includeTime"), isOn: $item.dueHasTime)
                    .tint(Brand.primary)
            }

            if item.lesson?.start != nil, item.subject != nil {
                Divider()
                Button {
                    findNextLesson()
                } label: {
                    HStack {
                        GradelyLabel(AppL10n.string("planner.nextLesson"), systemImage: "forward.fill")
                        Spacer()
                        if isFindingLesson { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .accessibilityIdentifier("plannerNextLessonButton")
            }

            if let nextLessonMessage {
                Text(nextLessonMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calendarSection: some View {
        section("planner.calendar.section") {
            Toggle(AppL10n.string("planner.calendar.toggle"), isOn: Binding(
                get: { item.calendarSyncEnabled && item.hasCalendarDate },
                set: { item.calendarSyncEnabled = $0 }
            ))
            .tint(Brand.primary)
            .disabled(!item.hasCalendarDate)
            .accessibilityIdentifier("plannerCalendarToggle")

            Text(AppL10n.string(item.hasCalendarDate ? "planner.calendar.explanation" : "planner.calendar.needsDate"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            GradelyLabel(AppL10n.string("planner.delete"), systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GradeBand.poor.foregroundColor)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(GradeBand.poor.foregroundColor.opacity(0.12))
        }
        .accessibilityIdentifier("plannerDeleteButton")
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: title)
            SettingsModalSurface {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private var subjectChoices: [PlannerSubjectReference] {
        var choices = subjects
        if let subject = item.subject, !choices.contains(where: { subjectKey($0) == subjectKey(subject) }) {
            choices.append(subject)
        }
        return choices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func subjectKey(_ subject: PlannerSubjectReference) -> String { subject.selfKey }

    private func findNextLesson() {
        isFindingLesson = true
        nextLessonMessage = nil
        nextLessonTask = Task {
            defer { isFindingLesson = false }
            do {
                let next = try await resolver.nextDate(after: item, displayedWeek: displayedWeek)
                try Task.checkCancellation()
                if let next {
                    item.dueDate = next
                    item.dueHasTime = true
                } else {
                    nextLessonMessage = AppL10n.string("planner.nextLesson.notFound")
                }
            } catch is CancellationError {
                return
            } catch {
                nextLessonMessage = error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(item)
            if let warning = store.calendarError, store.pendingCalendarCount > 0 {
                savedWithCalendarWarning = true
                errorMessage = warning
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.delete(id: item.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension PlannerSubjectReference {
    var selfKey: String { "\(scope.rawValue)|\(id)" }
}
