import Foundation
import SwiftUI

/// One entry in the "what changed" breakdown shown by `PrivacyPolicyUpdateView`.
///
/// Copy lives in the strings catalog under `privacy.update.change.<id>.*` so the
/// Czech and chronically-online voices come from the same place as the rest of
/// the app.
struct PrivacyPolicyChange: Identifiable, Hashable, Sendable {
    /// Stable slug. Also forms the row's accessibility identifier and its
    /// localization keys, so it must not change once shipped.
    let id: String
    /// Raw Hugeicons Stroke Rounded glyph name, rendered through `GradelyIcon`.
    let iconName: String

    var titleKey: LocalizedStringKey { LocalizedStringKey(titleKeyString) }
    var summaryKey: LocalizedStringKey { LocalizedStringKey(summaryKeyString) }
    var detailKey: LocalizedStringKey { LocalizedStringKey(detailKeyString) }

    var titleKeyString: String { "privacy.update.change.\(id).title" }
    var summaryKeyString: String { "privacy.update.change.\(id).summary" }
    var detailKeyString: String { "privacy.update.change.\(id).detail" }
}

/// The privacy-policy revision the app currently ships, and the breakdown of
/// what changed since the previous one.
///
/// `current` is deliberately independent of `CFBundleShortVersionString`: a
/// release that does not touch the policy must not re-prompt. Bump it only when
/// the published policy materially changes, and refresh `changes` when you do.
enum PrivacyPolicyRevision {
    /// Revision 2 — the September 2026 rewrite that removed Bakaláři password
    /// upload and documented the Planner, Gradey AI and Apple Watch surfaces.
    static let current = 2

    // TODO: Confirm before release. `Docs/PrivacyPolicy.en.md` still carries
    // "Effective date: [insert publication date]", and the coordinated app and
    // Edge Function release has not shipped yet. This date must match the
    // published policy on help.bukovinafilip.com.
    static let effectiveDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_789_776_000)
    }()

    /// Ordered most-important first; the sheet renders them in this order.
    static let changes: [PrivacyPolicyChange] = [
        // Policy section 3.2
        PrivacyPolicyChange(id: "password", iconName: "security-lock"),
        // Policy section 7
        PrivacyPolicyChange(id: "cleanup", iconName: "delete-02"),
        // Policy section 3.2
        PrivacyPolicyChange(id: "tokens", iconName: "key-01"),
        // Policy section 3.10
        PrivacyPolicyChange(id: "planner", iconName: "calendar-03"),
        // Policy section 3.5
        PrivacyPolicyChange(id: "ai", iconName: "sparkles"),
        // Policy section 3.4
        PrivacyPolicyChange(id: "watch", iconName: "smart-watch-01"),
    ]

    /// Effective date in the in-app language, not the device language.
    static func formattedEffectiveDate(locale: Locale = AppLanguageOverride.locale) -> String {
        effectiveDate.formatted(
            Date.FormatStyle(date: .long, time: .omitted)
                .locale(locale)
        )
    }
}
