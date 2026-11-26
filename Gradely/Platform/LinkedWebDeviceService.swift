import Foundation
import Observation

// MARK: - QR Pairing Payload

struct QRPairingPayload: Equatable, Identifiable, Sendable {
    let version: Int
    let challengeID: String
    let qrSecret: String

    var id: String { challengeID }

    init?(rawString: String) {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "gradey" || scheme == "gradely",
              url.host?.lowercased() == "pair" || url.path == "/pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let items = components.queryItems ?? []
        // Reject QR codes carrying unexpected or credential-like parameters.
        let allowedNames: Set<String> = ["v", "c", "t"]
        guard items.allSatisfy({ allowedNames.contains($0.name) }) else {
            return nil
        }

        let rawVersion = items.first(where: { $0.name == "v" })?.value ?? "1"
        guard let parsedVersion = Int(rawVersion), parsedVersion == 1 else {
            return nil
        }

        guard let rawChallenge = items.first(where: { $0.name == "c" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              UUID(uuidString: rawChallenge) != nil,
              let rawSecret = items.first(where: { $0.name == "t" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              (24...128).contains(rawSecret.count),
              rawSecret.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else {
            return nil
        }

        self.version = parsedVersion
        self.challengeID = rawChallenge.lowercased()
        self.qrSecret = rawSecret
    }
}

// MARK: - Linked Web Device Models

struct WebPairingChallengePreview: Codable, Equatable, Identifiable, Sendable {
    let challengeID: String
    let browserName: String
    let osName: String
    let deviceLabel: String
    let createdAt: Date
    let expiresAt: Date

    var id: String { challengeID }

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case browserName
        case osName
        case deviceLabel
        case createdAt
        case expiresAt
    }
}

struct LinkedWebDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: LinkedAccountProvider
    let studentName: String
    let className: String?
    let schoolName: String?
    let browserName: String
    let osName: String
    let deviceLabel: String
    let firstLoginAt: Date
    let lastActiveAt: Date
    let expiresAt: Date

    var browserAndDeviceTitle: String {
        let trimmedLabel = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return browserName
    }

    var hugeiconName: String {
        let lowerOS = osName.lowercased()
        if lowerOS.contains("ios") || lowerOS.contains("android") {
            return "smart-phone-01"
        }
        if lowerOS.contains("ipados") {
            return "laptop"
        }
        if lowerOS.contains("mac") || lowerOS.contains("windows") || lowerOS.contains("linux") || lowerOS.contains("chrome") {
            return "laptop"
        }
        return "browser"
    }
}

enum LinkedWebDeviceError: LocalizedError, Equatable {
    case invalidQRCode
    case missingSchoolSession
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidQRCode:
            return AppL10n.string("settings.linkedDevices.error.invalidQR")
        case .missingSchoolSession:
            return AppL10n.string("settings.linkedDevices.error.missingSchool")
        case .server(let message):
            return message
        }
    }
}

struct GradeyWebConfiguration: Equatable {
    let baseURL: URL

    static func fromBundle(_ bundle: Bundle = .main) -> GradeyWebConfiguration? {
        guard let raw = bundle.object(forInfoDictionaryKey: "GradeyWebURL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else {
            return nil
        }
        #if DEBUG
        guard scheme == "https" || scheme == "http" else { return nil }
        #else
        guard scheme == "https" else { return nil }
        #endif
        return GradeyWebConfiguration(baseURL: url)
    }
}

// MARK: - Client Protocol & Live Implementation

