import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    static func configureIfNeeded(bundle: Bundle = .main) {
        guard !Purchases.isConfigured,
              let apiKey = bundle.revenueCatIOSAPIKey
        else {
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey)
    }
}

private extension Bundle {
    var revenueCatIOSAPIKey: String? {
        guard let rawValue = object(forInfoDictionaryKey: "RevenueCatIOSAPIKey") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
