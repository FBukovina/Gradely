import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif
#if canImport(StoreKit)
import StoreKit
#endif

struct SupportTipOption: Identifiable, Equatable, Sendable {
    let id: String
    let productIdentifier: String
    let title: String
    let localizedPrice: String
}

enum SupportTipPurchaseOutcome: Equatable {
    case success
    case cancelled
    case pending
}

enum SupportTipServiceError: Error, Equatable {
    case notConfigured
    case emptyOffering
    case productUnavailable
    case purchaseFailed(String)
    case accountRequired
    case restoreFailed(String)
    case offerCodeRefreshFailed(String)
}

extension SupportTipServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            AppL10n.string("support.tips.error.notConfigured")
        case .emptyOffering:
            AppL10n.string("support.tips.error.emptyOffering")
        case .productUnavailable:
            AppL10n.string("support.tips.error.productUnavailable")
        case .purchaseFailed(let message),
             .restoreFailed(let message),
             .offerCodeRefreshFailed(let message):
            message
        case .accountRequired:
            AppL10n.string("support.plans.signIn.required")
        }
    }
}

protocol SupportTipProviding {
    @MainActor
    func loadCatalog() async throws -> SupportCatalog

    @MainActor
    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome

    @MainActor
    func purchase(_ plan: SupportPlanOption) async throws -> SupportTipPurchaseOutcome

    @MainActor
    func restorePurchases() async throws -> SupportEntitlement

    @MainActor
    func refreshPurchasesAfterOfferCodeRedemption() async throws -> SupportEntitlement

    @MainActor
    func currentEntitlement() async -> SupportEntitlement
}

enum SupportTipServiceFactory {
    @MainActor
    static func makeLive() -> any SupportTipProviding {
        #if canImport(RevenueCat)
        if Purchases.isConfigured {
            return RevenueCatSupportTipService()
        }
        #endif
        #if canImport(StoreKit)
        return StoreKitSupportTipService()
        #else
        return UnavailableSupportTipService()
        #endif
    }
}

#if canImport(StoreKit)
@MainActor
enum SupportStoreKitLoader {
    static func subscriptionPlans() async -> (
        plans: [SupportPlanOption],
        productsByIdentifier: [String: StoreKit.Product]
    ) {
        let identifiers = SupportTipCatalog.subscriptionProducts.map(\.productIdentifier)
        let storeProducts = (try? await StoreKit.Product.products(for: identifiers)) ?? []
        let productsByID = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
        var productsByPackage: [String: StoreKit.Product] = [:]
        let plans = SupportTipCatalog.subscriptionProducts.compactMap { catalogProduct -> SupportPlanOption? in
            guard let product = productsByID[catalogProduct.productIdentifier] else {
                return nil
            }
            productsByPackage[catalogProduct.packageIdentifier] = product
            return SupportPlanOption(
                id: catalogProduct.packageIdentifier,
                productIdentifier: product.id,
                tier: catalogProduct.tier,
                interval: catalogProduct.interval,
                localizedPrice: product.displayPrice
            )
        }
        return (plans, productsByPackage)
    }

