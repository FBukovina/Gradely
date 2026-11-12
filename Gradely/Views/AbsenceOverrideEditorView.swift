import SwiftUI

struct AbsenceOverrideEditorView: View {
    @Bindable var viewModel: AbsenceOverrideEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The lesson number's column, as wide as two of its digits.
    @ScaledMetric(relativeTo: .headline) private var hourColumnWidth: CGFloat = 24

    var body: some View {
        ModalNavigationContainer {
            AbsenceSheetPage(title: "absence.override.editTitle") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.title)
                        .font(.gradely(.headline))
                    Text("absence.override.removeHint")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                    Text("absence.override.localOnly")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                }

                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let error = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        GradelyLabel(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(GradeBand.poor.foregroundColor)
                        if viewModel.context == nil {
                            Button("action.retry") { Task { await viewModel.load() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    .accessibilityIdentifier("absenceOverrideError")
                }
                if let context = viewModel.context {
                    if context.existingOverride?.pauseReason != nil {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle")
                            Text("absence.override.reviewMessage")
                                .font(.gradely(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !viewModel.hasOriginalSelection {
                        originalSelection(context)
                    } else {
                        allocationSection(context)
                        summary(context)
                        actions(context)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { Task { await viewModel.save() } }
                        .disabled(!viewModel.canSave)
                        .accessibilityIdentifier("absenceOverrideSaveButton")
                }
            }
            .disabled(viewModel.isSaving)
            .overlay { if viewModel.isSaving { ProgressView().controlSize(.large) } }
            .task { await viewModel.load() }
            .onChange(of: viewModel.didSave) { _, saved in if saved { dismiss() } }
        }
        .gradelyMacSheetSize(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 600)
        .interactiveDismissDisabled(viewModel.isSaving)
        .accessibilityIdentifier("absenceOverrideEditor")
    }

    @ViewBuilder
    private func originalSelection(_ context: AbsenceOverrideEditorContext) -> some View {
        PlainSection {
            VStack(alignment: .leading, spacing: 2) {
                PlainSectionTitle("absence.override.originalTitle")
                Text(String(format: AppL10n.string("absence.manual.selectedCount"), viewModel.originalLessonIDs.count, viewModel.originalCount))
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
            }
        } content: {
            ForEach(context.lessons) { lesson in
                AbsenceLessonToggleRow(
                    lesson: lesson,
                    isSelected: viewModel.originalLessonIDs.contains(lesson.id)
                ) {
                    viewModel.toggleOriginalLesson(lesson.id)
                }
                .accessibilityIdentifier("absenceOverrideOriginal-\(lesson.id)")
            }
        }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button("absence.override.confirmOriginal") { viewModel.confirmOriginalLessons() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.originalLessonIDs.count != viewModel.originalCount)
                .accessibilityIdentifier("absenceOverrideConfirmOriginal")
            Button("absence.override.manualAllocation") { viewModel.useManualAllocations() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("absenceOverrideManualButton")
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func allocationSection(_ context: AbsenceOverrideEditorContext) -> some View {
        PlainSection {
            VStack(alignment: .leading, spacing: 2) {
                PlainSectionTitle("absence.override.lessonsTitle")
                if viewModel.availableCategories.count > 1 {
                    Text("absence.override.mixedCategories")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            ForEach($viewModel.allocations) { $allocation in
                allocationRow($allocation, context: context)
            }
        }
    }

    private func allocationRow(
        _ allocation: Binding<AbsenceOverrideEditorViewModel.DraftAllocation>,
        context: AbsenceOverrideEditorContext
    ) -> some View {
        let lesson = context.lessons.first { $0.id == allocation.wrappedValue.lessonID }
        // At accessibility sizes the button goes under the lesson: beside
        // it, the subject pushed it off the sheet.
        let stacked = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: stacked ? .firstTextBaseline : .center, spacing: Spacing.md) {
                Text(lesson?.hourCaption ?? "–")
                    .font(.gradely(.headline).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: hourColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: stacked ? Spacing.sm : 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        if allocation.wrappedValue.subjectName.isEmpty || allocation.wrappedValue.lessonID == nil {
                            subjectField(allocation, context: context)
                        } else {
                            Text(allocation.wrappedValue.subjectName)
                                .font(.gradely(.subheadline).weight(.semibold))
                                .strikethrough(allocation.wrappedValue.isHidden)
                                .foregroundStyle(allocation.wrappedValue.isHidden ? .secondary : .primary)
                        }
                        let detail = detailCaption(for: allocation.wrappedValue, lesson: lesson)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.gradely(.caption).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if allocation.wrappedValue.isHidden {
                            Text("absence.override.removed")
                                .font(.gradely(.caption))
                                .foregroundStyle(GradeBand.poor.foregroundColor)
                        }
                    }
                    if stacked {
                        removeButton(allocation)
                    }
                }

                if !stacked {
                    Spacer(minLength: Spacing.sm)
                    removeButton(allocation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.availableCategories.count > 1 {
                Picker("absence.override.category", selection: allocation.category) {
                    Text("absence.override.chooseCategory").tag(AbsenceOverrideCategory?.none)
                    ForEach(viewModel.availableCategories, id: \.rawValue) { category in
                        Text(category.localizedTitle).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("absenceOverrideCategory-\(allocation.wrappedValue.id)")
            }
        }
    }

    private func removeButton(
        _ allocation: Binding<AbsenceOverrideEditorViewModel.DraftAllocation>
    ) -> some View {
        Button {
            allocation.wrappedValue.isHidden.toggle()
        } label: {
            Text(allocation.wrappedValue.isHidden
                ? AppL10n.string("absence.override.putBack")
                : AppL10n.string("absence.override.remove"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(allocation.wrappedValue.isHidden ? Brand.primary : GradeBand.poor.foregroundColor)
        .accessibilityIdentifier(allocation.wrappedValue.isHidden
            ? "absenceOverridePutBack-\(allocation.wrappedValue.id)"
            : "absenceOverrideRemove-\(allocation.wrappedValue.id)")
    }

    /// Stands in for the subject name when the timetable couldn't place the hour.
    @ViewBuilder
    private func subjectField(
        _ allocation: Binding<AbsenceOverrideEditorViewModel.DraftAllocation>,
        context: AbsenceOverrideEditorContext
    ) -> some View {
        if context.subjects.isEmpty {
            TextField(AppL10n.string("absence.override.subject"), text: allocation.subjectName)
                .font(.gradely(.subheadline).weight(.semibold))
                .accessibilityIdentifier("absenceOverrideSubject-\(allocation.wrappedValue.id)")
        } else if dynamicTypeSize.isAccessibilitySize {
            // The system menu picker stays one line tall and as wide as its
            // text, which at these sizes is wider than the sheet. This
            // label wraps.
            let selectedID = viewModel.selectedSubjectID(for: allocation.wrappedValue)
            Menu {
                subjectPicker(allocation, context: context)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(verbatim: context.subjects.first { $0.id == selectedID }?.subjectName
                        ?? AppL10n.string("absence.override.chooseSubject"))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    GradelyIcon(systemName: "chevron.up.chevron.down", size: 13)
                }
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(Brand.primary)
                .frame(minHeight: ControlMetrics.minHeight)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("absenceOverrideSubject-\(allocation.wrappedValue.id)")
        } else {
            subjectPicker(allocation, context: context)
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("absenceOverrideSubject-\(allocation.wrappedValue.id)")
        }
    }

    private func subjectPicker(
        _ allocation: Binding<AbsenceOverrideEditorViewModel.DraftAllocation>,
        context: AbsenceOverrideEditorContext
    ) -> some View {
        Picker("absence.override.subject", selection: Binding(
            get: { viewModel.selectedSubjectID(for: allocation.wrappedValue) },
            set: { viewModel.selectSubject($0, allocationID: allocation.wrappedValue.id) }
        )) {
            Text("absence.override.chooseSubject").tag("")
            ForEach(context.subjects) { subject in
                Text(subject.subjectName).tag(subject.id)
            }
        }
    }

    private func detailCaption(
        for allocation: AbsenceOverrideEditorViewModel.DraftAllocation,
        lesson: AbsenceLessonCandidate?
    ) -> String {
        var parts: [String] = []
        if let lesson, !lesson.timeRange.isEmpty {
            parts.append(lesson.timeRange)
        }
        if viewModel.availableCategories.count > 1, let category = allocation.category {
            parts.append(category.localizedTitle)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func summary(_ context: AbsenceOverrideEditorContext) -> some View {
        HStack {
            Text("absence.override.resultCount")
                .font(.gradely(.subheadline).weight(.semibold))
            Spacer(minLength: Spacing.sm)
            Text("\(viewModel.originalCount) → \(viewModel.resultingCount)")
                .font(.gradely(.headline).monospacedDigit())
        }
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("absenceOverridePreview")

        if let message = viewModel.hiddenSubjectMappingError {
            GradelyLabel(message, systemImage: "exclamationmark.triangle")
                .font(.gradely(.caption))
                .foregroundStyle(GradeBand.poor.foregroundColor)
                .accessibilityIdentifier("absenceOverrideSubjectMappingError")
        } else if !viewModel.canSave && viewModel.hiddenCount > 0 {
            Text("absence.override.validationMessage")
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private func actions(_ context: AbsenceOverrideEditorContext) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button("absence.override.removeDay") { viewModel.hideEntireDay() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("absenceOverrideHideDay")
            Button("absence.override.putAllBack") { viewModel.clearHiddenSelection() }
                .buttonStyle(.bordered)
                .disabled(viewModel.hiddenCount == 0)
            if !context.lessons.isEmpty {
                Button("absence.override.changeOriginal") { viewModel.reviseOriginalLessons() }
                    .buttonStyle(.bordered)
            }
            if !viewModel.usesManualAllocations {
                Button("absence.override.manualAllocation") { viewModel.useManualAllocations() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, Spacing.xs)
    }
}

struct HiddenAbsencesView: View {
    @Bindable var viewModel: AbsenceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRestoreAll = false

    var body: some View {
        ModalNavigationContainer {
            AbsenceSheetPage(title: "absence.override.hiddenTitle") {
                if let error = viewModel.overrideErrorMessage {
                    GradelyLabel(error, systemImage: "exclamationmark.triangle")
                        .font(.gradely(.subheadline))
                        .foregroundStyle(GradeBand.poor.foregroundColor)
                }

                if viewModel.allOverrides.isEmpty {
                    emptyState
                } else {
                    PlainSection(footer: "absence.override.localOnly") {
                        ForEach(viewModel.allOverrides) { saved in
                            dayRow(saved)
                        }
                    }
                    .disabled(viewModel.isRestoringOverrides)

                    Button("absence.override.restoreAll", role: .destructive) { confirmRestoreAll = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(viewModel.isRestoringOverrides)
                        .padding(.horizontal, Spacing.xs)
                        .accessibilityIdentifier("absenceHiddenRestoreAll")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } }
            }
            .confirmationDialog("absence.override.restoreAll", isPresented: $confirmRestoreAll, titleVisibility: .visible) {
                Button("absence.override.restoreAll", role: .destructive) { Task { await viewModel.restoreAllOverrides() } }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("absence.override.restoreAllMessage")
            }
            .sheet(item: $viewModel.editor) { editor in AbsenceOverrideEditorView(viewModel: editor) }
        }
        .gradelyMacSheetSize(minWidth: 460, idealWidth: 540, minHeight: 420, idealHeight: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absenceHiddenList")
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            GradelyIcon("view-off", size: 30)
                .foregroundStyle(.secondary)
            Text("absence.override.none")
                .font(.gradely(.headline))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl * 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("absenceHiddenEmpty")
    }

    /// One day: its date, the lessons hidden on it, and the two ways out.
    private func dayRow(_ saved: AbsenceDayOverride) -> some View {
        let day = dayTitle(saved.dateKey)
        let needsReview = viewModel.overrideMetadata.reviewOverrides.contains { $0.id == saved.id }

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: day)
                .font(.gradely(.headline))

            if needsReview {
                VStack(alignment: .leading, spacing: 2) {
                    GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle", iconSize: 13)
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(GradeBand.average.foregroundColor)
                    Text("absence.override.reviewMessage")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(saved.hiddenAllocations) { allocation in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(verbatim: allocation.subjectName)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.sm)
                        Text(verbatim: allocation.category.localizedTitle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.gradely(.subheadline))
                }
            }

            HStack(spacing: Spacing.lg) {
                Button {
                    viewModel.openOverrideEditor(dateKey: saved.dateKey)
                } label: {
                    linkLabel("absence.override.edit.short")
                }
                .accessibilityLabel(Text(verbatim: AppL10n.string("absence.override.editTitle") + ", " + day))
                .accessibilityIdentifier("absenceHiddenEdit-\(saved.dateKey)")

                Button {
                    Task { await viewModel.restoreOverride(dateKey: saved.dateKey) }
                } label: {
                    linkLabel("absence.override.restore.short")
                }
                .accessibilityLabel(Text(verbatim: AppL10n.string("absence.override.restore") + ", " + day))
                .accessibilityIdentifier("absenceHiddenRestore-\(saved.dateKey)")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.gradely(.subheadline).weight(.semibold))
            .foregroundStyle(Brand.primary)
            .frame(minHeight: ControlMetrics.minHeight)
            .contentShape(Rectangle())
    }

    /// "út 3. 11." instead of the stored 2026-11-03.
    private func dayTitle(_ dateKey: String) -> String {
        MarkDateFormatter.date(from: dateKey).map { SchoolDateFormatting.weekdayShortDate($0) } ?? dateKey
    }
}

extension AbsenceOverrideEditorViewModel: Identifiable {
    var id: String { dateKey }
}

extension AbsenceOverrideCategory {
    var localizedTitle: String {
        switch self {
        case .unsolved: AppL10n.string("absence.category.unsolved")
        case .ok: AppL10n.string("absence.category.ok")
        case .missed: AppL10n.string("absence.category.missed")
        case .late: AppL10n.string("absence.category.late")
        case .soon: AppL10n.string("absence.category.soon")
        case .school: AppL10n.string("absence.category.school")
        case .distanceTeaching: AppL10n.string("absence.category.distanceTeaching")
        }
    }
}
