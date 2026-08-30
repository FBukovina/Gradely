import Foundation
import Observation
#if canImport(StoreKit)
import StoreKit
#endif

enum SupportTipLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

enum SupportPurchaseKind: Equatable {
    case tip
    case plan
}

@MainActor
@Observable
final class SupportTipViewModel {
    var loadState: SupportTipLoadState = .idle
    var tips: [SupportTipOption] = []
    var plans: [SupportPlanOption] = []
    var entitlement: SupportEntitlement = .none
    var selectedInterval: SupportInterval = .monthly
    var purchasingTipID: String?
    var purchasingPlanID: String?
    var isRestoring = false
    var isRefreshingOfferCode = false
    var purchaseErrorMessage: String?
    var didCompletePurchase = false
    var completedPurchaseKind: SupportPurchaseKind?
    var isSignedIn: Bool
    var onEntitlementChanged: (() -> Void)?

    var visiblePlans: [SupportPlanOption] {
        plans.filter { $0.interval == selectedInterval }
            .sorted { $0.tier.rank < $1.tier.rank }
    }

    var isPurchasing: Bool {
        purchasingTipID != nil || purchasingPlanID != nil || isRestoring || isRefreshingOfferCode
    }

    var canRedeemOfferCode: Bool {
        isSignedIn && !isPurchasing
    }

    var managementURL: URL {
        entitlement.managementURL ?? SupportTipCatalog.managementURL
    }

    var thankYouMessage: String {
        switch completedPurchaseKind {
        case .plan:
            AppL10n.string("support.plans.thankYou.message")
        case .tip, nil:
            AppL10n.string("support.tips.thankYou.message")
        }
    }

    private let supportTipProvider: any SupportTipProviding
    private var hasLoaded = false

    init(
        supportTipProvider: any SupportTipProviding,
        isSignedIn: Bool = true,
        onEntitlementChanged: (() -> Void)? = nil
    ) {
        self.supportTipProvider = supportTipProvider
        self.isSignedIn = isSignedIn
        self.onEntitlementChanged = onEntitlementChanged
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        hasLoaded = true
        loadState = .loading
        purchaseErrorMessage = nil
        didCompletePurchase = false
        completedPurchaseKind = nil

        do {
            apply(try await supportTipProvider.loadCatalog())
            loadState = tips.isEmpty && plans.isEmpty ? .empty : .loaded
        } catch {
            tips = []
            plans = []
            entitlement = .none
            loadState = .failed(userFacingMessage(for: error))
        }
    }

    func refreshEntitlement() async {
        let updated = await supportTipProvider.currentEntitlement()
        if updated != entitlement {
            entitlement = updated
            onEntitlementChanged?()
        }
    }

    func purchase(_ tip: SupportTipOption) async {
        guard purchasingTipID == nil, purchasingPlanID == nil else { return }

        purchasingTipID = tip.id
        purchaseErrorMessage = nil
        defer { purchasingTipID = nil }

        do {
            let outcome = try await supportTipProvider.purchase(tip)
            if outcome == .success {
                completedPurchaseKind = .tip
                didCompletePurchase = true
            } else if outcome == .pending {
                purchaseErrorMessage = AppL10n.string("support.tips.purchase.pending")
            }
        } catch {
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func purchase(_ plan: SupportPlanOption) async {
        guard purchasingTipID == nil, purchasingPlanID == nil else { return }
        guard isSignedIn else {
            purchaseErrorMessage = AppL10n.string("support.plans.signIn.required")
            return
        }
        guard canPurchase(plan) else { return }

        purchasingPlanID = plan.id
        purchaseErrorMessage = nil
        defer { purchasingPlanID = nil }

        do {
            let outcome = try await supportTipProvider.purchase(plan)
            if outcome == .success {
                apply(try await supportTipProvider.loadCatalog())
                completedPurchaseKind = .plan
                didCompletePurchase = true
                onEntitlementChanged?()
            } else if outcome == .pending {
                purchaseErrorMessage = AppL10n.string("support.tips.purchase.pending")
            }
        } catch {
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func restorePurchases() async {
        guard !isPurchasing else { return }
        isRestoring = true
        purchaseErrorMessage = nil
        defer { isRestoring = false }

        do {
            entitlement = try await supportTipProvider.restorePurchases()
            apply(try await supportTipProvider.loadCatalog())
            if entitlement.tier != .none {
                completedPurchaseKind = .plan
                didCompletePurchase = true
            }
            onEntitlementChanged?()
        } catch {
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func completeOfferCodeRedemption(with result: Result<Void, Error>) async {
        switch result {
        case .success:
            await refreshPurchasesAfterOfferCodeRedemption()
        case .failure(let error):
            guard !isUserCancellation(error) else { return }
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func refreshPurchasesAfterOfferCodeRedemption() async {
        guard canRedeemOfferCode else { return }

        isRefreshingOfferCode = true
        purchaseErrorMessage = nil
        defer { isRefreshingOfferCode = false }

        do {
            let previousEntitlement = entitlement
            entitlement = try await supportTipProvider.refreshPurchasesAfterOfferCodeRedemption()
            if entitlement != previousEntitlement {
                onEntitlementChanged?()
            }
        } catch {
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func canPurchase(_ plan: SupportPlanOption) -> Bool {
        guard isSignedIn else { return false }
        if entitlement.tier > plan.tier { return false }
        if entitlement.tier == plan.tier, entitlement.interval == plan.interval {
            return false
        }
        return true
    }

    func isCurrentPlan(_ plan: SupportPlanOption) -> Bool {
        entitlement.tier == plan.tier && entitlement.interval == plan.interval
    }

    func dismissThankYou() {
        didCompletePurchase = false
        completedPurchaseKind = nil
    }

    private func apply(_ catalog: SupportCatalog) {
        tips = catalog.tips
        plans = catalog.plans
        entitlement = catalog.entitlement
        if entitlement.interval == .yearly {
            selectedInterval = .yearly
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        #if canImport(StoreKit)
        if let storeKitError = error as? StoreKitError,
           case .userCancelled = storeKitError {
            return true
        }
        #endif
        return false
    }
}
