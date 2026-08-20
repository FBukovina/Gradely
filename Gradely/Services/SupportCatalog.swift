import Foundation

/// Recurring support tiers. This is not a Gradey Pro / premium product.
///
/// Firebase Functions must resolve RevenueCat entitlements for
/// `app_user_id` = Gradey account id (`gradey_account_id` on AI callables)
/// and apply `dailyLimit(for:)`:
/// - none / unsigned: 5 messages / day
/// - entitlement `support`: 10
/// - entitlement `support_plus`: 25 (`support_plus` implies `support`)
///
/// App Store Connect / RevenueCat checklist:
/// - One subscription group containing all four auto-renewable products
/// - Products: `support.standard.monthly` ($2), `support.standard.yearly` ($20),
///   `support.plus.monthly` ($4), `support.plus.yearly` ($40)
/// - Entitlements: `support` and `support_plus` (plus includes support)
/// - Offering identifier `support` with packages `support_standard_monthly`,
///   `support_standard_yearly`, `support_plus_monthly`, `support_plus_yearly`
/// - Keep the existing `tips` offering unchanged
enum SupportInterval: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case yearly

    var id: String { rawValue }
}

enum SupportTier: String, Comparable, Sendable {
    case none
    case standard
    case plus

    static let paidTiers: [SupportTier] = [.standard, .plus]

    var rank: Int {
        switch self {
        case .none: 0
        case .standard: 1
        case .plus: 2
        }
    }

    var hasEarlyAccess: Bool {
        self != .none
    }

    var canUpgrade: Bool {
        self != .plus
    }

