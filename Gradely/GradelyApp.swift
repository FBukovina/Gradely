//
//  GradelyApp.swift
//  Gradely
//
//  Created by Filip Bukovina on 01.06.2026.
//

import SwiftUI
import AppIntents
import HugeiconsStrokeRounded

@main
struct GradelyApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(GradeyAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(GradeyMacAppDelegate.self) private var appDelegate
    #endif
    @State private var languageStore: AppLanguageStore
    private let environment: AppEnvironment
    private let siriService: GradeyIntentService
    private let siriDiscovery: GradeySiriDiscoveryCoordinator

    init() {
        _ = HugeiconsStrokeRounded.load()
        GradelyDisplayFont.registerIfNeeded()
        GradeyFirebaseConfiguration.configureIfNeeded()
        RevenueCatConfiguration.configureIfNeeded()
        IntercomConfiguration.configureIfNeeded()
        Self.resetLanguageForUITestsIfNeeded()
        Self.attestAgeForUITestsIfNeeded()
        Self.seedPrivacyPolicyConsentForUITestsIfNeeded()
        let store = AppLanguageStore.shared
        store.prepareAtLaunch()
        _languageStore = State(initialValue: store)
        let environment = AppEnvironment.current()
        self.environment = environment
        let service = GradeyIntentService(environment: environment)
        self.siriService = service
        self.siriDiscovery = GradeySiriDiscoveryCoordinator(service: service)
        AppDependencyManager.shared.add(dependency: environment)
        AppDependencyManager.shared.add(dependency: service)
        GradeyAppShortcuts.updateAppShortcutParameters()
        siriDiscovery.start()
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView(environment: environment, siriService: siriService)
                .frame(minWidth: 880, minHeight: 600)
                .appLanguage(languageStore)
            #else
            ContentView(environment: environment, siriService: siriService)
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

    /// UI tests must not meet the policy sheet unless they ask for it —
    /// otherwise every existing signed-in test launches behind it.
    static func seedPrivacyPolicyConsentForUITestsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingMockAPI") else { return }
        let store = PrivacyPolicyConsentStore.shared
        if arguments.contains(PrivacyPolicyConsentStore.uiTestingShowArgument) {
            store.clear()
            return
        }
        store.accept()
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
