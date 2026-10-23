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
    /// Revision 3 adds friends' timetables, TŠ Vavruška dance classes and
    /// school homework. Revision 2 (effective 15 September 2026) removed
    /// Bakaláři password upload and documented the Planner, Gradey AI and
    /// Apple Watch.
    static let current = 3

    // Revision 3 is drafted in `Docs/PrivacyPolicy.en.md` and
    // `Docs/PrivacyPolicy-revision3.cs.md` but not published yet. Publish both
    // on help.bukovinafilip.com, set `effectiveDate` to the date they show,
    // then delete this block.
    #if !DEBUG
    #error("Publish privacy policy revision 3 and set PrivacyPolicyRevision.effectiveDate to its date")
    #endif

    static let effectiveDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 26
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_792_969_200)
    }()

    /// Ordered most-important first; the sheet renders them in this order.
    static let changes: [PrivacyPolicyChange] = [
        // Policy section 3.11
        PrivacyPolicyChange(id: "friends", iconName: "user-group"),
        // Policy section 3.12
        PrivacyPolicyChange(id: "dance", iconName: "music-note-01"),
        // Policy section 3.3
        PrivacyPolicyChange(id: "homework", iconName: "book-open-01"),
    ]

    /// Effective date in the in-app language, not the device language.
    static func formattedEffectiveDate(locale: Locale = AppLanguageOverride.locale) -> String {
        effectiveDate.formatted(
            Date.FormatStyle(date: .long, time: .omitted)
                .locale(locale)
        )
    }
}
