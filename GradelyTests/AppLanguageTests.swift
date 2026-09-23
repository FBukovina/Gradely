import Foundation
import Testing
import os
@testable import Gradely

struct ChronicallyOnlineTextTests {
    @Test func lowercasesCopyWhileKeepingBrandNames() {
        #expect(ChronicallyOnlineText.transform("Welcome to Gradey") == "welcome to Gradey")
        #expect(ChronicallyOnlineText.transform("Apple ID connected") == "Apple ID connected")
        #expect(ChronicallyOnlineText.transform("Sign in to Strava.cz") == "sign in to Strava.cz")
        #expect(ChronicallyOnlineText.transform("Ask Gradey AI about marks") == "ask Gradey AI about marks")
        #expect(ChronicallyOnlineText.transform("Daily AI replies use Compute") == "daily AI replies use Compute")
        #expect(ChronicallyOnlineText.transform("Microsoft Azure OpenAI and Google Firebase") == "Microsoft Azure OpenAI and Google Firebase")
        #expect(ChronicallyOnlineText.transform("Computed averages and email") == "computed averages and email")
    }

    @Test func preservesFormatSpecifiers() {
        #expect(ChronicallyOnlineText.transform("Error %d") == "error %d")
        #expect(ChronicallyOnlineText.transform("Selected %lld of %lld lessons") == "selected %lld of %lld lessons")
        #expect(ChronicallyOnlineText.transform("Average %.2f") == "average %.2f")
        #expect(ChronicallyOnlineText.transform("%1$@ · %2$@") == "%1$@ · %2$@")
        #expect(ChronicallyOnlineText.transform("Selected %#@SubjectCount@") == "selected %#@SubjectCount@")
    }

    @Test func leavesEmptyStringsAlone() {
        #expect(ChronicallyOnlineText.transform("") == "")
    }
}

@MainActor
struct AppLanguageStoreTests {
    @Test func mapsLocalesAndTables() {
        #expect(AppLanguage.system.localizationCode == nil)
        #expect(!AppLanguage.system.isChronicallyOnline)

        #expect(AppLanguage.english.localizationCode == "en")
        #expect(!AppLanguage.english.isChronicallyOnline)
        #expect(AppLanguage.englishChronicallyOnline.localizationCode == "en-CO")
        #expect(AppLanguage.englishChronicallyOnline.isChronicallyOnline)
        #expect(AppLanguage.englishChronicallyOnline.displayName == "English")
        #expect(AppLanguage.englishChronicallyOnline.pickerLanguage == .english)

        #expect(AppLanguage.czech.localizationCode == "cs")
        #expect(AppLanguage.czechChronicallyOnline.localizationCode == "cs-US")
        #expect(AppLanguage.czechChronicallyOnline.isChronicallyOnline)
        #expect(AppLanguage.czechChronicallyOnline.displayName == "Čeština")
        #expect(AppLanguage.czechChronicallyOnline.pickerLanguage == .czech)
    }

    @Test func keepsChronicallyOnlineWhenSwitchingPickerLanguage() {
        #expect(AppLanguage.englishChronicallyOnline.withChronicallyOnline(false) == .english)
        #expect(AppLanguage.czech.withChronicallyOnline(true) == .czechChronicallyOnline)
        #expect(AppLanguage.englishChronicallyOnline.withChronicallyOnline(true).pickerLanguage == .english)
        #expect(AppLanguage.czechChronicallyOnline.withChronicallyOnline(false) == .czech)
    }

    @Test func persistsSelection() throws {
        let suiteName = "AppLanguageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            AppLanguageStore.apply(.system)
        }

        let store = AppLanguageStore(userDefaults: defaults)
        #expect(store.selection == AppLanguage.resolvedFromDevice())

        store.selection = .czechChronicallyOnline
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == AppLanguage.czechChronicallyOnline.rawValue)
        #expect(store.isChronicallyOnline)

        store.selectPickerLanguage(.english)
        #expect(store.selection == .englishChronicallyOnline)

        let restored = AppLanguageStore(userDefaults: defaults)
        #expect(restored.selection == .englishChronicallyOnline)
        AppLanguageStore.apply(.system)
    }
}


