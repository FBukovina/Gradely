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

    init() {
        _ = HugeiconsStrokeRounded.load()
        GradeyFirebaseConfiguration.configureIfNeeded()
        RevenueCatConfiguration.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView()
                .frame(minWidth: 880, minHeight: 600)
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}
