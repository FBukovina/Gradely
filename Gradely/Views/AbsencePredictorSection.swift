import SwiftUI

struct AbsencePredictorCard: View {
    let result: AbsencePredictionResult
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    SectionHeader("absence.predictor.title")
                    Spacer()

                    if result.hasSelection {
                        Button(action: onClear) {
                            Text("action.clear")
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("absencePredictorClearButton")
                    }

                    Button(action: onOpen) {
                        Text(openButtonKey)
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("absencePredictorOpenButton")
                }

                if result.hasSelection {
                    predictionSummary
                } else {
                    infoRow(
                        title: Text("absence.predictor.empty.title"),
                        subtitle: Text("absence.predictor.empty.message"),
                        tint: .secondary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absencePredictorCard")
    }

    private var openButtonKey: LocalizedStringKey {
        result.hasSelection ? "absence.predictor.edit" : "absence.predictor.open"
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
                    .font(.headline.monospacedDigit())
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
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                subtitle
                    .font(.caption)
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
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Text(detail(for: row))
                    .font(.caption.monospacedDigit())
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
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "absence.predictor.date",
                        selection: $viewModel.predictionSelectedDate,
                        in: viewModel.predictionMinimumDate...,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("absencePredictorDatePicker")
                }

                predictionLessonSection

                Section {
                    Button(role: .destructive) {
                        viewModel.clearPredictionDraftSelections()
                    } label: {
                        Text("action.clear")
                    }
                    .disabled(viewModel.predictionDraftSelectedCount == 0)
                    .accessibilityIdentifier("absencePredictorSheetClearButton")
                }
            }
            .navigationTitle("absence.predictor.sheet.title")
            .gradelyNavigationTitleDisplayMode(.inline)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("absencePredictionSheet")
    }

    @ViewBuilder
    private var predictionLessonSection: some View {
        if viewModel.isLoadingPredictionLessons {
            Section {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("absence.predictor.loading")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let message = viewModel.predictionErrorMessage {
            Section {
                GradelyLabel(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(GradeBand.poor.foregroundColor)

                Button("action.retry") {
                    Task { await viewModel.loadPredictionLessonsForSelectedDate() }
                }
            }
        } else if viewModel.predictionLessons.isEmpty {
            Section {
                GradelyLabel("absence.predictor.noLessons", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("absencePredictorNoLessons")
            }
        } else {
            Section {
                ForEach(viewModel.predictionLessons) { lesson in
                    Button {
                        viewModel.togglePredictionLesson(lesson)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if !lesson.timeRange.isEmpty {
                                    Text(lesson.timeRange)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if viewModel.isPredictionLessonSelected(lesson.id) {
                                GradelyIcon(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Brand.primary)
                            } else {
                                GradelyIcon(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("absencePredictorLesson-\(lesson.id)")
                }
            } header: {
                Text(
                    String.localizedStringWithFormat(
                        AppL10n.string("absence.predictor.selectedCount"),
                        viewModel.predictionDraftSelectedCount
                    )
                )
            }
        }
    }
}