@MainActor
struct BundledLanguageFallbackTests {
    @Test func allGradey22KeysResolveInBothChronicallyOnlineModes() throws {
        for language in [AppLanguage.englishChronicallyOnline, .czechChronicallyOnline] {
            try withLanguage(language) {
                let code = language.pickerLanguage.localizationCode!
                let base = try #require(Bundle.gradelyLprojBundle(for: code))
                for key in Self.intelligenceKeys {
                    let standard = base.gradely_localizedString(forKey: key, value: ChronicallyOnlineText.missingSentinel, table: nil)
                    #expect(standard != ChronicallyOnlineText.missingSentinel, "Missing base translation: \(code)/\(key)")
                    let bundled = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                    let resource = AppL10n.string(String.LocalizationValue(key))
                    #expect(bundled != key && bundled != ChronicallyOnlineText.missingSentinel && !bundled.isEmpty)
                    // Authored dialect wording can differ from the base copy;
                    // native SwiftUI and Bundle lookup must still agree.
                    #expect(resource == bundled, "Native/Bundle mismatch: \(language)/\(key): \(resource)")
                    #expect(resource != key && !resource.isEmpty)
                }
            }
        }
    }

    @Test func everyBundledSymbolicKeyResolvesThroughNativeLocalizationInAllFourModes() throws {
        for language in [AppLanguage.english, .englishChronicallyOnline, .czech, .czechChronicallyOnline] {
            try withLanguage(language) {
                let base = try #require(Bundle.gradelyLprojBundle(for: language.pickerLanguage.localizationCode!))
                var keys = Set<String>()
                for fileExtension in ["strings", "stringsdict"] {
                    guard let url = base.url(forResource: "Localizable", withExtension: fileExtension) else { continue }
                    let data = try Data(contentsOf: url)
                    let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    let values = try #require(propertyList as? [String: Any])
                    keys.formUnion(values.keys.filter { key in
                        key.range(of: #"^[A-Za-z0-9_]+(?:[._][A-Za-z0-9_]+)+$"#, options: .regularExpression) != nil
                    })
                }
                #expect(keys.count > 800, "Expected the real compiled app catalog, not an empty fixture")
                for key in keys.sorted() {
                    let value = AppL10n.string(String.LocalizationValue(key))
                    #expect(value != key && !value.isEmpty, "Native localization missing: \(language)/\(key)")
                    #expect(value == Bundle.main.localizedString(forKey: key, value: nil, table: nil),
                        "Native and authored Bundle copy differ: \(language)/\(key)")
                }
            }
        }
    }

    @Test func actualNewKeysKeepStandardLanguageCapitalization() {
        withLanguage(.english) {
            #expect(AppL10n.string("today.attention.title") == "Worth your attention")
            #expect(AppL10n.string("gradey.ai.action.study_priorities") == "Study priorities")
        }
        withLanguage(.czech) {
            #expect(AppL10n.string("today.attention.title") == "Stojí za pozornost")
            #expect(AppL10n.string("gradey.ai.action.study_priorities") == "Na co se zaměřit")
        }
    }

    @Test func authoredChronicallyOnlineCopyStillTakesPrecedence() {
        withLanguage(.englishChronicallyOnline) {
            #expect(AppL10n.string("action.retry") == "try again")
            #expect(Bundle.main.localizedString(forKey: "action.retry", value: nil, table: AppLanguage.chronicallyOnlineTableName) == "try again")
        }
        withLanguage(.czechChronicallyOnline) {
            #expect(AppL10n.string("action.retry") == "zkus to znovu")
            #expect(Bundle.main.localizedString(forKey: "action.retry", value: nil, table: AppLanguage.chronicallyOnlineTableName) == "zkus to znovu")
        }
    }

    @Test func newComputeFormatPreservesBothIntegerArguments() {
        withLanguage(.englishChronicallyOnline) {
            let format = AppL10n.string("gradey.ai.compute.remaining")
            #expect(format == "%lld of %lld Compute remaining")
            #expect(String.localizedStringWithFormat(format, Int64(2), Int64(5)) == "2 of 5 Compute remaining")
        }
        withLanguage(.czechChronicallyOnline) {
            let format = AppL10n.string("gradey.ai.compute.remaining")
            #expect(format == "zbývá %lld z %lld Compute")
            #expect(String.localizedStringWithFormat(format, Int64(2), Int64(5)) == "zbývá 2 z 5 Compute")
        }
    }

