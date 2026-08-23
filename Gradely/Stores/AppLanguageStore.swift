import Foundation
import Observation
import ObjectiveC
import os

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case english
    case englishChronicallyOnline
    case czech
    case czechChronicallyOnline

    static let chronicallyOnlineTableName = "LocalizableCO"

    var id: String { rawValue }

    var isChronicallyOnline: Bool {
        switch self {
        case .englishChronicallyOnline, .czechChronicallyOnline:
            true
        case .system, .english, .czech:
            false
        }
    }

    /// `nil` follows the device language. Otherwise a `.lproj` code.
    var localizationCode: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .englishChronicallyOnline:
            "en-CO"
        case .czech:
            "cs"
        case .czechChronicallyOnline:
            "cs-US"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .englishChronicallyOnline:
            Locale(identifier: "en_CO")
        case .czech:
            Locale(identifier: "cs_CZ")
        case .czechChronicallyOnline:
            Locale(identifier: "cs_US")
        }
    }

    /// Identity labels stay in their own voice so they remain recognizable
    /// after the rest of the UI switches language.
    var displayName: String {
        pickerLanguage == .czech ? "Čeština" : "English"
    }

    static let pickerLanguages: [AppLanguage] = [.english, .czech]

    var pickerLanguage: AppLanguage {
        switch self {
        case .system:
            .resolvedFromDevice()
        case .english, .englishChronicallyOnline:
            .english
        case .czech, .czechChronicallyOnline:
            .czech
        }
    }

    func withChronicallyOnline(_ enabled: Bool) -> AppLanguage {
        switch (pickerLanguage, enabled) {
        case (.english, false):
            .english
        case (.english, true):
            .englishChronicallyOnline
        case (.czech, false):
            .czech
        case (.czech, true):
            .czechChronicallyOnline
        case (.system, _), (.englishChronicallyOnline, _), (.czechChronicallyOnline, _):
            self
        }
    }

    static func resolvedFromDevice() -> AppLanguage {
        Locale.autoupdatingCurrent.language.languageCode?.identifier == "cs" ? .czech : .english
    }
}

struct AppLanguageRuntimeState: Sendable, Equatable {
    var localizationCode: String?
    var isChronicallyOnline: Bool

    static let system = AppLanguageRuntimeState(localizationCode: nil, isChronicallyOnline: false)

    init(localizationCode: String?, isChronicallyOnline: Bool) {
        self.localizationCode = localizationCode
        self.isChronicallyOnline = isChronicallyOnline
    }

    init(_ language: AppLanguage) {
        localizationCode = language.localizationCode
        isChronicallyOnline = language.isChronicallyOnline
    }
}

enum ChronicallyOnlineText {
    static let missingSentinel = "\u{E000}gradely.missing\u{E001}"

    private static let preservedTokens = [
        "Gradey ID",
        "Gradey AI",
        "Strava.cz",
        "Apple ID",
        "Gradely",
        "Gradey",
        "Bakaláři",
        "Bakalari",
        "EduPage",
        "GitHub",
        "iCloud",
        "Keychain",
        "RevenueCat",
        "Supabase",
        "Firebase Functions",
        "Firebase",
        "Microsoft Azure AI",
        "Azure AI",
        "Microsoft",
        "Azure",
        "CAPTCHA",
        "HTTPS",
        "JSON",
        "API",
        "URL"
    ].sorted { $0.count > $1.count }

    private static let formatRegex: NSRegularExpression = {
        let pattern = "%(?:\\d+\\$)?[-+0 #]*(?:\\d+)?(?:\\.\\d+)?(?:ll|l|h)?[@diouxXeEfFgGcs%]"
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func transform(_ string: String) -> String {
        guard !string.isEmpty else { return string }

        var working = string
        var tokens: [(placeholder: String, original: String)] = []

        func protectRange(_ range: Range<String.Index>, original: String) {
            let placeholder = "\u{E000}\(tokens.count)\u{E001}"
            tokens.append((placeholder, original))
            working.replaceSubrange(range, with: placeholder)
        }

        let formatMatches = formatRegex.matches(
            in: working,
            range: NSRange(working.startIndex..., in: working)
        )
        for match in formatMatches.reversed() {
            guard let range = Range(match.range, in: working) else { continue }
            protectRange(range, original: String(working[range]))
        }

        for brand in preservedTokens {
            let regex = try! NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: brand),
                options: [.caseInsensitive]
            )
            let matches = regex.matches(
                in: working,
                range: NSRange(working.startIndex..., in: working)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: working) else { continue }
                protectRange(range, original: brand)
            }
        }

        working = working.lowercased()
        for token in tokens.reversed() {
            working = working.replacingOccurrences(of: token.placeholder, with: token.original)
        }
        return working
    }

    static func resolve(
        key: String,
        value: String?,
        table tableName: String?,
        in bundle: Bundle,
        lookup: (Bundle, String, String?, String?) -> String
    ) -> String {
        let coValue = lookup(bundle, key, missingSentinel, AppLanguage.chronicallyOnlineTableName)
        if coValue != missingSentinel {
            return coValue
        }

        let standardTable = tableName == AppLanguage.chronicallyOnlineTableName ? "Localizable" : tableName
        return transform(lookup(bundle, key, value, standardTable))
    }
}

