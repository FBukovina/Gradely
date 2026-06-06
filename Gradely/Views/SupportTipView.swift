import SwiftUI

struct SupportTipView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SupportTipViewModel

    init(viewModel: SupportTipViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    content
                }
                .padding(Spacing.lg)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(String(localized: "support.tips.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "action.ok")) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Image(systemName: "heart.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("support.tips.heading")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("support.tips.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        Card {
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
        VStack(spacing: Spacing.md) {
            ForEach(viewModel.tips) { tip in
                SupportTipRow(
                    tip: tip,
                    isPurchasing: viewModel.purchasingTipID == tip.id,
                    isDisabled: viewModel.purchasingTipID != nil
                ) {
                    Task { await viewModel.purchase(tip) }
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
        .accessibilityIdentifier("supportTipsList")
    }

    private func unavailable(message: String, canRetry: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if canRetry {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Label(String(localized: "action.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("supportTipsRetryButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportTipsUnavailable")
    }

    private var thankYou: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Brand.primary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("support.tips.thankYou.title")
                        .font(.title3.weight(.bold))

                    Text("support.tips.thankYou.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    dismiss()
                } label: {
                    Text("action.ok")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("supportTipsDoneButton")
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
            Card(padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(tip.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(tip.localizedPrice)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                    }

                    Spacer(minLength: Spacing.md)

                    if isPurchasing {
                        ProgressView()
                            .tint(Brand.primary)
                            .accessibilityLabel(String(localized: "support.tips.purchase.progress"))
                    } else {
                        Image(systemName: "heart.circle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                    }
                }
            }
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
