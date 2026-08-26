import Foundation

enum AppLinks {
    static let githubRepositoryURL = URL(string: "https://github.com/FBukovina/Gradely")!
    static let timetableURL = NextLessonWidgetConstants.timetableDeepLink
    static let opensideWebURL = URL(string: "https://openside.tech")!
    static let filipInstagramURL = URL(string: "https://www.instagram.com/bukovinafilip")!
    static let filipEmailURL = URL(string: "mailto:filip@openside.tech")!
    static let tomasEmailURL = URL(string: "mailto:tom@openside.tech")!
    static let manageSubscriptionsURL = SupportTipCatalog.managementURL

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
