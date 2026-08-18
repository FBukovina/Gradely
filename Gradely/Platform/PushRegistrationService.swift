import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

protocol GradeyAccountSettingsClient {
    func fetchAccountSettings(gradeySession: GradeyAuthSession) async throws -> GradeyAccountSettingsSnapshot
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        gradeySession: GradeyAuthSession
    ) async throws -> NotificationPreferences
    func requestDataExport(gradeySession: GradeyAuthSession) async throws -> Data
    func deleteAccount(gradeySession: GradeyAuthSession) async throws
}

enum GradeyFunctionError: LocalizedError, Equatable {
    case httpStatus(
        function: String,
        statusCode: Int,
        code: String?,
        message: String?
    )

    var errorDescription: String? {
        switch self {
        case .httpStatus(_, _, _, let message):
            guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return String(localized: "gradey.account.error.requestFailed")
            }
            return message
        }
    }

    var isUnavailableCapability: Bool {
        switch self {
        case .httpStatus(_, let statusCode, let code, _):
            return statusCode == 404 && code == "NOT_FOUND"
        }
    }
}

protocol DevicePushTokenClient: GradeyAccountSettingsClient {
    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws
}

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol NotificationAuthorizing: AnyObject {
    func authorizationStatus() async -> NotificationAuthorizationStatus

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorizationStatus

    func openSystemSettings()
}

@MainActor
final class PushRegistrationService: NotificationAuthorizing {
    static let shared = PushRegistrationService()

    private var client: (any DevicePushTokenClient)?
    private var authClient: (any GradeyAuthClient)?
    private var pendingDeviceToken: Data?

    private init() {}

    func configure(
        client: any DevicePushTokenClient,
        authClient: any GradeyAuthClient
    ) {
        self.client = client
        self.authClient = authClient
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.authorizationStatus(from: settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                registerForRemoteNotifications()
            }
        } catch {
            // Permission prompts should never block account linking.
        }

        return await authorizationStatus()
    }

    func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    func refreshRegistrationIfAuthorized() async {
        guard await authorizationStatus() == .authorized else { return }
        registerForRemoteNotifications()
        if let pendingDeviceToken {
            await handleDeviceToken(pendingDeviceToken)
        }
    }

    func handleDeviceToken(_ data: Data) async {
        pendingDeviceToken = data
        guard
            let client,
            let authClient,
            let session = try? await authClient.validSession()
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

    private func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private static func authorizationStatus(from status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional:
            return .authorized
        #if os(iOS)
        case .ephemeral:
            return .authorized
        #endif
        @unknown default:
            return .notDetermined
        }
    }
}

@MainActor
final class MockNotificationAuthorizer: NotificationAuthorizing {
    var status: NotificationAuthorizationStatus
    var requestResult: NotificationAuthorizationStatus

    private(set) var authorizationStatusCallCount = 0
    private(set) var requestAuthorizationCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(
        status: NotificationAuthorizationStatus = .notDetermined,
        requestResult: NotificationAuthorizationStatus = .authorized
    ) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        authorizationStatusCallCount += 1
        return status
    }

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        requestAuthorizationCallCount += 1
        status = requestResult
        return status
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

final class SupabaseDevicePushTokenClient: DevicePushTokenClient {
    private let configuration: SupabaseConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.sessionEncoder
    private let decoder = JSONDecoder.gradeyAPIDecoder

