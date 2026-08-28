import Foundation
#if os(macOS)
import AppKit
#endif

enum AppLinks {
    static let githubRepositoryURL = URL(string: "https://github.com/FBukovina/Gradely")!
    static let timetableURL = NextLessonWidgetConstants.timetableDeepLink
    static let opensideWebURL = URL(string: "https://openside.tech")!
    static let filipInstagramURL = URL(string: "https://www.instagram.com/bukovinafilip")!
    static let filipEmailURL = URL(string: "mailto:filip@openside.tech")!
    static let tomasEmailURL = URL(string: "mailto:tom@openside.tech")!
    static let manageSubscriptionsURL = SupportTipCatalog.managementURL

    /// Apple's Licensed Application EULA. Guideline 3.1.2 requires a functional
    /// Terms of Use link in App Store metadata; when using the standard EULA,
    /// this URL must appear in the App Description.
    static let standardAppleEULAURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    /// Custom help-center domain. Articles currently live on Gleap and will move
    /// to Intercom on the same host.
    static let helpCenterHost = "help.bukovinafilip.com"

    static var helpCenterURL: URL {
        helpURL(path: nil)
    }

    static var privacyPolicyURL: URL {
        helpURL(path: "articles/10-privacy-policy")
    }

    static var termsOfUseURL: URL {
        helpURL(path: "articles/11-terms-and-conditions")
    }

    /// Copy this block into the App Store Connect description for each platform
    /// that sells auto-renewable subscriptions (macOS has its own description).
    static func appStoreDescriptionLegalFooter(languageCode: String = "en") -> String {
        let isCzech = helpLanguage(languageCode) == "cs"
        let termsLabel = isCzech ? "Podmínky používání (EULA)" : "Terms of Use (EULA)"
        let gradeyTermsLabel = isCzech ? "Podmínky používání Gradey" : "Gradey Terms of Use"
        let privacyLabel = isCzech ? "Zásady ochrany osobních údajů" : "Privacy Policy"
        let privacy = helpURL(path: "articles/10-privacy-policy", languageCode: languageCode)
        let terms = helpURL(path: "articles/11-terms-and-conditions", languageCode: languageCode)
        return """
        \(termsLabel): \(standardAppleEULAURL.absoluteString)
        \(gradeyTermsLabel): \(terms.absoluteString)
        \(privacyLabel): \(privacy.absoluteString)
        """
    }

    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    static func helpURL(
        path: String?,
        languageCode: String? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = helpCenterHost
        let language = helpLanguage(languageCode)
        if let path, !path.isEmpty {
            components.path = "/\(language)/\(path)"
        } else {
            components.path = "/\(language)"
        }
        return components.url ?? URL(string: "https://\(helpCenterHost)/\(language)")!
    }

    static func helpLanguage(_ languageCode: String? = nil) -> String {
        let code = languageCode
            ?? AppLanguageOverride.locale.language.languageCode?.identifier
            ?? Locale.current.language.languageCode?.identifier
        return code == "cs" ? "cs" : "en"
    }
}
