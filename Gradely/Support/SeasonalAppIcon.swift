import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Puts the red app icon up while `ChristmasSeason` is on and the regular
/// one back afterwards.
///
/// iOS changes an icon only for an app in the foreground and always shows
/// its own "icon changed" alert, so the switch happens the first time Gradey
/// is opened in or after the season. On the Mac only the running app's Dock
/// tile can change; Finder and Launchpad keep the bundled icon.
enum SeasonalAppIcon {
    static let christmasIconName = "AppIconChristmas"
    static let christmasDockImageName = "ChristmasDockIcon"

    private static var isApplying = false

    static func apply() async {
        #if os(iOS)
        // The system alert would get in the way of UI tests, unless a test
        // moved the season clock on purpose.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI"), !ChristmasSeason.isDemoClockSet {
            return
        }
        let application = UIApplication.shared
        guard application.supportsAlternateIcons, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        // Asking right as the app activates can fail with "resource
        // temporarily unavailable", so wait a moment and try twice.
        for delay in [1.0, 2.0] {
            try? await Task.sleep(for: .seconds(delay))
            let wanted = ChristmasSeason.isActive ? christmasIconName : nil
            guard application.applicationState == .active, application.alternateIconName != wanted else { return }
            do {
                try await application.setAlternateIconName(wanted)
                return
            } catch {
                continue
            }
        }
        #elseif os(macOS)
        NSApplication.shared.applicationIconImage = ChristmasSeason.isActive
            ? NSImage(named: christmasDockImageName)
            : nil
        #endif
    }
}