    @Test func authoredAndBaseFallbackPluralResourcesStillChooseTheCorrectForms() throws {
        for language in [AppLanguage.englishChronicallyOnline, .czechChronicallyOnline] {
            try withLanguage(language) {
                let base = try #require(Bundle.gradelyLprojBundle(for: language.pickerLanguage.localizationCode!))
                let authored = AppL10n.string("marks.hero.subjectCount")
                // Exercise the real base-language stringsdict fallback directly,
                // including when a future key has no authored dialect resource.
                let fallback = ChronicallyOnlineText.resolve(key: "marks.hero.subjectCount", value: nil, table: nil, in: base) { bundle, key, value, table in
                    bundle.gradely_localizedString(forKey: key, value: value, table: table)
                }
                let expected = language.pickerLanguage == .english
                    ? ["1 subject", "2 subjects", "5 subjects"] : ["1 předmět", "2 předměty", "5 předmětů"]
                for (count, value) in zip([1, 2, 5], expected) {
                    #expect(String(format: authored, locale: language.locale, arguments: [count]) == value)
                    #expect(String(format: fallback, locale: language.locale, arguments: [count]) == value)
                }
            }
        }
    }

    @Test func missingKeysKeepTheirCallerProvidedFallback() {
        withLanguage(.englishChronicallyOnline) {
            #expect(Bundle.main.localizedString(forKey: "language.tests.missing", value: "Fallback for Gradey AI %d", table: nil) == "fallback for Gradey AI %d")
        }
        withLanguage(.czechChronicallyOnline) {
            #expect(Bundle.main.localizedString(forKey: "language.tests.missing", value: "Náhradní text %d", table: nil) == "náhradní text %d")
        }
    }

    @Test func aiRequestsCaptureTheSelectedAppLanguageAndKeepItWhenLanguageChanges() {
        let context = GradeyAIContextBuilder.emptyContext(schoolScope: "localization-test", now: Date(timeIntervalSince1970: 0))
        func request() -> GradeyAIReplyRequest {
            GradeyAIReplyRequest(conversationID: "chat", clientMessageID: "message", text: "Help me study", context: context,
                actionID: .reply, contextSelectionID: "general", catalogVersion: "v1", maximumComputeCost: 1)
        }
        for language in [AppLanguage.english, .czech, .englishChronicallyOnline, .czechChronicallyOnline] {
            withLanguage(language) {
                let captured = request()
                let originalHash = captured.payloadHash
                let expectedLocale = language.localizationCode!.replacingOccurrences(of: "-", with: "_")
                #expect(captured.locale == expectedLocale)
                let other: AppLanguage = language.pickerLanguage == .english ? .czech : .english
                withLanguage(other) {
                    #expect(captured.locale == expectedLocale)
                    #expect(captured.payloadHash == originalHash)
                    #expect(request().payloadHash != originalHash)
                }
            }
        }
    }

    @Test func aiServerFailuresAndContextSectionsUseTheAppLanguageWithoutExposingDiagnostics() throws {
        let codes = ["quota_exceeded", "catalog_changed", "price_changed", "request_pending", "cancelled", "timeout",
            "content-filter", "provider-rate-limit", "provider-error", "accounting_blocked", "idempotency_conflict",
            "firebase_1", "firebase_4", "firebase_5", "firebase_8", "firebase_14", "firebase_16", "unknown-new-server-code"]
        for language in [AppLanguage.english, .czech, .englishChronicallyOnline, .czechChronicallyOnline] {
            try withLanguage(language) {
                for code in codes {
                    let error = GradeyAIError.server(code: code, message: "English-only backend diagnostic", retryable: false)
                    let localized = try #require(error.errorDescription)
                    #expect(!localized.isEmpty && !localized.hasPrefix("gradey.") && !localized.contains("backend diagnostic"))
                    #expect(!error.isRetryable)
                }
                #expect(GradeyAIError.server(code: "quota_exceeded", message: "", retryable: true).errorDescription?.contains("Compute") == true)
                let expected = language.pickerLanguage == .czech ? "známky" : "marks"
                #expect(GradeyAIContextSection.marks.localizedName == expected)
                if language.pickerLanguage == .czech {
                    #expect(GradeyAIError.server(code: "timeout", message: "", retryable: true).errorDescription?.lowercased().contains("odpověď") == true)
                    #expect(GradeyAIContextSection.events.localizedName.contains("události"))
                }
            }
        }
    }

    private func withLanguage(_ language: AppLanguage, body: () throws -> Void) rethrows {
        Bundle.enableGradelyLanguageOverride()
        let previous = AppLanguageOverride.state.withLock { state in
            let previous = state
            state = AppLanguageRuntimeState(language)
            return previous
        }
        defer { AppLanguageOverride.state.withLock { $0 = previous } }
        try body()
    }

