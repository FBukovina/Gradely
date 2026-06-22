import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif
#if canImport(StoreKit)
import StoreKit
#endif

struct SupportTipOption: Identifiable, Equatable {
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
}

extension SupportTipServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "support.tips.error.notConfigured")
        case .emptyOffering:
            String(localized: "support.tips.error.emptyOffering")
        case .productUnavailable:
            String(localized: "support.tips.error.productUnavailable")
        case .purchaseFailed(let message):
            message
        }
    }
}

protocol SupportTipProviding {
    @MainActor
    func loadTips() async throws -> [SupportTipOption]

    @MainActor
    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome
}

enum SupportTipCatalog {
    static let offeringIdentifier = "tips"

    static let products: [(packageIdentifier: String, productIdentifier: String)] = [
        ("tip_small", "com.bukovinafilip.BakalariMarks.tip.small"),
        ("tip_medium", "com.bukovinafilip.BakalariMarks.tip.medium"),
        ("tip_large", "com.bukovinafilip.BakalariMarks.tip.large"),
    ]
}

#if canImport(RevenueCat)
@MainActor
final class RevenueCatSupportTipService: SupportTipProviding {
    private var packagesByIdentifier: [String: Package] = [:]

    func loadTips() async throws -> [SupportTipOption] {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.offering(identifier: SupportTipCatalog.offeringIdentifier) ?? offerings.current else {
            throw SupportTipServiceError.emptyOffering
        }

        let packages = orderedTipPackages(from: offering)
        packagesByIdentifier = Dictionary(uniqueKeysWithValues: packages.map { ($0.identifier, $0) })

        return packages.map { package in
            SupportTipOption(
                id: package.identifier,
                productIdentifier: package.storeProduct.productIdentifier,
                title: package.storeProduct.localizedTitle,
                localizedPrice: package.localizedPriceString
            )
        }
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        guard Purchases.isConfigured else {
            throw SupportTipServiceError.notConfigured
        }

        var package = packagesByIdentifier[tip.id]
        if package == nil {
            _ = try await loadTips()
            package = packagesByIdentifier[tip.id]
        }

        guard let package else {
            throw SupportTipServiceError.productUnavailable
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            return result.userCancelled ? .cancelled : .success
        } catch {
            if let errorCode = (error as NSError).asErrorCode, errorCode == .purchaseCancelledError {
                return .cancelled
            }
            throw SupportTipServiceError.purchaseFailed(userFacingMessage(for: error))
        }
    }

    private func orderedTipPackages(from offering: Offering) -> [Package] {
        SupportTipCatalog.products.compactMap { product in
            offering.package(identifier: product.packageIdentifier)
                ?? offering.availablePackages.first {
                    $0.storeProduct.productIdentifier == product.productIdentifier
                }
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

#if canImport(StoreKit)
@MainActor
final class StoreKitSupportTipService: SupportTipProviding {
    private var productsByPackageIdentifier: [String: StoreKit.Product] = [:]

    func loadTips() async throws -> [SupportTipOption] {
        let productIdentifiers = SupportTipCatalog.products.map(\.productIdentifier)
        let storeProducts = try await StoreKit.Product.products(for: productIdentifiers)
        let productsByIdentifier = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
        let orderedProducts = SupportTipCatalog.products.compactMap { catalogProduct -> (packageIdentifier: String, product: StoreKit.Product)? in
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

        return orderedProducts.map { packageIdentifier, product in
            SupportTipOption(
                id: packageIdentifier,
                productIdentifier: product.id,
                title: product.displayName,
                localizedPrice: product.displayPrice
            )
        }
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        var product = productsByPackageIdentifier[tip.id]
        if product == nil {
            _ = try await loadTips()
            product = productsByPackageIdentifier[tip.id]
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
                throw SupportTipServiceError.purchaseFailed(String(localized: "support.tips.error.purchaseUnknown"))
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
    func loadTips() async throws -> [SupportTipOption] {
        throw SupportTipServiceError.notConfigured
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        throw SupportTipServiceError.notConfigured
    }
}

final class MockSupportTipService: SupportTipProviding {
    static let previewTips = [
        SupportTipOption(
            id: "tip_small",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.small",
            title: String(localized: "support.tips.tip.small"),
            localizedPrice: "29 CZK"
        ),
        SupportTipOption(
            id: "tip_medium",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.medium",
            title: String(localized: "support.tips.tip.medium"),
            localizedPrice: "79 CZK"
        ),
        SupportTipOption(
            id: "tip_large",
            productIdentifier: "com.bukovinafilip.BakalariMarks.tip.large",
            title: String(localized: "support.tips.tip.large"),
            localizedPrice: "149 CZK"
        ),
    ]

    var loadResult: Result<[SupportTipOption], Error>
    var purchaseResult: Result<SupportTipPurchaseOutcome, Error>
    private(set) var purchasedTipIDs: [String] = []

    init(
        tips: [SupportTipOption] = MockSupportTipService.previewTips,
        purchaseResult: Result<SupportTipPurchaseOutcome, Error> = .success(.success)
    ) {
        self.loadResult = .success(tips)
        self.purchaseResult = purchaseResult
    }

    init(
        loadResult: Result<[SupportTipOption], Error>,
        purchaseResult: Result<SupportTipPurchaseOutcome, Error> = .success(.success)
    ) {
        self.loadResult = loadResult
        self.purchaseResult = purchaseResult
    }

    func loadTips() async throws -> [SupportTipOption] {
        try loadResult.get()
    }

    func purchase(_ tip: SupportTipOption) async throws -> SupportTipPurchaseOutcome {
        purchasedTipIDs.append(tip.id)
        return try purchaseResult.get()
    }
}
