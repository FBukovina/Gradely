import SwiftUI

struct AbsenceOverrideEditorView: View {
    @Bindable var viewModel: AbsenceOverrideEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("absence.override.localOnly")
                        .foregroundStyle(.secondary)
                    Text(viewModel.title).font(.headline)
                }
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let error = viewModel.errorMessage {
                    Section {
                        GradelyLabel(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(GradeBand.poor.foregroundColor)
                        if viewModel.context == nil {
                            Button("action.retry") { Task { await viewModel.load() } }
                        }
                    }
                    .accessibilityIdentifier("absenceOverrideError")
                }
                if let context = viewModel.context {
                    if context.existingOverride?.pauseReason != nil {
                        Section {
                            GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle")
                            Text("absence.override.reviewMessage").foregroundStyle(.secondary)
                        }
                    }
                    if !viewModel.hasOriginalSelection {
                        originalSelection(context)
                    } else {
                        allocationSection(context)
                        previewSection(context)
                    }
                }
            }
            .navigationTitle("absence.override.editTitle")
            .gradelyNavigationTitleDisplayMode(.inline)
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
        .interactiveDismissDisabled(viewModel.isSaving)
        .accessibilityIdentifier("absenceOverrideEditor")
    }

    private func originalSelection(_ context: AbsenceOverrideEditorContext) -> some View {
        Section {
            Text("absence.override.originalMessage").font(.subheadline).foregroundStyle(.secondary)
            Text(String(format: AppL10n.string("absence.manual.selectedCount"), viewModel.originalLessonIDs.count, viewModel.originalCount))
                .font(.subheadline.weight(.semibold))
            ForEach(context.lessons) { lesson in
                Button {
                    viewModel.toggleOriginalLesson(lesson.id)
                } label: {
                    HStack {
                        Text(lesson.displayTitle).foregroundStyle(.primary)
                        Spacer()
                        GradelyIcon(systemName: viewModel.originalLessonIDs.contains(lesson.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Brand.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("absenceOverrideOriginal-\(lesson.id)")
            }
            Button("absence.override.confirmOriginal") { viewModel.confirmOriginalLessons() }
                .disabled(viewModel.originalLessonIDs.count != viewModel.originalCount)
                .accessibilityIdentifier("absenceOverrideConfirmOriginal")
            Button("absence.override.manualAllocation") { viewModel.useManualAllocations() }
                .accessibilityIdentifier("absenceOverrideManualButton")
        } header: {
            Text("absence.override.originalTitle")
        }
    }

    private func allocationSection(_ context: AbsenceOverrideEditorContext) -> some View {
        Section {
            Text("absence.override.allocationMessage").font(.subheadline).foregroundStyle(.secondary)
            if viewModel.availableCategories.count > 1 {
                Text("absence.override.mixedCategories").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($viewModel.allocations) { $allocation in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if !allocation.lessonTitle.isEmpty {
                        Text(allocation.lessonTitle).font(.subheadline.weight(.semibold))
                    }
                    if context.subjects.isEmpty {
                        TextField(AppL10n.string("absence.override.subject"), text: $allocation.subjectName)
                            .accessibilityIdentifier("absenceOverrideSubject-\(allocation.id)")
                    } else {
                        Picker("absence.override.subject", selection: Binding(
                            get: { viewModel.selectedSubjectID(for: allocation) },
                            set: { viewModel.selectSubject($0, allocationID: allocation.id) }
                        )) {
                            Text("absence.override.chooseSubject").tag("")
                            ForEach(context.subjects) { subject in
                                Text(subject.subjectName).tag(subject.id)
                            }
                        }
                        .accessibilityIdentifier("absenceOverrideSubject-\(allocation.id)")
                    }
                    Picker("absence.override.category", selection: $allocation.category) {
                        Text("absence.override.chooseCategory").tag(AbsenceOverrideCategory?.none)
                        ForEach(viewModel.availableCategories, id: \.rawValue) { category in
                            Text(category.localizedTitle).tag(Optional(category))
                        }
                    }
                    .accessibilityIdentifier("absenceOverrideCategory-\(allocation.id)")
                    Toggle("absence.override.hideLesson", isOn: $allocation.isHidden)
                        .accessibilityIdentifier("absenceOverrideHide-\(allocation.id)")
                }
                .padding(.vertical, Spacing.xs)
            }
            Button("absence.override.hideDay") { viewModel.hideEntireDay() }
                .accessibilityIdentifier("absenceOverrideHideDay")
            Button("absence.override.clearSelection") { viewModel.clearHiddenSelection() }
                .disabled(viewModel.hiddenCount == 0)
            if !context.lessons.isEmpty {
                Button("absence.override.changeOriginal") { viewModel.reviseOriginalLessons() }
            }
            if !viewModel.usesManualAllocations {
                Button("absence.override.manualAllocation") { viewModel.useManualAllocations() }
            }
        } header: {
            Text("absence.override.hideSelected")
        }
    }

    private func previewSection(_ context: AbsenceOverrideEditorContext) -> some View {
        Section {
            LabeledContent("absence.override.schoolCount", value: "\(viewModel.originalCount)")
            LabeledContent("absence.override.hiddenCount", value: "\(viewModel.hiddenCount)")
            LabeledContent("absence.override.resultCount", value: "\(viewModel.resultingCount)")
                .font(.headline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("absenceOverridePreview")
            ForEach(viewModel.availableCategories, id: \.rawValue) { category in
                let hidden = viewModel.allocations.filter { $0.category == category && $0.isHidden }.count
                LabeledContent(category.localizedTitle, value: "\(category.count(in: context.rawDay)) → \(max(0, category.count(in: context.rawDay) - hidden))")
            }
            if let message = viewModel.hiddenSubjectMappingError {
                GradelyLabel(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(GradeBand.poor.foregroundColor)
                    .accessibilityIdentifier("absenceOverrideSubjectMappingError")
            } else if !viewModel.canSave && viewModel.hiddenCount > 0 {
                Text("absence.override.validationMessage").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("absence.override.previewTitle")
        }
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
                            Text(saved.dateKey).font(.headline)
                            Spacer()
                            Text("\(saved.hiddenAllocationIDs.count)").monospacedDigit()
                        }
                        if viewModel.overrideMetadata.reviewOverrides.contains(where: { $0.id == saved.id }) {
                            GradelyLabel("absence.override.needsReview", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(GradeBand.average.foregroundColor)
                            Text("absence.override.reviewMessage").font(.caption).foregroundStyle(.secondary)
                        } else {
                            GradelyLabel("absence.override.adjusted", systemImage: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(saved.allocations.filter { saved.hiddenAllocationIDs.contains($0.id) }) { allocation in
                            HStack {
                                Text(allocation.subjectName)
                                Spacer()
                                Text(allocation.category.localizedTitle).foregroundStyle(.secondary)
                            }.font(.caption)
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