protocol LinkedWebDeviceClient {
    func fetchLinkedDevices(gradeySession: GradeyAuthSession) async throws -> [LinkedWebDevice]
    func inspectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws -> WebPairingChallengePreview
    func rejectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws
    func approveChallenge(
        _ payload: QRPairingPayload,
        schoolSession: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedWebDevice
    func revokeDevice(id: String, gradeySession: GradeyAuthSession) async throws
    func revokeAllDevices(gradeySession: GradeyAuthSession) async throws -> Int
}

final class GradeyLinkedWebDeviceClient: LinkedWebDeviceClient {
    private let webConfiguration: GradeyWebConfiguration?
    private let supabaseConfiguration: SupabaseConfiguration?
    private let urlSession: URLSession
    private let bakalariClient: any BakalariClient
    private let dateProvider: () -> Date
    private let encoder = JSONEncoder.sessionEncoder
    private let decoder = JSONDecoder.gradeyAPIDecoder

    init(
        webConfiguration: GradeyWebConfiguration? = .fromBundle(),
        supabaseConfiguration: SupabaseConfiguration? = .fromBundle(),
        urlSession: URLSession = .shared,
        bakalariClient: (any BakalariClient)? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.webConfiguration = webConfiguration
        self.supabaseConfiguration = supabaseConfiguration
        self.urlSession = urlSession
        self.bakalariClient = bakalariClient ?? URLSessionBakalariClient(urlSession: urlSession)
        self.dateProvider = dateProvider
    }

    func fetchLinkedDevices(gradeySession: GradeyAuthSession) async throws -> [LinkedWebDevice] {
        let response: DevicesListResponse = try await send(
            endpoint: .listDevices,
            gradeySession: gradeySession,
            body: Optional<EmptyPayload>.none
        )
        return response.devices
    }

    func inspectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws -> WebPairingChallengePreview {
        try await send(
            endpoint: .inspect,
            gradeySession: gradeySession,
            body: ChallengeSecretRequest(challengeId: payload.challengeID, qrSecret: payload.qrSecret)
        )
    }

    func rejectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws {
        let _: EmptyObjectResponse = try await send(
            endpoint: .reject,
            gradeySession: gradeySession,
            body: ChallengeSecretRequest(challengeId: payload.challengeID, qrSecret: payload.qrSecret)
        )
    }

    func approveChallenge(
        _ payload: QRPairingPayload,
        schoolSession: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedWebDevice {
        let dedicatedPayload = try await makeDedicatedWebSessionPayload(from: schoolSession)
        let studentName = user?.fullName
            ?? schoolSession.eduPage?.activeStudent?.fullName
            ?? schoolSession.linkedAccountDisplayName
            ?? dedicatedPayload.provider.displayName
        let className = user?.userClass?.abbrev ?? schoolSession.eduPage?.activeStudent?.className
        let schoolName = user?.displaySchoolName ?? schoolSession.linkedAccountSchoolName

        let request = ApproveWebPairingRequest(
            challengeId: payload.challengeID,
            qrSecret: payload.qrSecret,
            linkedAccountID: schoolSession.linkedAccountID,
            provider: dedicatedPayload.provider,
            providerUserID: user?.userUID ?? schoolSession.eduPage?.activeStudent?.id ?? schoolSession.eduPage?.userID,
            baseURL: dedicatedPayload.baseURL,
            studentName: studentName,
            className: className,
            schoolName: schoolName,
            tokenPayload: dedicatedPayload
        )
        let response: ApproveDeviceResponse = try await send(
            endpoint: .approve,
            gradeySession: gradeySession,
            body: request
        )
        return response.device
    }

    func revokeDevice(id: String, gradeySession: GradeyAuthSession) async throws {
        let _: EmptyObjectResponse = try await send(
            endpoint: .revoke(id: id),
            gradeySession: gradeySession,
            body: RevokeSessionRequest(sessionId: id)
        )
    }

    func revokeAllDevices(gradeySession: GradeyAuthSession) async throws -> Int {
        let response: RevokeAllResponse = try await send(
            endpoint: .revokeAll,
            gradeySession: gradeySession,
            body: EmptyPayload()
        )
        return response.revokedCount
    }

    /// Mints an isolated Bakaláři token family directly with the school server so the
    /// linked web session never shares rotating refresh tokens with this phone or the
    /// background poller, and never sends raw credentials to Gradey servers.
    private func makeDedicatedWebSessionPayload(
        from session: StoredSession
    ) async throws -> ProviderSecretSanitizer.SchoolPayload {
        guard webConfiguration != nil || (supabaseConfiguration?.isConfigured == true) else {
            throw GradeyAuthError.notConfigured
        }
        guard session.provider == .bakalari else {
            return ProviderSecretSanitizer.schoolPayload(from: session)
        }
        guard let credentials = session.bakalari,
              !credentials.username.isEmpty,
              !credentials.password.isEmpty
        else {
            throw SchoolAuthenticationError.deviceSignInRequired
        }

        let response = try await bakalariClient.login(
            baseURL: session.baseURL,
            username: credentials.username,
            password: credentials.password
        )
        guard !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              response.refreshToken != session.refreshToken
        else {
            throw SchoolAuthenticationError.deviceSignInRequired
        }

        let now = dateProvider()
        let dedicatedSession = StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            baseURL: session.baseURL
        )
        var sanitized = ProviderSecretSanitizer.schoolPayload(from: dedicatedSession)
        sanitized.webSessionEstablishedAt = now
        return sanitized
    }

