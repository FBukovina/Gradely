#if os(macOS)
import SwiftUI

/// What the menu bar can do in the focused main window. The window publishes
/// it with `focusedSceneValue` only while the signed-in tabs are on screen,
/// so the commands grey out during onboarding and sign-in.
struct MacWindowActions {
    var selectedTab: AppTab
    var showsMeals: Bool
    var selectTab: (AppTab) -> Void
    var refresh: () -> Void
    var newPlannerItem: () -> Void
    var openGradeyAI: () -> Void
}

private struct MacWindowActionsKey: FocusedValueKey {
    typealias Value = MacWindowActions
}

extension FocusedValues {
    var macWindowActions: MacWindowActions? {
        get { self[MacWindowActionsKey.self] }
        set { self[MacWindowActionsKey.self] = newValue }
    }
}

/// Hands the signed-in window's Settings content to the Settings scene. The
/// hub needs the main window's view model and callbacks, so the window
/// registers a builder here instead of the App owning a second copy.
@MainActor
@Observable
final class MacSettingsBridge {
    static let shared = MacSettingsBridge()

    var makeContent: (() -> AnyView)?

    private init() {}
}

/// Root of the Mac Settings window (⌘,).
struct MacSettingsWindow: View {
    @Environment(\.dismiss) private var dismiss
    private let bridge = MacSettingsBridge.shared

    var body: some View {
        if let makeContent = bridge.makeContent {
            makeContent()
                .tint(Brand.primary)
        } else {
            // Signed out or onboarding: there is nothing to configure yet.
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear { dismiss() }
        }
    }
}

struct GradeyMacCommands: Commands {
    @FocusedValue(\.macWindowActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // SwiftUI doesn't list the app's only window in the Window menu, so
        // once it's closed this is the way back (besides the Dock).
        CommandGroup(before: .windowList) {
            Button {
                openWindow(id: "main")
            } label: {
                Text(verbatim: "Gradey")
            }
            .keyboardShortcut("0")

            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button(AppL10n.string("planner.add")) { actions?.newPlannerItem() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }

        CommandGroup(before: .sidebar) {
            ForEach(AppTab.allCases.filter { $0 != .stravaCZ || actions?.showsMeals != false }) { tab in
                Toggle(AppL10n.string(tab.titleKey), isOn: Binding(
                    get: { actions?.selectedTab == tab },
                    set: { if $0 { actions?.selectTab(tab) } }
                ))
                .keyboardShortcut(tab.shortcut)
                .disabled(actions == nil)
            }

            Divider()

            Button(AppL10n.string("gradey.ai.title")) { actions?.openGradeyAI() }
                .keyboardShortcut("k")
                .disabled(actions == nil)

            Button(AppL10n.string("action.refresh")) { actions?.refresh() }
                .keyboardShortcut("r")
                .disabled(actions == nil)

            Divider()
        }
    }
}

private extension AppTab {
    var titleKey: String.LocalizationValue {
        switch self {
        case .today: "Today"
        case .subjects: "subjects.title"
        case .absence: "absence.title"
        case .timetable: "rozvrh.title"
        case .stravaCZ: "stravacz.title"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .subjects: "2"
        case .absence: "3"
        case .timetable: "4"
        case .stravaCZ: "5"
        }
    }
}
#endif
