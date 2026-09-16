//
//  GradelyApp.swift
//  Gradely
//
//  Created by Filip Bukovina on 01.06.2026.
//

import SwiftUI
import HugeiconsStrokeRounded

@main
struct GradelyApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(GradeyAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(GradeyMacAppDelegate.self) private var appDelegate
    #endif
    @State private var languageStore: AppLanguageStore

    init() {
        _ = HugeiconsStrokeRounded.load()
        GradelyDisplayFont.registerIfNeeded()
        GradeyFirebaseConfiguration.configureIfNeeded()
        RevenueCatConfiguration.configureIfNeeded()
        IntercomConfiguration.configureIfNeeded()
        Self.resetLanguageForUITestsIfNeeded()
        Self.attestAgeForUITestsIfNeeded()
        let store = AppLanguageStore.shared
        store.prepareAtLaunch()
        _languageStore = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView()
                .frame(minWidth: 880, minHeight: 600)
                .appLanguage(languageStore)
            #else
            ContentView()
                .appLanguage(languageStore)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button("legal.privacyPolicy") {
                    AppLinks.open(AppLinks.privacyPolicyURL)
                }
                Button("legal.termsOfUse") {
                    AppLinks.open(AppLinks.termsOfUseURL)
                }
            }
        }
        #endif
    }
}

private extension View {
    func appLanguage(_ store: AppLanguageStore) -> some View {
        environment(\.locale, store.locale)
            .environment(store)
    }
}

private extension GradelyApp {
    static func resetLanguageForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingMockAPI") else { return }
        if !arguments.contains("-settings.appLanguage") {
            UserDefaults.standard.set(
                AppLanguage.system.rawValue,
                forKey: AppLanguageStore.storageKey
            )
        }
    }

    static func attestAgeForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingMockAPI") else { return }
        if arguments.contains(AgeAttestationStore.uiTestingShowArgument) {
            UserDefaults.standard.removeObject(forKey: AgeAttestationStore.storageKey)
            return
        }
        UserDefaults.standard.set(
            AgeAttestationKind.sixteenOrOlder.rawValue,
            forKey: AgeAttestationStore.storageKey
        )
    }
}