    private enum Endpoint {
        case listDevices
        case inspect
        case reject
        case approve
        case revoke(id: String)
        case revokeAll
    }

    private func send<Response: Decodable, Body: Encodable>(
        endpoint: Endpoint,
        gradeySession: GradeyAuthSession,
        body: Body?
    ) async throws -> Response {
        let request = try buildRequest(endpoint: endpoint, gradeySession: gradeySession, body: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedWebDeviceError.server(AppL10n.string("gradey.account.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let decodedError = try? decoder.decode(ServerErrorEnvelope.self, from: data),
               let message = decodedError.displayMessage,
               !message.isEmpty {
                throw LinkedWebDeviceError.server(message)
            }
            let rawMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LinkedWebDeviceError.server(
                rawMessage?.isEmpty == false ? rawMessage! : AppL10n.string("gradey.account.error.requestFailed")
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func buildRequest<Body: Encodable>(
        endpoint: Endpoint,
        gradeySession: GradeyAuthSession,
        body: Body?
    ) throws -> URLRequest {
        let url: URL
        let method: String
        var extraHeaders: [String: String] = [:]

        if let webConfiguration {
            switch endpoint {
            case .listDevices:
                url = webConfiguration.baseURL.appending(path: "api/mobile/devices")
                method = "GET"
            case .inspect:
                url = webConfiguration.baseURL.appending(path: "api/mobile/qr/inspect")
                method = "POST"
            case .reject:
                url = webConfiguration.baseURL.appending(path: "api/mobile/qr/reject")
                method = "POST"
            case .approve:
                url = webConfiguration.baseURL.appending(path: "api/mobile/qr/approve")
                method = "POST"
            case .revoke:
                url = webConfiguration.baseURL.appending(path: "api/mobile/devices/revoke")
                method = "POST"
            case .revokeAll:
                url = webConfiguration.baseURL.appending(path: "api/mobile/devices/revoke-all")
                method = "POST"
            }
        } else if let supabaseConfiguration, supabaseConfiguration.isConfigured {
            let base = supabaseConfiguration.url.appending(path: "functions/v1/web-linked-devices")
            let actionName: String
            switch endpoint {
            case .listDevices:
                actionName = "list"
                method = "GET"
            case .inspect:
                actionName = "inspect"
                method = "POST"
            case .reject:
                actionName = "reject"
                method = "POST"
            case .approve:
                actionName = "approve"
                method = "POST"
            case .revoke:
                actionName = "revoke"
                method = "POST"
            case .revokeAll:
                actionName = "revoke-all"
                method = "POST"
            }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "action", value: actionName)]
            url = components?.url ?? base
            extraHeaders["apikey"] = supabaseConfiguration.anonKey
        } else {
            throw GradeyAuthError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(gradeySession.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tokens-only-v1", forHTTPHeaderField: "x-gradey-provider-session")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if method != "GET", let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }
}

// MARK: - Repository & ViewModel

final class LinkedWebDeviceRepository {
    private let client: any LinkedWebDeviceClient
    private let authClient: any GradeyAuthClient

    init(
        client: any LinkedWebDeviceClient,
        authClient: any GradeyAuthClient
    ) {
        self.client = client
        self.authClient = authClient
    }

    func fetchDevices() async throws -> [LinkedWebDevice] {
        let session = try await authClient.validSession()
        return try await client.fetchLinkedDevices(gradeySession: session)
    }

    func inspectChallenge(_ payload: QRPairingPayload) async throws -> WebPairingChallengePreview {
        let session = try await authClient.validSession()
        return try await client.inspectChallenge(payload, gradeySession: session)
    }

    func rejectChallenge(_ payload: QRPairingPayload) async throws {
        let session = try await authClient.validSession()
        try await client.rejectChallenge(payload, gradeySession: session)
    }

    func approveChallenge(
        _ payload: QRPairingPayload,
        schoolSession: StoredSession,
        user: UserResponse?
    ) async throws -> LinkedWebDevice {
        let session = try await authClient.validSession()
        return try await client.approveChallenge(
            payload,
            schoolSession: schoolSession,
            user: user,
            gradeySession: session
        )
    }

    func revokeDevice(id: String) async throws {
        let session = try await authClient.validSession()
        try await client.revokeDevice(id: id, gradeySession: session)
    }

    func revokeAllDevices() async throws -> Int {
        let session = try await authClient.validSession()
        return try await client.revokeAllDevices(gradeySession: session)
    }
}

@MainActor
@Observable
final class LinkedDevicesViewModel {
    struct PendingApproval: Identifiable, Equatable {
        let payload: QRPairingPayload
        let preview: WebPairingChallengePreview
        var id: String { payload.challengeID }
    }

    var devices: [LinkedWebDevice] = []
    var isLoading = false
    var isInspectingQR = false
    var isApproving = false
    var revokingDeviceIDs: Set<String> = []
    var isRevokingAll = false
    var pendingApproval: PendingApproval?
    var errorMessage: String?

    private let repository: LinkedWebDeviceRepository
    private let schoolRepository: SchoolRepository

    init(
        repository: LinkedWebDeviceRepository,
        schoolRepository: SchoolRepository
    ) {
        self.repository = repository
        self.schoolRepository = schoolRepository
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            devices = try await repository.fetchDevices()
        } catch GradeyAuthError.notConfigured, AppError.notLoggedIn {
            // Leave empty when unconfigured or in guest mode.
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func handleScannedCode(_ rawCode: String) async -> Bool {
        guard let payload = QRPairingPayload(rawString: rawCode) else {
            errorMessage = LinkedWebDeviceError.invalidQRCode.errorDescription
            return false
        }
        return await inspect(payload)
    }

    @discardableResult
    func inspect(_ payload: QRPairingPayload) async -> Bool {
        errorMessage = nil
        isInspectingQR = true
        defer { isInspectingQR = false }

        do {
            let preview = try await repository.inspectChallenge(payload)
            pendingApproval = PendingApproval(payload: payload, preview: preview)
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func cancelPendingApproval() async {
        guard let current = pendingApproval else { return }
        pendingApproval = nil
        try? await repository.rejectChallenge(current.payload)
    }

    func confirmPendingApproval() async -> Bool {
        guard let current = pendingApproval else { return false }
        guard let schoolSession = try? schoolRepository.currentStoredSession() else {
            errorMessage = LinkedWebDeviceError.missingSchoolSession.errorDescription
            return false
        }

        errorMessage = nil
        isApproving = true
        defer { isApproving = false }

        do {
            let user = await schoolRepository.loadUser()
            let linked = try await repository.approveChallenge(
                current.payload,
                schoolSession: schoolSession,
                user: user
            )
            pendingApproval = nil
            devices.removeAll { $0.id == linked.id }
            devices.insert(linked, at: 0)
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func revoke(_ device: LinkedWebDevice) async {
        errorMessage = nil
        revokingDeviceIDs.insert(device.id)
        defer { revokingDeviceIDs.remove(device.id) }

        do {
            try await repository.revokeDevice(id: device.id)
            devices.removeAll { $0.id == device.id }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func revokeAll() async {
        errorMessage = nil
        isRevokingAll = true
        defer { isRevokingAll = false }

        do {
            _ = try await repository.revokeAllDevices()
            devices.removeAll()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

// MARK: - UI Test / SwiftUI Preview Mock (Never Used in Live AppEnvironment)

final class MockLinkedWebDeviceClient: LinkedWebDeviceClient {
    var devices: [LinkedWebDevice]

    init(devices: [LinkedWebDevice] = []) {
        self.devices = devices
    }

    func fetchLinkedDevices(gradeySession: GradeyAuthSession) async throws -> [LinkedWebDevice] {
        devices
    }

    func inspectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws -> WebPairingChallengePreview {
        WebPairingChallengePreview(
            challengeID: payload.challengeID,
            browserName: "Safari",
            osName: "macOS",
            deviceLabel: "Safari · macOS",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60)
        )
    }

    func rejectChallenge(_ payload: QRPairingPayload, gradeySession: GradeyAuthSession) async throws {}

    func approveChallenge(
        _ payload: QRPairingPayload,
        schoolSession: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedWebDevice {
        let now = Date()
        let created = LinkedWebDevice(
            id: payload.challengeID,
            provider: LinkedAccountProvider(schoolProvider: schoolSession.provider),
            studentName: user?.fullName ?? "Student",
            className: user?.userClass?.abbrev,
            schoolName: user?.displaySchoolName,
            browserName: "Safari",
            osName: "macOS",
            deviceLabel: "Safari · macOS",
            firstLoginAt: now,
            lastActiveAt: now,
            expiresAt: now.addingTimeInterval(30 * 86_400)
        )
        devices.insert(created, at: 0)
        return created
    }

    func revokeDevice(id: String, gradeySession: GradeyAuthSession) async throws {
        devices.removeAll { $0.id == id }
    }

    func revokeAllDevices(gradeySession: GradeyAuthSession) async throws -> Int {
        let count = devices.count
        devices.removeAll()
        return count
    }
}

// MARK: - Wire DTOs

private struct EmptyPayload: Encodable {}
private struct EmptyObjectResponse: Decodable {}

private struct DevicesListResponse: Decodable {
    let devices: [LinkedWebDevice]
}

private struct ApproveDeviceResponse: Decodable {
    let device: LinkedWebDevice
}

private struct RevokeAllResponse: Decodable {
    let revokedCount: Int
}

private struct ChallengeSecretRequest: Encodable {
    let challengeId: String
    let qrSecret: String
}

private struct RevokeSessionRequest: Encodable {
    let sessionId: String
}

private struct ApproveWebPairingRequest: Encodable {
    let challengeId: String
    let qrSecret: String
    let linkedAccountID: String?
    let provider: LinkedAccountProvider
    let providerUserID: String?
    let baseURL: URL
    let studentName: String
    let className: String?
    let schoolName: String?
    let tokenPayload: ProviderSecretSanitizer.SchoolPayload

    enum CodingKeys: String, CodingKey {
        case challengeId
        case qrSecret
        case linkedAccountID = "linked_account_id"
        case provider
        case providerUserID = "provider_user_id"
        case baseURL = "base_url"
        case studentName = "student_name"
        case className = "class_name"
        case schoolName = "school_name"
        case tokenPayload = "token_payload"
    }
}

private struct ServerErrorEnvelope: Decodable {
    let error: String?
    let message: String?
    let msg: String?

    var displayMessage: String? {
        for candidate in [error, message, msg] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
