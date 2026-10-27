import SwiftUI

struct AbsenceOverrideEditorView: View {
    @Bindable var viewModel: AbsenceOverrideEditorViewModel
    @Environment(\.dismiss) private var dismiss

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
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text(lesson?.hourCaption ?? "–")
                    .font(.gradely(.headline).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)

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

                Spacer(minLength: Spacing.sm)

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
        } else {
            Picker("absence.override.subject", selection: Binding(
                get: { viewModel.selectedSubjectID(for: allocation.wrappedValue) },
                set: { viewModel.selectSubject($0, allocationID: allocation.wrappedValue.id) }
            )) {
                Text("absence.override.chooseSubject").tag("")
                ForEach(context.subjects) { subject in
                    Text(subject.subjectName).tag(subject.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("absenceOverrideSubject-\(allocation.wrappedValue.id)")
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
        NavigationStack {
            List {
                Section {
                    Text("absence.override.localOnly").foregroundStyle(.secondary)
                }
                if let error = viewModel.overrideErrorMessage {
                    Section {
                        GradelyLabel(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(GradeBand.poor.foregroundColor)
                    }
                }
                if viewModel.allOverrides.isEmpty {
                    ContentUnavailableView(AppL10n.string("absence.override.none"), systemImage: "eye")
                        .accessibilityIdentifier("absenceHiddenEmpty")
                }
                ForEach(viewModel.allOverrides) { saved in
                    Section {
                        HStack {
                            Text(saved.dateKey).font(.gradely(.headline))
                            Spacer()
                            Text("\(saved.hiddenAllocationIDs.count)").monospacedDigit()
                        }
                        if viewModel.overrideMetadata.reviewOverrides.contains(where: { $0.id == saved.id }) {
                            GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(GradeBand.average.foregroundColor)
                            Text("absence.override.reviewMessage").font(.gradely(.caption)).foregroundStyle(.secondary)
                        } else {
                            GradelyLabel("absence.override.adjusted", systemImage: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(saved.allocations.filter { saved.hiddenAllocationIDs.contains($0.id) }) { allocation in
                            HStack {
                                Text(allocation.subjectName)
                                Spacer()
                                Text(allocation.category.localizedTitle).foregroundStyle(.secondary)
                            }.font(.gradely(.caption))
                        }
                        Button("absence.override.editTitle") { viewModel.openOverrideEditor(dateKey: saved.dateKey) }
                            .accessibilityIdentifier("absenceHiddenEdit-\(saved.dateKey)")
                        Button("absence.override.restore") { Task { await viewModel.restoreOverride(dateKey: saved.dateKey) } }
                            .accessibilityIdentifier("absenceHiddenRestore-\(saved.dateKey)")
                    }
                    .disabled(viewModel.isRestoringOverrides)
                }
                if !viewModel.allOverrides.isEmpty {
                    Button("absence.override.restoreAll", role: .destructive) { confirmRestoreAll = true }
                        .disabled(viewModel.isRestoringOverrides)
                        .accessibilityIdentifier("absenceHiddenRestoreAll")
                }
            }
            .navigationTitle("absence.override.hiddenTitle")
            .gradelyNavigationTitleDisplayMode(.inline)
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
        .accessibilityIdentifier("absenceHiddenList")
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
