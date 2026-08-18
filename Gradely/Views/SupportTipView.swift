import SwiftUI

struct SupportTipView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SupportTipViewModel

    init(viewModel: SupportTipViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SettingsModalBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        SettingsModalHeader(
                            title: "support.tips.title",
                            onDismiss: dismiss.callAsFunction
                        )

                        header
                        SupportTipOptionsContent(
                            viewModel: viewModel,
                            onThankYouDone: dismiss.callAsFunction
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("supportTipsScreen")
            }
            .settingsModalNavigationChrome()
        }
    }

    private var header: some View {
        SettingsModalSurface {
            HStack(alignment: .top, spacing: Spacing.md) {
                SettingsModalIcon(name: "favourite")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("support.tips.heading")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("support.tips.message")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportTipsHeader")
    }
}

/// Shared tip states used by Settings and returning-user onboarding.
struct SupportTipOptionsContent: View {
    @Bindable var viewModel: SupportTipViewModel
    var onThankYouDone: (() -> Void)?

    var body: some View {
        content
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.didCompletePurchase {
            thankYou
        } else {
            switch viewModel.loadState {
            case .idle, .loading:
                loading
            case .loaded:
                tipsList
            case .empty:
                unavailable(message: String(localized: "support.tips.empty"), canRetry: true)
            case .failed(let message):
                unavailable(message: message, canRetry: true)
            }
        }
    }

    private var loading: some View {
        SettingsModalSurface {
            HStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(Brand.primary)
                Text("support.tips.loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportTipsLoading")
    }

    private var tipsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.tips.enumerated()), id: \.element.id) { index, tip in
                        SupportTipRow(
                            tip: tip,
                            isPurchasing: viewModel.purchasingTipID == tip.id,
                            isDisabled: viewModel.purchasingTipID != nil
                        ) {
                            Task { await viewModel.purchase(tip) }
                        }

                        if index < viewModel.tips.count - 1 {
                            SettingsModalRowDivider()
                        }
                    }
                }
            }

            if let purchaseErrorMessage = viewModel.purchaseErrorMessage {
                Text(purchaseErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(GradeBand.poor.foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("supportTipsPurchaseError")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supportTipsList")
    }

    private func unavailable(message: String, canRetry: Bool) -> some View {
        SettingsModalSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    SettingsModalIcon(
                        name: "alert-circle",
                        color: .secondary,
                        size: 15
                    )

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canRetry {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            GradelyIcon("refresh-04", size: 15)
                            Text("action.retry")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("supportTipsRetryButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportTipsUnavailable")
    }

    private var thankYou: some View {
        SettingsModalSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    SettingsModalIcon(name: "checkmark-badge-02")

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("support.tips.thankYou.title")
                            .font(.headline)

                        Text("support.tips.thankYou.message")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let onThankYouDone {
                    Button(action: onThankYouDone) {
                        Text("action.ok")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("supportTipsDoneButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportTipsThankYou")
    }
}

private struct SupportTipRow: View {
    let tip: SupportTipOption
    let isPurchasing: Bool
    let isDisabled: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: Spacing.md) {
                SettingsModalIcon(name: "favourite")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(tip.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(tip.localizedPrice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPurchasing {
                    ProgressView()
                        .tint(Brand.primary)
                        .accessibilityLabel(String(localized: "support.tips.purchase.progress"))
                } else {
                    SettingsModalDisclosureIcon()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tip.title), \(tip.localizedPrice)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("supportTip-\(tip.id)")
    }
}

#Preview {
    SupportTipView(
        viewModel: SupportTipViewModel(
            supportTipProvider: MockSupportTipService()
        )
    )
}
