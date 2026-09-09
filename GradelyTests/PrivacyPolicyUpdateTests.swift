import Foundation
import Testing
@testable import Gradely

@Suite(.serialized)
struct PrivacyPolicyConsentStoreTests {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "gradey.tests.privacyPolicy.\(name)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test func aDeviceThatHasNeverAcceptedIsPrompted() {
        let defaults = makeDefaults()
        let store = PrivacyPolicyConsentStore(userDefaults: defaults)
        #expect(store.acceptedVersion == nil)
        #expect(store.acceptedAt == nil)
        #expect(store.needsAcknowledgement)
    }

    @Test func acceptingRecordsTheRevisionAndATimestamp() {
        let defaults = makeDefaults()
        let store = PrivacyPolicyConsentStore(userDefaults: defaults)
        let moment = Date(timeIntervalSince1970: 1_789_000_000)

        store.accept(at: moment)

        #expect(store.acceptedVersion == PrivacyPolicyRevision.current)
        #expect(!store.needsAcknowledgement)
        // Persisted to the second, so compare at that resolution.
        #expect(abs((store.acceptedAt ?? .distantPast).timeIntervalSince(moment)) < 1)

        // A fresh store reading the same defaults sees the acceptance.
        let reloaded = PrivacyPolicyConsentStore(userDefaults: defaults)
        #expect(reloaded.acceptedVersion == PrivacyPolicyRevision.current)
        #expect(!reloaded.needsAcknowledgement)
    }

    @Test func acceptingTwiceIsIdempotent() {
        let defaults = makeDefaults()
        let store = PrivacyPolicyConsentStore(userDefaults: defaults)

        store.accept()
        store.accept()

        #expect(store.acceptedVersion == PrivacyPolicyRevision.current)
        #expect(!store.needsAcknowledgement)
    }

    @Test func anOlderAcceptedRevisionIsPromptedAgain() {
        let defaults = makeDefaults()
        defaults.set(PrivacyPolicyRevision.current - 1, forKey: PrivacyPolicyConsentStore.versionKey)

        let store = PrivacyPolicyConsentStore(userDefaults: defaults)
        #expect(store.needsAcknowledgement)

        store.accept()
        #expect(!store.needsAcknowledgement)
    }

    @Test func clearingRestoresThePrompt() {
        let defaults = makeDefaults()
        let store = PrivacyPolicyConsentStore(userDefaults: defaults)
        store.accept()

        store.clear()

        #expect(store.acceptedVersion == nil)
        #expect(store.acceptedAt == nil)
        #expect(store.needsAcknowledgement)
        #expect(defaults.object(forKey: PrivacyPolicyConsentStore.versionKey) == nil)
    }
}

struct PrivacyPolicyReadProgressTests {
    @Test func contentThatFitsCountsAsRead() {
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 400, containerHeight: 800, offset: 0) == 1)
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 800, containerHeight: 800, offset: 0) == 1)
    }

    @Test func fractionTracksScrollPositionAndClamps() {
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 1800, containerHeight: 800, offset: 0) == 0)
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 1800, containerHeight: 800, offset: 500) == 0.5)
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 1800, containerHeight: 800, offset: 1000) == 1)
        // Rubber-banding must not push the bar past the ends.
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 1800, containerHeight: 800, offset: -60) == 0)
        #expect(PrivacyPolicyReadProgress.fraction(contentHeight: 1800, containerHeight: 800, offset: 1400) == 1)
    }

    @Test func reachingTheEndLatchesSoScrollingBackDoesNotRelock() {
        var progress = PrivacyPolicyReadProgress()
        #expect(!progress.isSatisfied(voiceOverEnabled: false))

        progress.update(fraction: 0.5)
        #expect(!progress.isSatisfied(voiceOverEnabled: false))

        progress.update(fraction: 0.99)
        #expect(progress.isSatisfied(voiceOverEnabled: false))

        progress.update(fraction: 0.1)
        #expect(progress.isSatisfied(voiceOverEnabled: false))
        #expect(progress.fraction == 0.1)
    }

    @Test func voiceOverUnlocksWithoutScrolling() {
        let progress = PrivacyPolicyReadProgress()
        #expect(!progress.isSatisfied(voiceOverEnabled: false))
        #expect(progress.isSatisfied(voiceOverEnabled: true))
    }
}

struct PrivacyPolicyRevisionTests {
    @Test func changeIdentifiersAreUniqueAndStable() {
        let ids = PrivacyPolicyRevision.changes.map(\.id)
        #expect(ids == ["password", "cleanup", "tokens", "planner", "ai", "watch"])
        #expect(Set(ids).count == ids.count)
    }

    /// Every row's copy must exist in all four shipped voices. This is what
    /// catches a key that was added to the view but not to the catalog.
    @Test func everyChangeIsLocalizedInAllShippedLanguages() throws {
        let keys = PrivacyPolicyRevision.changes.flatMap {
            [$0.titleKeyString, $0.summaryKeyString, $0.detailKeyString]
        } + [
            "privacy.update.title",
            "privacy.update.subtitle",
            "privacy.update.effective",
            "privacy.update.changes.title",
            "privacy.update.row.hint",
            "privacy.update.scrollHint",
            "privacy.update.progress",
            "privacy.update.accept",
            "privacy.update.fullPolicy",
            "privacy.update.footer",
            "privacy.update.settingsRow.title",
            "privacy.update.settingsRow.caption",
        ]

        for code in ["en", "cs", "en-CO", "cs-US"] {
            let bundle = try #require(
                Bundle.gradelyLprojBundle(for: code),
                "missing \(code).lproj — check the strings catalog localizations"
            )
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "\u{0}missing", table: nil)
                #expect(value != "\u{0}missing", "\(key) is not localized for \(code)")
                #expect(!value.isEmpty, "\(key) is empty for \(code)")
            }
        }
    }

    @Test func effectiveDateRendersInTheInAppLanguage() {
        let english = PrivacyPolicyRevision.formattedEffectiveDate(locale: Locale(identifier: "en_US"))
        let czech = PrivacyPolicyRevision.formattedEffectiveDate(locale: Locale(identifier: "cs_CZ"))
        #expect(english.contains("2026"))
        #expect(czech.contains("2026"))
        #expect(english != czech)
    }
}
