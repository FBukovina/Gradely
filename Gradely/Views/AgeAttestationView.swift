import SwiftUI

struct AgeAttestationView: View {
    @Bindable var store: AgeAttestationStore
    @State private var pendingParentalKind: AgeAttestationKind?
    @State private var parentConfirmed = false

    var body: some View {
        Group {
            if pendingParentalKind != nil {
                parentalConfirmation
            } else {
                chooser
            }
        }
        .accessibilityIdentifier("ageAttestationView")
    }

    private var chooser: some View {
        OnboardingStepScaffold(
            icon: "person.crop.circle.badge.questionmark",
            title: "age.gate.title",
            message: "age.gate.body"
        ) {
            VStack(spacing: Spacing.md) {
                ageChoiceButton(
                    title: "age.gate.sixteen.title",
                    subtitle: "age.gate.sixteen.subtitle",
                    identifier: "ageAttestationSixteenButton"
                ) {
                    store.confirm(.sixteenOrOlder)
                }

                ageChoiceButton(
                    title: "age.gate.teen.title",
                    subtitle: "age.gate.teen.subtitle",
                    identifier: "ageAttestationTeenButton"
                ) {
                    beginParentalConfirmation(for: .thirteenToFifteenWithParent)
                }

                ageChoiceButton(
                    title: "age.gate.underThirteen.title",
                    subtitle: "age.gate.underThirteen.subtitle",
                    identifier: "ageAttestationUnderThirteenButton"
                ) {
                    beginParentalConfirmation(for: .underThirteen)
                }

                Link(destination: AppLinks.privacyPolicyURL) {
                    Text("age.gate.privacyLink")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("ageAttestationPrivacyLink")
            }
        }
    }

    private var parentalConfirmation: some View {
        OnboardingStepScaffold(
            icon: "checkmark.shield",
            title: pendingParentalKind == .underThirteen
                ? "age.gate.underThirteen.title"
                : "age.gate.teen.title",
            message: "age.gate.teen.confirm"
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Toggle(isOn: $parentConfirmed) {
                    Text("age.gate.teen.toggle")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("ageAttestationParentToggle")

                Button {
                    guard let pendingParentalKind else { return }
                    store.confirm(pendingParentalKind)
                } label: {
                    Text("age.gate.teen.continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!parentConfirmed)
                .accessibilityIdentifier("ageAttestationTeenContinue")

                Button("age.gate.blocked.change") {
                    pendingParentalKind = nil
                    parentConfirmed = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.primary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func beginParentalConfirmation(for kind: AgeAttestationKind) {
        pendingParentalKind = kind
        parentConfirmed = false
    }

    private func ageChoiceButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                GradelyIcon(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.gradelySecondaryGroupedBackground,
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
