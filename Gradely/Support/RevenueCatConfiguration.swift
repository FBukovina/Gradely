import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    private static let publicIOSAPIKey = "appl_KTNbCvFOqwPTWfQKhjDCgSdSANH"

    static func configureIfNeeded(bundle: Bundle = .main) {
        guard !Purchases.isConfigured,
              let apiKey = bundle.revenueCatIOSAPIKey ?? publicIOSAPIKey.nonEmptyAPIKey
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

private extension String {
    var nonEmptyAPIKey: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
