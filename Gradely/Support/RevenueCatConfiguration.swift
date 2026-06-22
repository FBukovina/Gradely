import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

enum RevenueCatConfiguration {
    private static let publicAppleAPIKey = "appl_KTNbCvFOqwPTWfQKhjDCgSdSANH"

    static func configureIfNeeded(bundle: Bundle = .main) {
        #if canImport(RevenueCat)
        guard !Purchases.isConfigured,
              let apiKey = bundle.revenueCatPlatformAPIKey ?? publicAppleAPIKey.nonEmptyAPIKey
        else {
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey)
        #endif
    }
}

private extension Bundle {
    var revenueCatPlatformAPIKey: String? {
        #if os(macOS)
        revenueCatAPIKey(forInfoDictionaryKey: "RevenueCatMacOSAPIKey")
            ?? revenueCatAPIKey(forInfoDictionaryKey: "RevenueCatIOSAPIKey")
        #else
        revenueCatAPIKey(forInfoDictionaryKey: "RevenueCatIOSAPIKey")
        #endif
    }

    func revenueCatAPIKey(forInfoDictionaryKey key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}

private extension String {
    var nonEmptyAPIKey: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
