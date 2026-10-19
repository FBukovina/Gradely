import SwiftUI

struct AbsencePredictorCard: View {
    let result: AbsencePredictionResult
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        if result.hasSelection {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    PlainSectionTitle("absence.predictor.title")
                    Spacer()

                    Button(action: onClear) {
                        Text("action.clear")
                    }
                    .font(.gradely(.caption).weight(.bold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("absencePredictorClearButton")

                    Button(action: onOpen) {
                        Text("absence.predictor.edit")
                    }
                    .font(.gradely(.caption).weight(.bold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("absencePredictorOpenButton")
                }

                predictionSummary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.sm)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("absencePredictorCard")
        } else {
            Button(action: onOpen) {
                HStack(spacing: Spacing.md) {
                    GradelyIcon(systemName: "calendar.badge.clock")
                        .foregroundStyle(Brand.primary)
                    Text("absence.predictor.open")
                        .font(.gradely(.subheadline).weight(.semibold))
                    Spacer(minLength: Spacing.sm)
                    GradelyIcon(systemName: "chevron.right", size: 13)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("absencePredictorOpenButton")
        }
    }

    private var predictionSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                infoRow(
                    title: Text("absence.predictor.total"),
                    subtitle: Text(addedHoursDetail),
                    tint: Brand.primary
                )

                Spacer(minLength: Spacing.sm)

                Text("\(result.currentTotal.total) → \(result.projectedTotal.total)")
                    .font(.gradely(.headline).monospacedDigit())
                    .foregroundStyle(Brand.primary)
            }

            if !result.subjectRows.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(result.subjectRows) { row in
                        subjectRow(row)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("absencePredictorSubjectRows")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absencePredictionTotal")
    }

    private var addedHoursDetail: String {
        AppL10n.string("absence.predictor.okAdded")
            + " "
            + String.localizedStringWithFormat(
                AppL10n.string("absence.predictor.addedHours"),
                result.addedHours
            )
    }

    private func infoRow(title: Text, subtitle: Text, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            GradelyIcon(systemName: "calendar.badge.clock")
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .font(.gradely(.subheadline).weight(.bold))
                    .lineLimit(2)
                subtitle
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private func subjectRow(_ row: AbsencePredictionSubjectRow) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(row.subjectName)
                    .font(.gradely(.subheadline).weight(.bold))
                    .lineLimit(1)

                Text(detail(for: row))
                    .font(.gradely(.caption).monospacedDigit())
                    .foregroundStyle(row.exceedsThreshold ? GradeBand.poor.foregroundColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: Spacing.sm)

            StatusChip(
                text: String.localizedStringWithFormat(
                    AppL10n.string("absence.predictor.addedHours"),
                    row.addedHours
                ),
                color: row.exceedsThreshold ? GradeBand.poor.foregroundColor : Brand.secondary
            )
        }
        .accessibilityIdentifier("absencePredictionRow-\(row.id)")
    }

    private func detail(for row: AbsencePredictionSubjectRow) -> String {
        guard let currentBase = row.currentBase,
              let projectedBase = row.projectedBase,
              let currentPercentage = row.currentPercentage,
              let projectedPercentage = row.projectedPercentage else {
            return AppL10n.string("absence.predictor.baselineUnavailable")
        }

        let absentChange = String.localizedStringWithFormat(
            AppL10n.string("absence.predictor.subject.absentChange"),
            currentBase,
            projectedBase
        )
        let percentChange = String.localizedStringWithFormat(
            AppL10n.string("absence.predictor.subject.percentChange"),
            currentPercentage,
            projectedPercentage
        )
        return absentChange + " · " + percentChange
    }
}

struct AbsencePredictionSheet: View {
    @Bindable var viewModel: AbsenceViewModel

    var body: some View {
        ModalNavigationContainer {
            AbsenceSheetPage(title: "absence.predictor.sheet.title") {
                HStack(spacing: Spacing.md) {
                    Text("absence.predictor.date")
                        .font(.gradely(.subheadline).weight(.semibold))
                    Spacer(minLength: Spacing.sm)
                    DatePicker(
                        "absence.predictor.date",
                        selection: $viewModel.predictionSelectedDate,
                        in: viewModel.predictionMinimumDate...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("absencePredictorDatePicker")
                }

                predictionLessonSection

                Button(role: .destructive) {
                    viewModel.clearPredictionDraftSelections()
                } label: {
                    Text("action.clear")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.predictionDraftSelectedCount == 0)
                .accessibilityIdentifier("absencePredictorSheetClearButton")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        viewModel.cancelPredictionSheet()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        viewModel.commitPredictionSelections()
                    }
                    .accessibilityIdentifier("absencePredictorDoneButton")
                }
            }
            .task {
                await viewModel.loadPredictionLessonsForSelectedDate()
            }
            .onChange(of: viewModel.predictionSelectedDate) {
                Task { await viewModel.loadPredictionLessonsForSelectedDate() }
            }
        }
        .gradelyMacSheetSize(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 620)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absencePredictionSheet")
    }

    @ViewBuilder
    private var predictionLessonSection: some View {
        if viewModel.isLoadingPredictionLessons {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("absence.predictor.loading")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
            }
        } else if let message = viewModel.predictionErrorMessage {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                GradelyLabel(message, systemImage: "exclamationmark.triangle")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(GradeBand.poor.foregroundColor)

                Button("action.retry") {
                    Task { await viewModel.loadPredictionLessonsForSelectedDate() }
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
            }
        } else if viewModel.predictionLessons.isEmpty {
            GradelyLabel("absence.predictor.noLessons", systemImage: "calendar.badge.checkmark")
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("absencePredictorNoLessons")
        } else {
            PlainSection {
                Text(
                    String.localizedStringWithFormat(
                        AppL10n.string("absence.predictor.selectedCount"),
                        viewModel.predictionDraftSelectedCount
                    )
                )
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
            } content: {
                ForEach(viewModel.predictionLessons) { lesson in
                    AbsenceLessonToggleRow(
                        lesson: lesson,
                        isSelected: viewModel.isPredictionLessonSelected(lesson.id)
                    ) {
                        viewModel.togglePredictionLesson(lesson)
                    }
                    .accessibilityIdentifier("absencePredictorLesson-\(lesson.id)")
                }
            }
        }
    }
}
