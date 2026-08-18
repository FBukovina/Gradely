import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

enum RevenueCatIdentity {
    static var appUserID: String? {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return nil }
        return Purchases.shared.appUserID
        #else
        return nil
        #endif
    }

    static var originalAppUserID: String? {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return nil }
        return Purchases.shared.cachedCustomerInfo?.originalAppUserId
        #else
        return nil
        #endif
    }

    static func identify(userID: String) async {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return }
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await Purchases.shared.logIn(trimmed)
        #endif
    }

    static func reset() async {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.logOut()
        #endif
    }
}
