import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

protocol DevicePushTokenClient {
    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws
    func updateNotificationPreferences(_ preferences: NotificationPreferences, gradeySession: GradeyAuthSession) async throws
}

@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private var client: (any DevicePushTokenClient)?
    private var authClient: (any GradeyAuthClient)?
    private var preferencesStore: MarkNotificationSettingsStore?

    private init() {}

    func configure(
        client: any DevicePushTokenClient,
        authClient: any GradeyAuthClient,
        preferencesStore: MarkNotificationSettingsStore
    ) {
        self.client = client
        self.authClient = authClient
        self.preferencesStore = preferencesStore
    }

    func requestAuthorizationAfterFirstLink() async {
        guard preferencesStore?.preferences.newMarksEnabled ?? true else { return }

        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        } catch {
            // Permission prompts should never block account linking.
        }
    }

    func handleDeviceToken(_ data: Data) async {
        guard
            let client,
            let session = try? authClient?.bootstrapSession()
        else {
            return
        }

        let token = data.map { String(format: "%02x", $0) }.joined()
        let platform: String
        #if os(iOS)
        platform = "ios"
        #elseif os(macOS)
        platform = "macos"
        #else
        platform = "unknown"
        #endif

        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif

        try? await client.registerDeviceToken(token, platform: platform, environment: environment, gradeySession: session)
    }
}

final class SupabaseDevicePushTokenClient: DevicePushTokenClient {
    private let configuration: SupabaseConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.sessionEncoder

    init(configuration: SupabaseConfiguration? = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws {
        try await send(
            function: "register-device",
            gradeySession: gradeySession,
            body: RegisterDeviceRequest(token: token, platform: platform, environment: environment)
        )
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences, gradeySession: GradeyAuthSession) async throws {
        try await send(
            function: "update-notification-preferences",
            gradeySession: gradeySession,
            body: preferences
        )
    }

    private func send<Body: Encodable>(function: String, gradeySession: GradeyAuthSession, body: Body) async throws {
        guard let configuration else { throw GradeyAuthError.notConfigured }
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(gradeySession.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GradeyAuthError.server(String(localized: "gradey.account.error.pushSettingsFailed"))
        }
    }
}

final class MockDevicePushTokenClient: DevicePushTokenClient {
    private(set) var registeredTokens: [String] = []
    private(set) var preferences: NotificationPreferences?

    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws {
        registeredTokens.append(token)
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences, gradeySession: GradeyAuthSession) async throws {
        self.preferences = preferences
    }
}

final class MarkNotificationSettingsStore {
    private let userDefaults: UserDefaults
    private let key = "gradey.notificationPreferences.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var preferences: NotificationPreferences {
        get {
            guard let data = userDefaults.data(forKey: key),
                  let decoded = try? JSONDecoder.sessionDecoder.decode(NotificationPreferences.self, from: data)
            else {
                return .default
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder.sessionEncoder.encode(newValue) else { return }
            userDefaults.set(data, forKey: key)
        }
    }
}

private struct RegisterDeviceRequest: Encodable {
    let token: String
    let platform: String
    let environment: String
}

#if os(iOS)
final class GradeyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushRegistrationService.shared.handleDeviceToken(deviceToken)
        }
    }
}
#elseif os(macOS)
final class GradeyMacAppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushRegistrationService.shared.handleDeviceToken(deviceToken)
        }
    }
}
#endif