    static func purchase(_ product: StoreKit.Product) async throws -> SupportTipPurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                throw SupportTipServiceError.purchaseFailed(AppL10n.string("support.tips.error.purchaseUnknown"))
            }
        } catch let error as SupportTipServiceError {
            throw error
        } catch {
            throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
        }
    }

    private static func verifiedTransaction(
        from result: StoreKit.VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
#endif

#if canImport(RevenueCat)
@MainActor
final class RevenueCatSupportTipService: SupportTipProviding {
    private var packagesByIdentifier: [String: Package] = [:]
    #if canImport(StoreKit)
    private var storeKitProductsByIdentifier: [String: StoreKit.Product] = [:]
    #endif

    func loadCatalog() async throws -> SupportCatalog {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        let offerings = try await Purchases.shared.offerings()
        let tipOffering = offerings.offering(identifier: SupportTipCatalog.tipsOfferingIdentifier)
            ?? offerings.current
        let supportOffering = offerings.offering(identifier: SupportTipCatalog.supportOfferingIdentifier)

        var packages: [Package] = []
        if let tipOffering {
            packages.append(contentsOf: orderedTipPackages(from: tipOffering))
        }
        if let supportOffering {
            packages.append(contentsOf: orderedSubscriptionPackages(from: supportOffering))
        }

        packagesByIdentifier = Dictionary(uniqueKeysWithValues: packages.map { ($0.identifier, $0) })

        let tips = orderedTipPackages(from: tipOffering).map { package in
            SupportTipOption(
                id: package.identifier,
                productIdentifier: package.storeProduct.productIdentifier,
                title: SupportTipCatalog.localizedTipTitle(
                    forProductIdentifier: package.storeProduct.productIdentifier
                ),
                localizedPrice: package.localizedPriceString
            )
        }
        var plans = orderedSubscriptionPackages(from: supportOffering).compactMap { package -> SupportPlanOption? in
            guard let mapped = SupportTipCatalog.subscription(forPackageIdentifier: package.identifier)
                    ?? SupportTipCatalog.subscription(forProductIdentifier: package.storeProduct.productIdentifier)
            else {
                return nil
            }
            return SupportPlanOption(
                id: package.identifier,
                productIdentifier: package.storeProduct.productIdentifier,
                tier: mapped.tier,
                interval: mapped.interval,
                localizedPrice: package.localizedPriceString
            )
        }
        #if canImport(StoreKit)
        if plans.isEmpty {
            let storeKitCatalog = await SupportStoreKitLoader.subscriptionPlans()
            plans = storeKitCatalog.plans
            storeKitProductsByIdentifier = storeKitCatalog.productsByIdentifier
        } else {
            storeKitProductsByIdentifier = [:]
        }
        #endif
        #if DEBUG
        if plans.isEmpty {
            plans = SupportTipCatalog.previewSubscriptionPlans
        }
        #endif

        guard !tips.isEmpty || !plans.isEmpty else {
            throw SupportTipServiceError.emptyOffering
        }

        let customerInfo = try await Purchases.shared.customerInfo()
        let entitlement = entitlement(from: customerInfo)
        return SupportCatalog(
            tips: tips,
            plans: plans,
            entitlement: entitlement,
            managementURL: customerInfo.managementURL ?? SupportTipCatalog.managementURL
        )
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        try await purchasePackage(id: tip.id)
    }

    func purchase(_ plan: SupportPlanOption) async throws -> SupportTipPurchaseOutcome {
        try await purchasePackage(id: plan.id)
    }

    func restorePurchases() async throws -> SupportEntitlement {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            return entitlement(from: customerInfo)
        } catch {
            if let errorCode = (error as NSError).asErrorCode, errorCode == .purchaseCancelledError {
                return await currentEntitlement()
            }
            throw SupportTipServiceError.restoreFailed(userFacingMessage(for: error))
        }
    }

    func refreshPurchasesAfterOfferCodeRedemption() async throws -> SupportEntitlement {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        do {
            let customerInfo = try await Purchases.shared.syncPurchases()
            return entitlement(from: customerInfo)
        } catch {
            throw SupportTipServiceError.offerCodeRefreshFailed(userFacingMessage(for: error))
        }
    }

    func currentEntitlement() async -> SupportEntitlement {
        guard Purchases.isConfigured else { return .none }
        if let customerInfo = try? await Purchases.shared.customerInfo() {
            return entitlement(from: customerInfo)
        }
        return entitlement(from: Purchases.shared.cachedCustomerInfo)
    }

    private func purchasePackage(id: String) async throws -> SupportTipPurchaseOutcome {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        var package = packagesByIdentifier[id]
        if package == nil {
            _ = try await loadCatalog()
            package = packagesByIdentifier[id]
        }

        if let package {
            do {
                let result = try await Purchases.shared.purchase(package: package)
                return result.userCancelled ? .cancelled : .success
            } catch {
                if let errorCode = (error as NSError).asErrorCode {
                    if errorCode == .purchaseCancelledError {
                        return .cancelled
                    }
                    if errorCode == .productAlreadyPurchasedError {
                        return .success
                    }
                }
                throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
            }
        }

        #if canImport(StoreKit)
        if let storeProduct = storeKitProductsByIdentifier[id] {
            return try await SupportStoreKitLoader.purchase(storeProduct)
        }
        #endif

        throw SupportTipServiceError.productUnavailable
    }

    private func orderedTipPackages(from offering: Offering?) -> [Package] {
        guard let offering else { return [] }
        return SupportTipCatalog.tipProducts.compactMap { product in
            offering.package(identifier: product.packageIdentifier)
                ?? offering.availablePackages.first {
                    $0.storeProduct.productIdentifier == product.productIdentifier
                }
        }
    }

    private func orderedSubscriptionPackages(from offering: Offering?) -> [Package] {
        guard let offering else { return [] }
        return SupportTipCatalog.subscriptionProducts.compactMap { product in
            offering.package(identifier: product.packageIdentifier)
                ?? offering.availablePackages.first {
                    $0.storeProduct.productIdentifier == product.productIdentifier
                }
        }
    }

    private func entitlement(from customerInfo: CustomerInfo?) -> SupportEntitlement {
        guard let customerInfo else { return .none }
        let activeEntitlements = customerInfo.entitlements.active
        let activeIDs = Set(activeEntitlements.keys)
        let productIDs = activeEntitlements.values.map(\.productIdentifier)
        let plusInfo = activeEntitlements[SupportTipCatalog.plusEntitlementID]
        let standardInfo = activeEntitlements[SupportTipCatalog.standardEntitlementID]
        let primary = plusInfo ?? standardInfo
        return SupportTipCatalog.entitlement(
            activeProductIdentifiers: productIDs,
            activeEntitlementIDs: activeIDs,
            expirationDate: primary?.expirationDate,
            willRenew: primary?.willRenew ?? false,
            managementURL: customerInfo.managementURL
        )
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
#endif

#if canImport(StoreKit)
@MainActor
final class StoreKitSupportTipService: SupportTipProviding {
    private var productsByPackageIdentifier: [String: StoreKit.Product] = [:]

    func loadCatalog() async throws -> SupportCatalog {
        let catalogProducts = SupportTipCatalog.tipProducts + SupportTipCatalog.subscriptionProducts.map {
            (packageIdentifier: $0.packageIdentifier, productIdentifier: $0.productIdentifier)
        }
        let productIdentifiers = catalogProducts.map(\.productIdentifier)
        let storeProducts = try await StoreKit.Product.products(for: productIdentifiers)
        let productsByIdentifier = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
        let orderedProducts = catalogProducts.compactMap { catalogProduct -> (packageIdentifier: String, product: StoreKit.Product)? in
            guard let product = productsByIdentifier[catalogProduct.productIdentifier] else {
                return nil
            }
            return (catalogProduct.packageIdentifier, product)
        }

        guard !orderedProducts.isEmpty else {
            throw SupportTipServiceError.emptyOffering
        }

        productsByPackageIdentifier = Dictionary(
            uniqueKeysWithValues: orderedProducts.map { ($0.packageIdentifier, $0.product) }
        )

        let tips = SupportTipCatalog.tipProducts.compactMap { catalogProduct -> SupportTipOption? in
            guard let product = productsByPackageIdentifier[catalogProduct.packageIdentifier] else {
                return nil
            }
            return SupportTipOption(
                id: catalogProduct.packageIdentifier,
                productIdentifier: product.id,
                title: SupportTipCatalog.localizedTipTitle(forProductIdentifier: product.id),
                localizedPrice: product.displayPrice
            )
        }
        var plans = SupportTipCatalog.subscriptionProducts.compactMap { catalogProduct -> SupportPlanOption? in
            guard let product = productsByPackageIdentifier[catalogProduct.packageIdentifier] else {
                return nil
            }
            return SupportPlanOption(
                id: catalogProduct.packageIdentifier,
                productIdentifier: product.id,
                tier: catalogProduct.tier,
                interval: catalogProduct.interval,
                localizedPrice: product.displayPrice
            )
        }
        #if DEBUG
        if plans.isEmpty {
            plans = SupportTipCatalog.previewSubscriptionPlans
        }
        #endif

        let entitlement = await currentEntitlement()
        return SupportCatalog(
            tips: tips,
            plans: plans,
            entitlement: entitlement,
            managementURL: SupportTipCatalog.managementURL
        )
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        try await purchaseProduct(id: tip.id)
    }

    func purchase(_ plan: SupportPlanOption) async throws -> SupportTipPurchaseOutcome {
        try await purchaseProduct(id: plan.id)
    }

    func restorePurchases() async throws -> SupportEntitlement {
        do {
            try await AppStore.sync()
            return await currentEntitlement()
        } catch {
            throw SupportTipServiceError.restoreFailed(userFacingMessage(for: error))
        }
    }

    func refreshPurchasesAfterOfferCodeRedemption() async throws -> SupportEntitlement {
        await currentEntitlement()
    }

    func currentEntitlement() async -> SupportEntitlement {
        var productIdentifiers: [String] = []
        var expirationDate: Date?
        var willRenew = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SupportTipCatalog.subscription(forProductIdentifier: transaction.productID) != nil else {
                continue
            }
            productIdentifiers.append(transaction.productID)
            if let transactionExpiration = transaction.expirationDate {
                if expirationDate == nil || transactionExpiration > expirationDate! {
                    expirationDate = transactionExpiration
                    willRenew = transaction.isUpgraded == false
                }
            }
        }

        return SupportTipCatalog.entitlement(
            activeProductIdentifiers: productIdentifiers,
            expirationDate: expirationDate,
            willRenew: willRenew,
            managementURL: SupportTipCatalog.managementURL
        )
    }

    private func purchaseProduct(id: String) async throws -> SupportTipPurchaseOutcome {
        var product = productsByPackageIdentifier[id]
        if product == nil {
            _ = try await loadCatalog()
            product = productsByPackageIdentifier[id]
        }

        guard let product else {
            throw SupportTipServiceError.productUnavailable
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                throw SupportTipServiceError.purchaseFailed(AppL10n.string("support.tips.error.purchaseUnknown"))
            }
        } catch let error as SupportTipServiceError {
            throw error
        } catch {
            throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
        }
    }

    private func verifiedTransaction(
        from result: StoreKit.VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
#endif

final class UnavailableSupportTipService: SupportTipProviding {
    func loadCatalog() async throws -> SupportCatalog {
        throw SupportTipServiceError.notConfigured
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        throw SupportTipServiceError.notConfigured
    }

    func purchase(_ plan: SupportPlanOption) async throws -> SupportTipPurchaseOutcome {
        throw SupportTipServiceError.notConfigured
    }

    func restorePurchases() async throws -> SupportEntitlement {
        throw SupportTipServiceError.notConfigured
    }

    func refreshPurchasesAfterOfferCodeRedemption() async throws -> SupportEntitlement {
        throw SupportTipServiceError.notConfigured
    }

    func currentEntitlement() async -> SupportEntitlement {
        .none
    }
}

final class MockSupportTipService: SupportTipProviding {
    static let previewTips = [
        SupportTipOption(
            id: "tip_small",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.small",
            title: AppL10n.string("support.tips.tip.small"),
            localizedPrice: "29 CZK"
        ),
        SupportTipOption(
            id: "tip_medium",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.medium",
            title: AppL10n.string("support.tips.tip.medium"),
            localizedPrice: "79 CZK"
        ),
        SupportTipOption(
            id: "tip_large",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.large",
            title: AppL10n.string("support.tips.tip.large"),
            localizedPrice: "149 CZK"
        ),
    ]

    static let previewPlans = [
        SupportPlanOption(
            id: "support_standard_monthly",
            productIdentifier: "com.bukovinafilip.BakalariMarks.support.standard.monthly",
            tier: .standard,
            interval: .monthly,
            localizedPrice: "$2.00"
        ),
        SupportPlanOption(
            id: "support_standard_yearly",
            productIdentifier: "com.bukovinafilip.BakalariMarks.support.standard.yearly",
            tier: .standard,
            interval: .yearly,
            localizedPrice: "$20.00"
        ),
        SupportPlanOption(
            id: "support_plus_monthly",
            productIdentifier: "com.bukovinafilip.BakalariMarks.support.plus.monthly",
            tier: .plus,
            interval: .monthly,
            localizedPrice: "$4.00"
        ),
        SupportPlanOption(
            id: "support_plus_yearly",
            productIdentifier: "com.bukovinafilip.BakalariMarks.support.plus.yearly",
            tier: .plus,
            interval: .yearly,
            localizedPrice: "$40.00"
        ),
    ]

    var loadResult: Result<SupportCatalog, Error>
    var purchaseResult: Result<SupportTipPurchaseOutcome, Error>
    var restoreResult: Result<SupportEntitlement, Error>
    var offerCodeRefreshResult: Result<SupportEntitlement, Error>?
    private(set) var purchasedTipIDs: [String] = []
    private(set) var purchasedPlanIDs: [String] = []
    private(set) var didRestorePurchases = false
    private(set) var didRefreshPurchasesAfterOfferCodeRedemption = false
    private var entitlement: SupportEntitlement

    init(
        tips: [SupportTipOption] = MockSupportTipService.previewTips,
        plans: [SupportPlanOption] = MockSupportTipService.previewPlans,
        entitlement: SupportEntitlement = .none,
        purchaseResult: Result<SupportTipPurchaseOutcome, Error> = .success(.success),
        offerCodeRefreshResult: Result<SupportEntitlement, Error>? = nil
    ) {
        self.loadResult = .success(
            SupportCatalog(
                tips: tips,
                plans: plans,
                entitlement: entitlement,
                managementURL: SupportTipCatalog.managementURL
            )
        )
        self.purchaseResult = purchaseResult
        self.restoreResult = .success(entitlement)
        self.offerCodeRefreshResult = offerCodeRefreshResult
        self.entitlement = entitlement
    }

    init(
        loadResult: Result<SupportCatalog, Error>,
        purchaseResult: Result<SupportTipPurchaseOutcome, Error> = .success(.success),
        restoreResult: Result<SupportEntitlement, Error> = .success(.none),
        offerCodeRefreshResult: Result<SupportEntitlement, Error>? = nil
    ) {
        self.loadResult = loadResult
        self.purchaseResult = purchaseResult
        self.restoreResult = restoreResult
        self.offerCodeRefreshResult = offerCodeRefreshResult
        self.entitlement = (try? loadResult.get())?.entitlement ?? .none
    }

    func loadCatalog() async throws -> SupportCatalog {
        var catalog = try loadResult.get()
        catalog.entitlement = entitlement
        return catalog
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        purchasedTipIDs.append(tip.id)
        return try purchaseResult.get()
    }

    func purchase(_ plan: SupportPlanOption) async throws -> SupportTipPurchaseOutcome {
        purchasedPlanIDs.append(plan.id)
        let outcome = try purchaseResult.get()
        if outcome == .success {
            entitlement = SupportEntitlement(
                tier: plan.tier,
                interval: plan.interval,
                productIdentifier: plan.productIdentifier,
                expirationDate: Date().addingTimeInterval(plan.interval == .yearly ? 31_536_000 : 2_592_000),
                willRenew: true,
                managementURL: SupportTipCatalog.managementURL
            )
        }
        return outcome
    }

    func restorePurchases() async throws -> SupportEntitlement {
        didRestorePurchases = true
        let restored = try restoreResult.get()
        entitlement = restored
        return restored
    }

    func refreshPurchasesAfterOfferCodeRedemption() async throws -> SupportEntitlement {
        didRefreshPurchasesAfterOfferCodeRedemption = true
        if let offerCodeRefreshResult {
            entitlement = try offerCodeRefreshResult.get()
        }
        return entitlement
    }

    func currentEntitlement() async -> SupportEntitlement {
        entitlement
    }
}
