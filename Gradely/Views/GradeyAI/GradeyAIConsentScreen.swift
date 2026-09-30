import SwiftUI

/// First-run disclosure (EU AI Act transparency + data processing) with a
/// pinned consent action so it stays reachable at every text size.
struct GradeyAIConsentScreen: View {
    let viewModel: GradeyAIViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                hero

                if viewModel.status?.enabled == false {
                    GradeyAIBanner(
                        kind: .paused,
                        title: AppL10n.string("gradey.ai.availability.paused.title"),
                        message: AppL10n.string("gradey.ai.availability.paused.message")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("gradeyAIServiceUnavailableBanner")
                }

                disclosures

                Text("gradey.ai.disclaimer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xs)
            }
            .padding(.horizontal, 20)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("gradeyAIConsentView")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            consentAction
        }
    }

    private var hero: some View {
        VStack(spacing: Spacing.md) {
            GradeyAIOrb(size: 64)
                .padding(.bottom, Spacing.xs)

            Text("gradey.ai.consent.title")
                .font(.gradelyDisplay(size: 32, relativeTo: .title))
                .foregroundStyle(Brand.gradient)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("gradey.ai.consent.subtitle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
    }

    private var disclosures: some View {
        VStack(spacing: 0) {
            disclosureRow(
                icon: "sparkles",
                title: "gradey.ai.consent.system.title",
                message: "gradey.ai.consent.system.message"
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gradeyAIAIActDisclosure")

            rowDivider
            disclosureRow(
                icon: "chart.bar.doc.horizontal",
                title: "gradey.ai.consent.schoolData.title",
                message: "gradey.ai.consent.selectedContext"
            )

            rowDivider
            disclosureRow(
                icon: "cloud.fill",
                title: "gradey.ai.consent.processors.title",
                message: "gradey.ai.consent.processors.message"
            )

            rowDivider
            disclosureRow(
                icon: "clock.arrow.circlepath",
                title: "gradey.ai.consent.retention.title",
                message: "gradey.ai.consent.selectedRetention"
            )
        }
        .gradeyAIGlass(cornerRadius: 26, tint: 0.06)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 18 + 36 + Spacing.md)
    }

    private func disclosureRow(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(systemName: icon, size: 17)
                .foregroundStyle(Brand.gradient)
                .frame(width: 36, height: 36)
                .background(Brand.primary.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var consentAction: some View {
        Button {
            Task { await viewModel.acceptConsent() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Brand.onAccent)
                }
                Text("gradey.ai.consent.action")
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier("gradeyAIConsentButton")
        .padding(.horizontal, 20)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background { GradeyAIBottomFade() }
    }
}

/// Centered orb with a status line, used while loading or opening a chat.
struct GradeyAIProgressState: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.lg) {
            GradeyAIOrb(size: 64, isActive: true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Load failure with a retry action.
struct GradeyAIUnavailableState: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GradeyAIOrb(size: 64, icon: GradelyIconCatalog.hugeiconName(for: "exclamationmark.triangle.fill"))

                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(.gradelyDisplay(size: 26, relativeTo: .title2))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onRetry) {
                    GradelyLabel(AppL10n.string("action.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 280)
                .accessibilityIdentifier("gradeyAIRetryLoadButton")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.xxl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .accessibilityIdentifier("gradeyAIUnavailable")
    }
}
