import Foundation
#if os(iOS) && canImport(Intercom)
import Intercom
#endif

enum IntercomConfiguration {
    struct Credentials: Equatable, Sendable {
        var apiKey: String
        var appID: String
    }

    private(set) static var isConfigured = false

    static func credentials(from bundle: Bundle = .main) -> Credentials? {
        credentials(from: bundle.infoDictionary ?? [:])
    }

    static func credentials(from infoDictionary: [String: Any]) -> Credentials? {
        guard let apiKey = cleanedValue(infoDictionary["IntercomIOSAPIKey"]),
              let appID = cleanedValue(infoDictionary["IntercomAppID"])
        else {
            return nil
        }
        return Credentials(apiKey: apiKey, appID: appID)
    }

    static func configureIfNeeded(bundle: Bundle = .main) {
        #if os(iOS) && canImport(Intercom)
        if !isConfigured, let credentials = credentials(from: bundle) {
            Intercom.setApiKey(credentials.apiKey, forAppId: credentials.appID)
            isConfigured = true
            IntercomIdentity.loginUnidentified()
        }

        guard isConfigured else { return }
        Intercom.setLauncherVisible(false)
        Intercom.setThemeOverride(.dark)
        #endif
    }

    private static func cleanedValue(_ rawValue: Any?) -> String? {
        guard let rawValue = rawValue as? String else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
