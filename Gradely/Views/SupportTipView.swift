import SwiftUI
import StoreKit

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isOfferCodeRedemptionPresented = false

    var body: some View {
        content
            .offerCodeRedemption(
                isPresented: $isOfferCodeRedemptionPresented
            ) { result in
                Task {
                    await viewModel.completeOfferCodeRedemption(with: result)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await viewModel.refreshEntitlement() }
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
                catalog
            case .empty:
                unavailable(message: AppL10n.string("support.tips.empty"), canRetry: true)
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

    private var catalog: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if !viewModel.plans.isEmpty {
                plansSection
            }

            if !viewModel.tips.isEmpty {
                tipsSection
            }

            restoreRow
            legalFooter

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

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: "support.plans.section")

            if viewModel.entitlement.tier != .none {
                activePlanCard
            }

            if !viewModel.isSignedIn {
                signInRequiredCard
            }

            SettingsModalSurface {
                Picker(selection: $viewModel.selectedInterval) {
                    Text("support.plans.interval.monthly")
                        .tag(SupportInterval.monthly)
                    Text("support.plans.interval.yearly")
                        .tag(SupportInterval.yearly)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("supportPlanIntervalPicker")

                if viewModel.selectedInterval == .yearly {
                    Text("support.plans.yearlySavings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsModalSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.visiblePlans.enumerated()), id: \.element.id) { index, plan in
                        SupportPlanRow(
                            plan: plan,
                            isCurrent: viewModel.isCurrentPlan(plan),
                            isPurchasing: viewModel.purchasingPlanID == plan.id,
                            isDisabled: viewModel.isPurchasing || !viewModel.canPurchase(plan)
                        ) {
                            Task { await viewModel.purchase(plan) }
                        }

                        if index < viewModel.visiblePlans.count - 1 {
                            SettingsModalRowDivider()
                        }
                    }
                }
            }
            .accessibilityIdentifier("supportPlansList")

            if viewModel.isSignedIn {
                offerCodeRow
            }
        }
    }

    private var offerCodeRow: some View {
        SettingsModalSurface(padding: 0) {
            Button {
                isOfferCodeRedemptionPresented = true
            } label: {
                HStack(spacing: Spacing.md) {
                    SettingsModalIcon(name: "favourite")

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("support.plans.offerCode.title")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("support.plans.offerCode.message")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.isRefreshingOfferCode {
                        ProgressView()
                            .tint(Brand.primary)
                            .accessibilityLabel(AppL10n.string("support.plans.offerCode.refresh.progress"))
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
            .disabled(!viewModel.canRedeemOfferCode)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("supportOfferCodeRedeemButton")
        }
    }

    private var activePlanCard: some View {
        SettingsModalSurface {
            HStack(alignment: .top, spacing: Spacing.md) {
                SettingsModalIcon(name: "checkmark-badge-02")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(activePlanTitle)
                            .font(.headline)
                        Text("support.plans.earlyAccess")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Brand.primary.opacity(0.12), in: Capsule())
                            .accessibilityIdentifier("supportEarlyAccessBadge")
                    }

                    Text(activePlanDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openURL(viewModel.managementURL)
                    } label: {
                        Text("support.plans.manage")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("supportManageSubscriptionButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("supportActivePlan")
    }

    private var signInRequiredCard: some View {
        SettingsModalSurface {
            HStack(alignment: .top, spacing: Spacing.md) {
                SettingsModalIcon(name: "alert-circle", color: .secondary, size: 15)
                Text("support.plans.signIn.required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("supportSignInRequired")
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: "support.tips.section")

            SettingsModalSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.tips.enumerated()), id: \.element.id) { index, tip in
                        SupportTipRow(
                            tip: tip,
                            isPurchasing: viewModel.purchasingTipID == tip.id,
                            isDisabled: viewModel.isPurchasing
                        ) {
                            Task { await viewModel.purchase(tip) }
                        }

                        if index < viewModel.tips.count - 1 {
                            SettingsModalRowDivider()
                        }
                    }
                }
            }
        }
    }

    private var restoreRow: some View {
        Button {
            Task { await viewModel.restorePurchases() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if viewModel.isRestoring {
                    ProgressView()
                        .tint(Brand.primary)
                        .accessibilityLabel(AppL10n.string("support.plans.restore.progress"))
                } else {
                    GradelyIcon("refresh-04", size: 15)
                }
                Text("support.plans.restore")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.isPurchasing)
        .accessibilityIdentifier("supportRestorePurchasesButton")
    }

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !viewModel.plans.isEmpty {
                Text("support.plans.legal.renewal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("supportLegalRenewalCopy")
            }

            HStack(spacing: Spacing.md) {
                AppLegalTextLink(
                    title: "legal.privacyPolicy",
                    url: AppLinks.privacyPolicyURL,
                    accessibilityIdentifier: "supportLegalPrivacyLink"
                )

                Text("·")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                AppLegalTextLink(
                    title: "legal.termsOfUse",
                    url: AppLinks.termsOfUseURL,
                    accessibilityIdentifier: "supportLegalTermsLink"
                )
            }
            .foregroundStyle(Brand.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("supportLegalFooter")
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

                        Text(viewModel.thankYouMessage)
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

    private var activePlanTitle: String {
        switch viewModel.entitlement.tier {
        case .plus:
            AppL10n.string("support.plans.plus.title")
        case .standard:
            AppL10n.string("support.plans.standard.title")
        case .none:
            ""
        }
    }

    private var activePlanDetail: String {
        if let expirationDate = viewModel.entitlement.expirationDate, viewModel.entitlement.willRenew {
            return String.localizedStringWithFormat(
                AppL10n.string("support.plans.renews"),
                expirationDate.formatted(date: .abbreviated, time: .omitted)
            )
        }
        return AppL10n.string("support.plans.active")
    }
}

private struct SupportPlanRow: View {
    let plan: SupportPlanOption
    let isCurrent: Bool
    let isPurchasing: Bool
    let isDisabled: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: Spacing.md) {
                SettingsModalIcon(name: plan.tier == .plus ? "sparkles" : "favourite")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(plan.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.benefitText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.xs) {
                        Text(plan.localizedPrice)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                        Text("support.plans.earlyAccess")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPurchasing {
                    ProgressView()
                        .tint(Brand.primary)
                        .accessibilityLabel(AppL10n.string("support.tips.purchase.progress"))
                } else if isCurrent {
                    Text("support.plans.current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.primary)
                } else {
                    SettingsModalDisclosureIcon()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("supportPlan-\(plan.tier.rawValue)")
    }

    private var accessibilityLabel: String {
        var parts = [plan.title, plan.localizedPrice, plan.benefitText]
        if isCurrent {
            parts.append(AppL10n.string("support.plans.current"))
        }
        return parts.joined(separator: ", ")
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
                        .accessibilityLabel(AppL10n.string("support.tips.purchase.progress"))
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

/// Opens legal URLs with `openURL` so the paywall links stay tappable on macOS
/// sheets, where SwiftUI `Link` plus custom styling can stop working.
private struct AppLegalTextLink: View {
    let title: LocalizedStringKey
    let url: URL
    let accessibilityIdentifier: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(url.absoluteString)
        .accessibilityAddTraits(.isLink)
    }
}

#Preview {
    SupportTipView(
        viewModel: SupportTipViewModel(
            supportTipProvider: MockSupportTipService()
        )
    )
}