    // All 107 keys introduced by the Gradey 2.2 implementation commit. This list
    // is compiled into tests; tests inspect the built app bundle, not source files.
    private static let intelligenceKeys = [
        "action.open",
        "detail.intelligence.assumedWeights",
        "detail.intelligence.averageMismatch",
        "detail.intelligence.calculatedAverage",
        "detail.intelligence.contributionExplanation",
        "detail.intelligence.estimatedAverage",
        "detail.intelligence.improving",
        "detail.intelligence.inferredWeights",
        "detail.intelligence.insights",
        "detail.intelligence.insufficientHistory",
        "detail.intelligence.modifierEstimate",
        "detail.intelligence.observedTrend",
        "detail.intelligence.partialGrades",
        "detail.intelligence.recentContribution",
        "detail.intelligence.schoolAverage",
        "detail.intelligence.source.estimated",
        "detail.intelligence.source.providedWeights",
        "detail.intelligence.source.schoolPrediction",
        "detail.intelligence.subjectUnavailable",
        "detail.intelligence.teacherDisclaimer",
        "detail.intelligence.worsening",
        "detail.simulator.addGrade",
        "detail.simulator.difference",
        "detail.simulator.done",
        "detail.simulator.grade",
        "detail.simulator.gradeNumber",
        "detail.simulator.hypotheticalGrades",
        "detail.simulator.invalidTarget",
        "detail.simulator.localOnly",
        "detail.simulator.mode",
        "detail.simulator.option",
        "detail.simulator.options",
        "detail.simulator.removeGrade",
        "detail.simulator.result",
        "detail.simulator.target",
        "detail.simulator.targetAverage",
        "detail.simulator.targetExplanation",
        "detail.simulator.targetReached",
        "detail.simulator.title",
        "detail.simulator.unavailable",
        "detail.simulator.unreachable",
        "detail.simulator.whatIf",
        "detail.weight.decrease",
        "detail.weight.increase",
        "gradey.ai.action.reply",
        "gradey.ai.action.study_priorities",
        "gradey.ai.action.subject_help",
        "gradey.ai.action.test_preparation",
        "gradey.ai.action.tomorrow",
        "gradey.ai.action.week_summary",
        "gradey.ai.compute.actionCost",
        "gradey.ai.compute.actionUnavailable",
        "gradey.ai.compute.checkRequest",
        "gradey.ai.compute.consentRequired",
        "gradey.ai.compute.pending",
        "gradey.ai.compute.priceChanged",
        "gradey.ai.compute.recoveryUnavailable",
        "gradey.ai.compute.remaining",
        "gradey.ai.compute.unavailable",
        "gradey.ai.compute.upgrade",
        "gradey.ai.consent.processors.message",
        "gradey.ai.consent.processors.title",
        "gradey.ai.consent.selectedContext",
        "gradey.ai.consent.selectedRetention",
        "gradey.ai.context.chooseAction",
        "gradey.ai.context.chooseItem",
        "gradey.ai.context.includeNotes",
        "gradey.ai.context.localTomorrow",
        "gradey.ai.context.newPurpose",
        "gradey.ai.context.none",
        "gradey.ai.context.selectedWeek",
        "gradey.ai.context.selectionSummary",
        "gradey.ai.context.tomorrowEmpty",
        "gradey.ai.prompt.general1",
        "gradey.ai.prompt.general2",
        "gradey.ai.prompt.study_priorities",
        "gradey.ai.prompt.subject_help",
        "gradey.ai.prompt.test_preparation",
        "gradey.ai.prompt.tomorrow",
        "gradey.ai.prompt.week_summary",
        "insight.assessment.due",
        "insight.average.changed",
        "insight.busy.tests",
        "insight.deadline.due",
        "insight.grade.edited",
        "insight.grade.new",
        "insight.trend.worsening",
        "planner.reminder.count",
        "planner.reminder.details",
        "planner.reminder.private",
        "planner.reminder.subjects",
        "planner.reminder.title",
        "planner.reminders.message",
        "planner.reminders.toggle",
        "today.attention.empty",
        "today.attention.title",
        "today.cached.warning",
        "today.destination.unavailable",
        "today.greeting.afternoon",
        "today.greeting.evening",
        "today.greeting.morning",
        "today.insight.recordedAverage",
        "today.planner.empty",
        "today.recentGrades.empty",
        "today.recentGrades.title",
        "today.recordedDate.unavailable",
        "today.refreshing",
    ]
}
