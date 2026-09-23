import Foundation
import Testing
@testable import Gradely

@Suite(.serialized)
struct ProviderPasswordPrivacyTests {
    @Test(arguments: [false, true])
    func linkingSendsPasswordOnlyToSchoolAndUploadsIndependentTokens(relink: Bool) async throws {
        let client = makeClient()
        defer { ProviderPrivacyURLProtocol.reset() }
        let local = localSession()

        _ = try await link(client, session: local, relink: relink)

        let requests = ProviderPrivacyURLProtocol.requests
        #expect(requests.count == 2)
        let school = try #require(requests.first)
        #expect(school.request.url?.host == "school.example")
        #expect(school.request.url?.path == "/api/login")
        #expect(school.request.value(forHTTPHeaderField: "Authorization") == nil)
        let form = String(decoding: school.body, as: UTF8.self)
        #expect(form.contains("password=school-only-password"))
        let cloud = try #require(requests.last)
        #expect(cloud.request.url?.host == "gradey.example")
        #expect(cloud.request.value(forHTTPHeaderField: "x-gradey-provider-session") == "tokens-only-v1")
        #expect(cloud.request.url?.path == "/functions/v1/\(relink ? "relink-school-account" : "link-school-account")")
        let body = try #require(JSONSerialization.jsonObject(with: cloud.body) as? [String: Any])
        let payload = try #require(body["token_payload"] as? [String: Any])
        #expect(payload["bakalari"] == nil)
        #expect(payload["password"] == nil)
        #expect(payload["accessToken"] as? String == "cloud-access")
        #expect(payload["refreshToken"] as? String == "cloud-refresh")
        #expect(payload["pollingSessionEstablishedAt"] as? String == "2026-09-07T12:00:00Z")
        let json = String(decoding: cloud.body, as: UTF8.self)
        #expect(!json.contains("school-only-password"))
        #expect(!json.contains("device-refresh"))
        #expect(!json.contains("device-access"))
        #expect(local.refreshToken == "device-refresh")
    }

    @Test(arguments: [false, true])
    func missingLocalPasswordRequiresSignInWithoutUploadingDeviceTokens(relink: Bool) async throws {
        let client = makeClient()
        defer { ProviderPrivacyURLProtocol.reset() }
        var session = localSession()
        session.bakalari = nil
        await #expect(throws: SchoolAuthenticationError.deviceSignInRequired) {
            try await link(client, session: session, relink: relink)
        }
        #expect(ProviderPrivacyURLProtocol.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func failedSchoolLoginNeverFallsBackToUploadingPasswordOrDeviceTokens(relink: Bool) async throws {
        let client = makeClient()
        defer { ProviderPrivacyURLProtocol.reset() }
        ProviderPrivacyURLProtocol.schoolStatus = 401
        await #expect(throws: (any Error).self) {
            try await link(client, session: localSession(), relink: relink)
        }
        #expect(ProviderPrivacyURLProtocol.requests.count == 1)
        #expect(ProviderPrivacyURLProtocol.requests.first?.request.url?.host == "school.example")
    }

    @Test func schoolMustReturnAnIndependentRefreshToken() async throws {
        let client = makeClient()
        defer { ProviderPrivacyURLProtocol.reset() }
        ProviderPrivacyURLProtocol.schoolRefreshToken = "device-refresh"
        await #expect(throws: SchoolAuthenticationError.deviceSignInRequired) {
            try await link(client, session: localSession(), relink: false)
        }
        #expect(ProviderPrivacyURLProtocol.requests.count == 1)
    }

    @Test func activationIgnoresLegacyBackendPasswordsAndRefreshTokens() throws {
        let data = Data("""
        {"provider":"bakalari","baseURL":"https://school.example/","accessToken":"cloud-access",
        "refreshToken":"cloud-refresh","tokenType":"Bearer","expiresAt":"2026-09-07T13:00:00Z",
        "bakalari":{"username":"student","password":"legacy-cloud-password"}}
        """.utf8)
        let payload = try JSONDecoder.sessionDecoder.decode(ProviderSecretSanitizer.SchoolPayload.self, from: data)
        let activation = LinkedSchoolAccountActivation(account: PreviewData.linkedSchoolAccount, tokenPayload: payload)
        #expect(activation.makeStoredSession().bakalari == nil)
        #expect(activation.makeStoredSession().refreshToken.isEmpty)
        let encoded = String(decoding: try JSONEncoder.sessionEncoder.encode(payload), as: UTF8.self)
        #expect(!encoded.contains("legacy-cloud-password"))
    }

    private func makeClient() -> SupabaseLinkedAccountClient {
        ProviderPrivacyURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderPrivacyURLProtocol.self]
        return SupabaseLinkedAccountClient(
            configuration: SupabaseConfiguration(url: URL(string: "https://gradey.example/")!, anonKey: "sb_publishable_test"),
            urlSession: URLSession(configuration: configuration),
            dateProvider: { Date(timeIntervalSince1970: 1_788_782_400) }
        )
    }

    private func localSession() -> StoredSession {
        StoredSession(
            accessToken: "device-access", refreshToken: "device-refresh", tokenType: "Bearer",
            expiresAt: .distantFuture, baseURL: URL(string: "https://school.example/")!,
            bakalari: BakalariCredentials(username: "student", password: "school-only-password")
        )
    }

    private func link(_ client: SupabaseLinkedAccountClient, session: StoredSession, relink: Bool) async throws -> LinkedAccount {
        if relink {
            return try await client.relinkSchoolAccount(id: "school", session: session, user: nil, gradeySession: PreviewData.gradeyAuthSession)
        }
        return try await client.linkSchoolAccount(session: session, user: nil, gradeySession: PreviewData.gradeyAuthSession)
    }
}

private final class ProviderPrivacyURLProtocol: URLProtocol {
    struct CapturedRequest {
        let request: URLRequest
        let body: Data
    }
    nonisolated(unsafe) static var requests: [CapturedRequest] = []
    nonisolated(unsafe) static var schoolStatus = 200
    nonisolated(unsafe) static var schoolRefreshToken = "cloud-refresh"

    static func reset() {
        requests = []
        schoolStatus = 200
        schoolRefreshToken = "cloud-refresh"
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.requests.append(CapturedRequest(request: request, body: body))
        let isSchool = request.url?.host == "school.example"
        let responseBody: Data
        if isSchool {
            responseBody = Data("""
            {"access_token":"cloud-access","refresh_token":"\(Self.schoolRefreshToken)","token_type":"Bearer","expires_in":3600}
            """.utf8)
        } else {
            responseBody = try! JSONEncoder.sessionEncoder.encode(PreviewData.linkedSchoolAccount)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: isSchool ? Self.schoolStatus : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
}
