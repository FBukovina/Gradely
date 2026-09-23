import SwiftUI

struct GradeSimulatorView: View {
    @Bindable var viewModel: SubjectDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .target

    private enum Mode: Hashable {
        case target
        case simulate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppL10n.string("detail.simulator.mode"), selection: $mode) {
                        Text(AppL10n.string("detail.simulator.target")).tag(Mode.target)
                        Text(AppL10n.string("detail.simulator.whatIf")).tag(Mode.simulate)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("gradeSimulatorMode")
                }

                baselineSection

                if !viewModel.preparedCalculation.canSimulate {
                    Section {
                        Text(AppL10n.string("detail.simulator.unavailable"))
                            .foregroundStyle(.secondary)
                    }
                } else if mode == .target {
                    targetSection
                    targetOptionsSection
                } else {
                    scenarioSection
                    simulationSection
                }
            }
            .navigationTitle(AppL10n.string("detail.simulator.title"))
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("detail.simulator.done")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("gradeSimulatorView")
    }

    private var baselineSection: some View {
        Section {
            if let official = viewModel.preparedCalculation.officialAverage {
                LabeledContent(AppL10n.string("detail.intelligence.schoolAverage")) {
                    Text(GradeMath.formattedAverage(official)).monospacedDigit()
                }
            }
            LabeledContent(AppL10n.string("detail.intelligence.calculatedAverage")) {
                Text(GradeMath.formattedAverage(viewModel.preparedCalculation.calculatedAverage))
                    .monospacedDigit()
            }
            if let key = viewModel.calculationWarningKey {
                Text(AppL10n.string(String.LocalizationValue(key)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(AppL10n.string("detail.intelligence.teacherDisclaimer"))
        }
    }

    private var targetSection: some View {
        Section {
            HStack {
                Text(AppL10n.string("detail.simulator.targetAverage"))
                Spacer()
                TextField("2.49", text: $viewModel.targetAverageText)
                    .multilineTextAlignment(.trailing)
                    .gradelyKeyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 95)
                    .accessibilityLabel(AppL10n.string("detail.simulator.targetAverage"))
                    .accessibilityIdentifier("gradeTargetAverageField")
            }
            Stepper(value: $viewModel.targetWeight, in: 1...10) {
                Text(String.localizedStringWithFormat(AppL10n.string("detail.weight"), viewModel.targetWeight))
            }
            .accessibilityIdentifier("gradeTargetWeightStepper")
        } header: {
            Text(AppL10n.string("detail.simulator.target"))
        } footer: {
            Text(AppL10n.string("detail.simulator.targetExplanation"))
        }
    }

    @ViewBuilder
    private var targetOptionsSection: some View {
        let result = viewModel.targetResult
        Section {
            switch result.status {
            case .options:
                ForEach(result.options) { option in
                    Button {
                        viewModel.applyTargetOption(option)
                        mode = .simulate
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String.localizedStringWithFormat(
                                    AppL10n.string("detail.simulator.option"), option.grade, option.count
                                ))
                                .font(.body.weight(.medium))
                                Text(String.localizedStringWithFormat(
                                    AppL10n.string("detail.simulator.result"), option.estimatedAverage
                                ))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            GradelyIcon(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("gradeTargetOption-\(option.id)")
                }
            case .alreadyReached:
                Text(AppL10n.string("detail.simulator.targetReached"))
            case .unreachable:
                Text(AppL10n.string("detail.simulator.unreachable"))
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text(AppL10n.string("detail.simulator.unavailable"))
                    .foregroundStyle(.secondary)
            case .invalidTarget:
                Text(AppL10n.string("detail.simulator.invalidTarget"))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(AppL10n.string("detail.simulator.options"))
        } footer: {
            Text(AppL10n.string(String.LocalizationValue(viewModel.calculationSourceKey)))
        }
        .accessibilityIdentifier("gradeTargetResults")
    }

    private var scenarioSection: some View {
        Section {
            ForEach(Array(viewModel.hypotheticalGrades.enumerated()), id: \.element.id) { index, grade in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String.localizedStringWithFormat(AppL10n.string("detail.simulator.gradeNumber"), index + 1))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeHypotheticalGrade(id: grade.id)
                        } label: {
                            GradelyIcon(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(AppL10n.string("detail.simulator.removeGrade"))
                    }
                    Picker(AppL10n.string("detail.simulator.grade"), selection: Binding(
                        get: { grade.value },
                        set: { viewModel.updateHypotheticalGrade(id: grade.id, value: $0) }
                    )) {
                        ForEach(1...5, id: \.self) { value in
                            Text(String(value)).tag(Double(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: Binding(
                        get: { grade.weight },
                        set: { viewModel.updateHypotheticalGrade(id: grade.id, weight: $0) }
                    ), in: 1...10) {
                        Text(String.localizedStringWithFormat(AppL10n.string("detail.weight"), grade.weight))
                    }
                }
                .accessibilityIdentifier("hypotheticalGrade-\(index)")
            }
            Button {
                viewModel.addHypotheticalGrade()
            } label: {
                GradelyLabel(AppL10n.string("detail.simulator.addGrade"), systemImage: "plus")
            }
            .disabled(viewModel.hypotheticalGrades.count >= GradeMath.maximumHypotheticalGrades)
            .accessibilityIdentifier("addHypotheticalGradeButton")
        } header: {
            Text(AppL10n.string("detail.simulator.hypotheticalGrades"))
        } footer: {
            Text(AppL10n.string("detail.simulator.localOnly"))
        }
    }

    @ViewBuilder
    private var simulationSection: some View {
        if !viewModel.hypotheticalGrades.isEmpty, let result = viewModel.simulationResult {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(GradeMath.formattedAverage(result.estimatedAverage))
                        .font(.largeTitle.bold().monospacedDigit())
                        .accessibilityIdentifier("multiGradeSimulationAverage")
                    if let difference = result.difference {
                        Text(String.localizedStringWithFormat(AppL10n.string("detail.simulator.difference"), difference))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(AppL10n.string("detail.intelligence.estimatedAverage"))
            } footer: {
                Text(AppL10n.string(String.LocalizationValue(viewModel.calculationSourceKey)))
            }
        }
    }
}