    init(configuration: SupabaseConfiguration? = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws {
        _ = try await sendData(
            function: "register-device",
            method: "POST",
            gradeySession: gradeySession,
            body: RegisterDeviceRequest(token: token, platform: platform, environment: environment)
        )
    }

    func fetchAccountSettings(gradeySession: GradeyAuthSession) async throws -> GradeyAccountSettingsSnapshot {
        let data = try await sendData(
            function: "account-settings",
            method: "GET",
            gradeySession: gradeySession,
            body: Optional<EmptyRequest>.none
        )
        return try decoder.decode(GradeyAccountSettingsSnapshot.self, from: data)
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        gradeySession: GradeyAuthSession
    ) async throws -> NotificationPreferences {
        let data = try await sendData(
            function: "update-notification-preferences",
            method: "POST",
            gradeySession: gradeySession,
            body: preferences
        )

        // Older deployments accepted the update but returned an empty JSON
        // object. Treat that legacy success response as the submitted value so
        // a staggered backend rollout does not roll back a valid preference.
        if data.isEmpty || Self.isEmptyJSONObject(data) {
            return preferences
        }

        return try decoder.decode(NotificationPreferencesResponse.self, from: data).notificationPreferences
    }

    func requestDataExport(gradeySession: GradeyAuthSession) async throws -> Data {
        try await sendData(
            function: "request-data-export",
            method: "POST",
            gradeySession: gradeySession,
            body: Optional<EmptyRequest>.none
        )
    }

    func deleteAccount(gradeySession: GradeyAuthSession) async throws {
        _ = try await sendData(
            function: "delete-account",
            method: "POST",
            gradeySession: gradeySession,
            body: Optional<EmptyRequest>.none
        )
    }

    private func sendData<Body: Encodable>(
        function: String,
        method: String,
        gradeySession: GradeyAuthSession,
        body: Body?
    ) async throws -> Data {
        guard let configuration else { throw GradeyAuthError.notConfigured }
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/\(function)"))
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(gradeySession.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GradeyAuthError.server(String(localized: "gradey.account.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverError = Self.serverError(from: data)
            throw GradeyFunctionError.httpStatus(
                function: function,
                statusCode: httpResponse.statusCode,
                code: serverError.code,
                message: serverError.message
            )
        }
        return data
    }

    private static func serverError(from data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, text?.isEmpty == false ? text : nil)
        }

        let rawMessage = (object["error"] as? String) ?? (object["message"] as? String)
        let message = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            object["code"] as? String,
            message?.isEmpty == false ? message : nil
        )
    }

    private static func isEmptyJSONObject(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object.isEmpty
    }

}

private struct NotificationPreferencesResponse: Decodable {
    let notificationPreferences: NotificationPreferences

    enum CodingKeys: String, CodingKey {
        case notificationPreferences = "notification_preferences"
    }
}

final class MockDevicePushTokenClient: DevicePushTokenClient {
    private(set) var registeredTokens: [String] = []
    private(set) var preferences: NotificationPreferences?
    private(set) var didRequestDataExport = false
    private(set) var didDeleteAccount = false

    var accountSettings: GradeyAccountSettingsSnapshot
    var exportData: Data
    var fetchError: Error?
    var updateError: Error?
    var exportError: Error?
    var deleteError: Error?

    init(
        accountSettings: GradeyAccountSettingsSnapshot = GradeyAccountSettingsSnapshot(
            activeSchoolAccountID: nil,
            linkedAccounts: [],
            notificationPreferences: .default
        ),
        exportData: Data = Data("{}".utf8),
        fetchError: Error? = nil,
        updateError: Error? = nil,
        exportError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.accountSettings = accountSettings
        self.exportData = exportData
        self.fetchError = fetchError
        self.updateError = updateError
        self.exportError = exportError
        self.deleteError = deleteError
    }

    func registerDeviceToken(_ token: String, platform: String, environment: String, gradeySession: GradeyAuthSession) async throws {
        registeredTokens.append(token)
    }

    func fetchAccountSettings(gradeySession: GradeyAuthSession) async throws -> GradeyAccountSettingsSnapshot {
        if let fetchError { throw fetchError }
        return accountSettings
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        gradeySession: GradeyAuthSession
    ) async throws -> NotificationPreferences {
        if let updateError { throw updateError }
        self.preferences = preferences
        accountSettings = GradeyAccountSettingsSnapshot(
            activeSchoolAccountID: accountSettings.activeSchoolAccountID,
            linkedAccounts: accountSettings.linkedAccounts,
            notificationPreferences: preferences
        )
        return preferences
    }

    func requestDataExport(gradeySession: GradeyAuthSession) async throws -> Data {
        if let exportError { throw exportError }
        didRequestDataExport = true
        return exportData
    }

    func deleteAccount(gradeySession: GradeyAuthSession) async throws {
        if let deleteError { throw deleteError }
        didDeleteAccount = true
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

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

private struct RegisterDeviceRequest: Encodable {
    let token: String
    let platform: String
    let environment: String
}

private struct EmptyRequest: Encodable {}

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
