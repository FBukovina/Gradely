import Foundation
import Testing
@testable import Gradely

struct ChronicallyOnlineTextTests {
    @Test func lowercasesCopyWhileKeepingBrandNames() {
        #expect(ChronicallyOnlineText.transform("Welcome to Gradey") == "welcome to Gradey")
        #expect(ChronicallyOnlineText.transform("Apple ID connected") == "Apple ID connected")
        #expect(ChronicallyOnlineText.transform("Sign in to Strava.cz") == "sign in to Strava.cz")
        #expect(ChronicallyOnlineText.transform("Ask Gradey AI about marks") == "ask Gradey AI about marks")
    }

    @Test func preservesFormatSpecifiers() {
        #expect(ChronicallyOnlineText.transform("Error %d") == "error %d")
        #expect(ChronicallyOnlineText.transform("Selected %lld of %lld lessons") == "selected %lld of %lld lessons")
        #expect(ChronicallyOnlineText.transform("Average %.2f") == "average %.2f")
        #expect(ChronicallyOnlineText.transform("%1$@ · %2$@") == "%1$@ · %2$@")
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