@Observable
@MainActor
final class AppLanguageStore {
    static let shared = AppLanguageStore()
    static let storageKey = "settings.appLanguage"

    private let userDefaults: UserDefaults

    var selection: AppLanguage {
        didSet {
            guard oldValue != selection else { return }
            userDefaults.set(selection.rawValue, forKey: Self.storageKey)
            Self.apply(selection)
        }
    }

    var locale: Locale { selection.locale }

    var isChronicallyOnline: Bool {
        get { selection.isChronicallyOnline }
        set { selection = selection.withChronicallyOnline(newValue) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            selection = stored == .system ? .resolvedFromDevice() : stored
        } else {
            selection = .resolvedFromDevice()
        }
    }

    func selectPickerLanguage(_ language: AppLanguage) {
        selection = language.withChronicallyOnline(isChronicallyOnline)
    }

    func prepareAtLaunch() {
        Bundle.enableGradelyLanguageOverride()
        Self.apply(selection)
    }

    nonisolated static func apply(_ language: AppLanguage) {
        AppLanguageOverride.state.withLock { $0 = AppLanguageRuntimeState(language) }
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .englishChronicallyOnline:
            UserDefaults.standard.set(["en-CO", "en"], forKey: "AppleLanguages")
        case .czech:
            UserDefaults.standard.set(["cs"], forKey: "AppleLanguages")
        case .czechChronicallyOnline:
            UserDefaults.standard.set(["cs-US", "cs"], forKey: "AppleLanguages")
        }
    }
}

enum AppLanguageOverride {
    static let state = OSAllocatedUnfairLock(initialState: AppLanguageRuntimeState.system)

    static var locale: Locale {
        let config = state.withLock { $0 }
        guard let code = config.localizationCode else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: code.replacingOccurrences(of: "-", with: "_"))
    }
}

enum AppL10n {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: AppLanguageOverride.locale))
    }
}

extension Bundle {
    private static let recursionKey = "gradely.language.lookup"

    static func enableGradelyLanguageOverride() {
        enum Token {
            static let didEnable: Void = {
                let original = #selector(Bundle.localizedString(forKey:value:table:))
                let swizzled = #selector(Bundle.gradely_localizedString(forKey:value:table:))
                guard
                    let originalMethod = class_getInstanceMethod(Bundle.self, original),
                    let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzled)
                else {
                    return
                }
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }()
        }
        _ = Token.didEnable
    }

    @objc func gradely_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if Thread.current.threadDictionary[Self.recursionKey] as? Bool == true {
            return gradely_localizedString(forKey: key, value: value, table: tableName)
        }

        let config = AppLanguageOverride.state.withLock { $0 }
        let shouldOverrideTable = tableName == nil
            || tableName == "Localizable"
            || tableName == AppLanguage.chronicallyOnlineTableName
        guard shouldOverrideTable, isGradelyLocalizationBundle else {
            return gradely_localizedString(forKey: key, value: value, table: tableName)
        }

        Thread.current.threadDictionary[Self.recursionKey] = true
        defer { Thread.current.threadDictionary[Self.recursionKey] = false }

        let lookup: (Bundle, String, String?, String?) -> String = { bundle, key, value, table in
            bundle.gradely_localizedString(forKey: key, value: value, table: table)
        }

        if let code = config.localizationCode,
           let preferred = Bundle.gradelyLprojBundle(for: code) {
            return lookup(preferred, key, value, tableName)
        }

        if config.isChronicallyOnline {
            return ChronicallyOnlineText.resolve(
                key: key,
                value: value,
                table: tableName,
                in: self === Bundle.main ? self : Bundle.main,
                lookup: lookup
            )
        }

        return lookup(self, key, value, tableName)
    }

    private var isGradelyLocalizationBundle: Bool {
        self === Bundle.main || bundleURL.pathExtension == "lproj"
    }

    static func gradelyLprojBundle(for code: String) -> Bundle? {
        let candidates = [
            code,
            code.replacingOccurrences(of: "-", with: "_"),
            code.replacingOccurrences(of: "_", with: "-")
        ]
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }
}
