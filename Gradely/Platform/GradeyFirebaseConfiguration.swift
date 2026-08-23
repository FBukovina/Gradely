import Foundation

#if canImport(FirebaseAppCheck) && canImport(FirebaseCore)
import FirebaseAppCheck
import FirebaseCore
#endif

enum GradeyFirebaseConfiguration {
    nonisolated static var isConfigured: Bool {
        #if canImport(FirebaseCore)
        FirebaseApp.app() != nil
        #else
        false
        #endif
    }

    nonisolated static func configureIfNeeded() {
        #if canImport(FirebaseAppCheck) && canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { return }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path)
        else {
            return
        }

        AppCheck.setAppCheckProviderFactory(GradeyAppCheckProviderFactory())
        FirebaseApp.configure(options: options)
        #endif
    }
}

#if canImport(FirebaseAppCheck) && canImport(FirebaseCore)
nonisolated final class GradeyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, macOS 11.3, *),
           let provider = AppAttestProvider(app: app) {
            return provider
        }
        #if !os(macOS)
        if #available(iOS 11.0, *) {
            return DeviceCheckProvider(app: app)
        }
        #endif
        return nil
        #endif
    }
}
#endif