    static func < (lhs: SupportTier, rhs: SupportTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct SupportPlanOption: Identifiable, Equatable, Sendable {
    let id: String
    let productIdentifier: String
    let tier: SupportTier
    let interval: SupportInterval
    let localizedPrice: String

    var title: String {
        switch tier {
        case .none:
            ""
        case .standard:
            AppL10n.string("support.plans.standard.title")
        case .plus:
            AppL10n.string("support.plans.plus.title")
        }
    }

    var benefitText: String {
        switch tier {
        case .none:
            ""
        case .standard:
            AppL10n.string("support.plans.standard.benefit")
        case .plus:
            AppL10n.string("support.plans.plus.benefit")
        }
    }

    var dailyLimit: Int {
        SupportTipCatalog.dailyLimit(for: tier)
    }
}

struct SupportEntitlement: Equatable, Sendable {
    var tier: SupportTier
    var interval: SupportInterval?
    var productIdentifier: String?
    var expirationDate: Date?
    var willRenew: Bool
    var managementURL: URL?

    static let none = SupportEntitlement(
        tier: .none,
        interval: nil,
        productIdentifier: nil,
        expirationDate: nil,
        willRenew: false,
        managementURL: nil
    )

    var hasEarlyAccess: Bool { tier.hasEarlyAccess }
}

struct SupportCatalog: Equatable, Sendable {
    var tips: [SupportTipOption]
    var plans: [SupportPlanOption]
    var entitlement: SupportEntitlement
    var managementURL: URL?

    static let empty = SupportCatalog(
        tips: [],
        plans: [],
        entitlement: .none,
        managementURL: nil
    )

    var isEmpty: Bool {
        tips.isEmpty && plans.isEmpty
    }

    func plans(for interval: SupportInterval) -> [SupportPlanOption] {
        SupportTier.paidTiers.compactMap { tier in
            plans.first { $0.tier == tier && $0.interval == interval }
        }
    }
}

enum SupportTipCatalog {
    static let tipsOfferingIdentifier = "tips"
    static let supportOfferingIdentifier = "support"
    static let standardEntitlementID = "support"
    static let plusEntitlementID = "support_plus"
    static let productIDPrefix = "com.bukovinafilip.BakalariMarks"

    static let managementURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    static let tipProducts: [(packageIdentifier: String, productIdentifier: String)] = [
        ("tip_small", "\(productIDPrefix).tip.small"),
        ("tip_medium", "\(productIDPrefix).tip.medium"),
        ("tip_large", "\(productIDPrefix).tip.large"),
    ]

    static let subscriptionProducts: [(
        packageIdentifier: String,
        productIdentifier: String,
        tier: SupportTier,
        interval: SupportInterval
    )] = [
        ("support_standard_monthly", "\(productIDPrefix).support.standard.monthly", .standard, .monthly),
        ("support_standard_yearly", "\(productIDPrefix).support.standard.yearly", .standard, .yearly),
        ("support_plus_monthly", "\(productIDPrefix).support.plus.monthly", .plus, .monthly),
        ("support_plus_yearly", "\(productIDPrefix).support.plus.yearly", .plus, .yearly),
    ]

    /// Default offering identifier kept for callers that still refer to tips.
    static let offeringIdentifier = tipsOfferingIdentifier

    static let products = tipProducts

    static let previewSubscriptionPlans: [SupportPlanOption] = [
        SupportPlanOption(
            id: "support_standard_monthly",
            productIdentifier: "\(productIDPrefix).support.standard.monthly",
            tier: .standard,
            interval: .monthly,
            localizedPrice: "$2.00"
        ),
        SupportPlanOption(
            id: "support_standard_yearly",
            productIdentifier: "\(productIDPrefix).support.standard.yearly",
            tier: .standard,
            interval: .yearly,
            localizedPrice: "$20.00"
        ),
        SupportPlanOption(
            id: "support_plus_monthly",
            productIdentifier: "\(productIDPrefix).support.plus.monthly",
            tier: .plus,
            interval: .monthly,
            localizedPrice: "$4.00"
        ),
        SupportPlanOption(
            id: "support_plus_yearly",
            productIdentifier: "\(productIDPrefix).support.plus.yearly",
            tier: .plus,
            interval: .yearly,
            localizedPrice: "$40.00"
        ),
    ]

    static func localizedTipTitle(forProductIdentifier identifier: String) -> String {
        switch identifier {
        case "\(productIDPrefix).tip.small":
            AppL10n.string("support.tips.tip.small")
        case "\(productIDPrefix).tip.medium":
            AppL10n.string("support.tips.tip.medium")
        case "\(productIDPrefix).tip.large":
            AppL10n.string("support.tips.tip.large")
        default:
            AppL10n.string("support.tips.tip.small")
        }
    }

    static func dailyLimit(for tier: SupportTier) -> Int {
        switch tier {
        case .none: 5
        case .standard: 10
        case .plus: 25
        }
    }

    static func subscription(
        forProductIdentifier productIdentifier: String
    ) -> (tier: SupportTier, interval: SupportInterval)? {
        subscriptionProducts.first { $0.productIdentifier == productIdentifier }
            .map { ($0.tier, $0.interval) }
    }

    static func subscription(
        forPackageIdentifier packageIdentifier: String
    ) -> (tier: SupportTier, interval: SupportInterval)? {
        subscriptionProducts.first { $0.packageIdentifier == packageIdentifier }
            .map { ($0.tier, $0.interval) }
    }

    static func entitlement(
        activeProductIdentifiers: [String],
        activeEntitlementIDs: Set<String> = [],
        expirationDate: Date? = nil,
        willRenew: Bool = false,
        managementURL: URL? = nil
    ) -> SupportEntitlement {
        let tierFromEntitlements: SupportTier
        if activeEntitlementIDs.contains(plusEntitlementID) {
            tierFromEntitlements = .plus
        } else if activeEntitlementIDs.contains(standardEntitlementID) {
            tierFromEntitlements = .standard
        } else {
            tierFromEntitlements = .none
        }

        let mappedProducts = activeProductIdentifiers.compactMap { identifier -> (String, SupportTier, SupportInterval)? in
            guard let mapped = subscription(forProductIdentifier: identifier) else { return nil }
            return (identifier, mapped.tier, mapped.interval)
        }
        let bestProduct = mappedProducts.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 == .monthly && rhs.2 == .yearly
        }

        let tier = max(tierFromEntitlements, bestProduct?.1 ?? .none)
        return SupportEntitlement(
            tier: tier,
            interval: bestProduct?.2,
            productIdentifier: bestProduct?.0,
            expirationDate: expirationDate,
            willRenew: willRenew,
            managementURL: managementURL
        )
    }
}
