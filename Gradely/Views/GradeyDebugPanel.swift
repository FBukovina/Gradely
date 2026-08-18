import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GradeyDebugSnapshot: Equatable {
    var supabaseUserID: String?
    var revenueCatAppUserID: String?
    var revenueCatOriginalAppUserID: String?
    var linkedAccountID: String?
    var isGuestMode: Bool
    var hasCompletedOnboardingV2: Bool
    var hasCompletedOnboardingV1: Bool
    var savedJourney: OnboardingJourney?
    var savedStep: OnboardingStep?

    static func make(
        supabaseUserID: String?,
        linkedAccountID: String?,
        isGuestMode: Bool,
        userDefaults: UserDefaults = .standard,
        progressStore: any OnboardingProgressStoring = OnboardingProgressStore()
    ) -> GradeyDebugSnapshot {
        let progress = progressStore.loadProgress()
        return GradeyDebugSnapshot(
            supabaseUserID: supabaseUserID,
            revenueCatAppUserID: RevenueCatIdentity.appUserID,
            revenueCatOriginalAppUserID: RevenueCatIdentity.originalAppUserID,
            linkedAccountID: linkedAccountID,
            isGuestMode: isGuestMode,
            hasCompletedOnboardingV2: userDefaults.bool(forKey: OnboardingProgressStore.completionKey),
            hasCompletedOnboardingV1: userDefaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey),
            savedJourney: progress?.journey,
            savedStep: progress?.step
        )
    }
}

enum GradeyDebugPendingAction: Equatable {
    case restart(OnboardingJourney)
    case signOut
    case clearCache
    case resetAsNewUser
}

struct GradeyDebugPanel: View {
    let snapshot: GradeyDebugSnapshot
    let onRestart: (OnboardingJourney) -> Void
    let onSignOut: () -> Void
    let onClearCache: () -> Void
    let onResetAsNewUser: () -> Void
    let onDisable: () -> Void

    @State private var pendingAction: GradeyDebugPendingAction?
    @State private var copiedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "debug.title",
                message: "debug.message"
            )

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    copyableRow(
                        title: "debug.supabaseID",
                        value: snapshot.supabaseUserID,
                        copiedLabel: String(localized: "debug.supabaseID"),
                        identifier: "debugSupabaseID"
                    )
                    SettingsRowDivider()
                    copyableRow(
                        title: "debug.revenueCatID",
                        value: snapshot.revenueCatAppUserID,
                        copiedLabel: String(localized: "debug.revenueCatID"),
                        identifier: "debugRevenueCatID"
                    )
                    SettingsRowDivider()
                    copyableRow(
                        title: "debug.revenueCatOriginalID",
                        value: snapshot.revenueCatOriginalAppUserID,
                        copiedLabel: String(localized: "debug.revenueCatOriginalID"),
                        identifier: "debugRevenueCatOriginalID"
                    )
                    SettingsRowDivider()
                    copyableRow(
                        title: "debug.linkedAccountID",
                        value: snapshot.linkedAccountID,
                        copiedLabel: String(localized: "debug.linkedAccountID"),
                        identifier: "debugLinkedAccountID"
                    )
                }
            }

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    SettingsValueRow(
                        title: "debug.guestMode",
                        value: snapshot.isGuestMode
                            ? String(localized: "debug.yes")
                            : String(localized: "debug.no")
                    )
                    .padding(20)
                    .accessibilityIdentifier("debugGuestMode")

                    SettingsRowDivider()

                    SettingsValueRow(
                        title: "debug.onboardingV2",
                        value: snapshot.hasCompletedOnboardingV2
                            ? String(localized: "debug.yes")
                            : String(localized: "debug.no")
                    )
                    .padding(20)

                    SettingsRowDivider()

                    SettingsValueRow(
                        title: "debug.onboardingV1",
                        value: snapshot.hasCompletedOnboardingV1
                            ? String(localized: "debug.yes")
                            : String(localized: "debug.no")
                    )
                    .padding(20)

                    SettingsRowDivider()

                    SettingsValueRow(
                        title: "debug.onboardingProgress",
                        value: progressSummary
                    )
                    .padding(20)
                }
            }

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Button {
                        pendingAction = .restart(.newUser)
                    } label: {
                        Text("debug.restartNewUser")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("debugRestartNewUserButton")

                    Button {
                        pendingAction = .restart(.upgrade)
                    } label: {
                        Text("debug.restartUpgrade")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("debugRestartUpgradeButton")

                    Button {
                        pendingAction = .resetAsNewUser
                    } label: {
                        Text("debug.resetAsNewUser")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("debugResetAsNewUserButton")

                    Button {
                        pendingAction = .signOut
                    } label: {
                        Text("debug.signOut")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debugSignOutButton")

                    Button {
                        pendingAction = .clearCache
                    } label: {
                        Text("debug.clearCache")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debugClearCacheButton")

                    Button(role: .destructive) {
                        onDisable()
                    } label: {
                        Text("debug.disable")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debugDisableButton")
                }
            }

            if let copiedField {
                Text(String(format: String(localized: "debug.copied"), copiedField))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("debugCopiedLabel")
            }
        }
        .confirmationDialog(
            actionTitle,
            isPresented: actionDialogBinding,
            titleVisibility: .visible
        ) {
            Button(actionConfirmTitle, role: actionIsDestructive ? .destructive : nil) {
                performPendingAction()
            }
            .accessibilityIdentifier("debugRestartConfirmButton")
            Button("action.cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(actionMessage)
        }
        .accessibilityIdentifier("debugPanel")
    }

    private var progressSummary: String {
        guard let journey = snapshot.savedJourney, let step = snapshot.savedStep else {
            return String(localized: "debug.none")
        }
        return "\(journey.rawValue) / \(step.rawValue)"
    }

    private var actionTitle: LocalizedStringKey {
        switch pendingAction {
        case .restart(.upgrade): "debug.restartUpgrade.confirm.title"
        case .restart: "debug.restartNewUser.confirm.title"
        case .signOut: "debug.signOut.confirm.title"
        case .clearCache: "debug.clearCache.confirm.title"
        case .resetAsNewUser: "debug.resetAsNewUser.confirm.title"
        case nil: "debug.title"
        }
    }

    private var actionMessage: LocalizedStringKey {
        switch pendingAction {
        case .restart(.upgrade): "debug.restartUpgrade.confirm.message"
        case .restart: "debug.restartNewUser.confirm.message"
        case .signOut: "debug.signOut.confirm.message"
        case .clearCache: "debug.clearCache.confirm.message"
        case .resetAsNewUser: "debug.resetAsNewUser.confirm.message"
        case nil: "debug.message"
        }
    }

    private var actionConfirmTitle: LocalizedStringKey {
        switch pendingAction {
        case .signOut: "debug.signOut"
        case .clearCache: "debug.clearCache"
        case .resetAsNewUser: "debug.resetAsNewUser"
        default: "debug.restart.confirm"
        }
    }

    private var actionIsDestructive: Bool {
        switch pendingAction {
        case .signOut, .clearCache, .resetAsNewUser: true
        default: false
        }
    }

    private var actionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )
    }

    private func performPendingAction() {
        switch pendingAction {
        case .restart(let journey):
            onRestart(journey)
        case .signOut:
            onSignOut()
        case .clearCache:
            onClearCache()
        case .resetAsNewUser:
            onResetAsNewUser()
        case nil:
            break
        }
        pendingAction = nil
    }

    private func copyableRow(
        title: LocalizedStringKey,
        value: String?,
        copiedLabel: String,
        identifier: String
    ) -> some View {
        let display = displayValue(value)
        return Button {
            copy(display)
            copiedField = copiedLabel
        } label: {
            SettingsValueRow(title: title, value: display)
                .padding(20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "debug.unavailable") : trimmed
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }
}
