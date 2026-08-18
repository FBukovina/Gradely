import Foundation
import Testing
@testable import Gradely

@Suite(.serialized)
struct GradeyAuthClientTests {
    @Test func appleSignInAcceptsProviderMetadataWithMixedJSONTypes() async throws {
        let urlSession = Self.makeURLSession()
        let sessionStore = InMemoryGradeyAuthSessionStore()
        let now = Date(timeIntervalSince1970: 1_752_332_400)

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseData = Data(Self.appleTokenResponse.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = SupabaseGradeyAuthClient(
            configuration: Self.supabaseConfiguration,
            sessionStore: sessionStore,
            urlSession: urlSession,
            dateProvider: { now }
        )

        let session = try await client.signInWithApple(
            identityToken: "apple-id-token",
            nonce: nil,
            fullName: nil
        )

        #expect(session.accessToken == "access-token")
        #expect(session.refreshToken == "refresh-token")
        #expect(session.expiresAt == now.addingTimeInterval(3_600))
        #expect(session.account.email == "student@example.com")
        #expect(session.account.fullName == "Stored Student")
        #expect(session.account.createdAt == Self.expectedCreatedAt)
        #expect(sessionStore.session == session)

        let request = try #require(GradeyAuthURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/auth/v1/token")
        #expect(request.url?.query == "grant_type=id_token")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sb_publishable_test")

        let requestData = try #require(GradeyAuthURLProtocol.lastRequestBody)
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        #expect(requestBody["provider"] as? String == "apple")
        #expect(requestBody["id_token"] as? String == "apple-id-token")
        #expect(requestBody["nonce"] == nil)
    }

    @Test func refreshAccountFetchesLatestProfileAndPreservesSessionTokens() async throws {
        let originalSession = Self.makeStoredSession()
        let sessionStore = InMemoryGradeyAuthSessionStore(session: originalSession)
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseData = Data(Self.refreshedUserResponse.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        let account = try await client.refreshAccount()

        #expect(account.id == originalSession.account.id)
        #expect(account.email == "fresh@example.com")
        #expect(account.fullName == "Remote Student")
        #expect(account.avatarURL == originalSession.account.avatarURL)
        #expect(account.createdAt == originalSession.account.createdAt)

        let persisted = try #require(sessionStore.session)
        #expect(persisted.account == account)
        #expect(persisted.accessToken == originalSession.accessToken)
        #expect(persisted.refreshToken == originalSession.refreshToken)
        #expect(persisted.tokenType == originalSession.tokenType)
        #expect(persisted.expiresAt == originalSession.expiresAt)

        let request = try #require(GradeyAuthURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/auth/v1/user")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer stored-access-token")
        #expect(GradeyAuthURLProtocol.lastRequestBody == nil)
    }

    @Test func updateFullNameSendsNestedMetadataAndPersistsReturnedAccount() async throws {
        let originalSession = Self.makeStoredSession()
        let sessionStore = InMemoryGradeyAuthSessionStore(session: originalSession)
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseData = Data(Self.updatedUserResponse.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        let account = try await client.updateFullName("Renamed Student")

        #expect(account.fullName == "Renamed Student")
        #expect(account.email == originalSession.account.email)

        let persisted = try #require(sessionStore.session)
        #expect(persisted.account == account)
        #expect(persisted.accessToken == originalSession.accessToken)
        #expect(persisted.refreshToken == originalSession.refreshToken)
        #expect(persisted.tokenType == originalSession.tokenType)
        #expect(persisted.expiresAt == originalSession.expiresAt)

        let request = try #require(GradeyAuthURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/auth/v1/user")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer stored-access-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")

        let requestData = try #require(GradeyAuthURLProtocol.lastRequestBody)
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let metadata = try #require(requestBody["data"] as? [String: Any])
        #expect(metadata["full_name"] as? String == "Renamed Student")
        #expect(metadata.count == 1)
    }

    @Test func updateFailureLeavesStoredSessionUntouched() async throws {
        let originalSession = Self.makeStoredSession()
        let sessionStore = InMemoryGradeyAuthSessionStore(session: originalSession)
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseStatusCode = 422
        GradeyAuthURLProtocol.responseData = Data(#"{"message":"Name rejected"}"#.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        do {
            _ = try await client.updateFullName("Rejected Name")
            #expect(Bool(false), "Expected the metadata request to fail")
        } catch {
            #expect(error as? GradeyAuthError == .server("Name rejected"))
        }

        #expect(sessionStore.session == originalSession)
    }

    @Test func mismatchedUserResponseIsRejectedWithoutReplacingStoredAccount() async throws {
        let originalSession = Self.makeStoredSession()
        let sessionStore = InMemoryGradeyAuthSessionStore(session: originalSession)
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseData = Data(Self.differentUserResponse.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        do {
            _ = try await client.refreshAccount()
            #expect(Bool(false), "Expected a different user ID to be rejected")
        } catch {
            #expect(error is GradeyAuthError)
        }

        #expect(sessionStore.session == originalSession)
    }

    @Test func sessionStoreFailureDoesNotMutateExistingSession() async throws {
        let originalSession = Self.makeStoredSession()
        let sessionStore = InMemoryGradeyAuthSessionStore(session: originalSession)
        sessionStore.saveError = TestSessionStoreError.saveFailed
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.responseData = Data(Self.updatedUserResponse.utf8)
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        do {
            _ = try await client.updateFullName("Renamed Student")
            #expect(Bool(false), "Expected the session store write to fail")
        } catch {
            #expect(error is TestSessionStoreError)
        }

        #expect(sessionStore.session == originalSession)
    }

    @Test func appleNameMetadataFailureDoesNotUndoSuccessfulSignIn() async throws {
        let sessionStore = InMemoryGradeyAuthSessionStore()
        let urlSession = Self.makeURLSession()

        GradeyAuthURLProtocol.reset()
        GradeyAuthURLProtocol.requestHandler = { request, _ in
            if request.url?.path == "/auth/v1/token" {
                return GradeyAuthStubResponse(
                    statusCode: 200,
                    data: Data(Self.appleTokenResponseWithoutName.utf8)
                )
            }
            return GradeyAuthStubResponse(
                statusCode: 503,
                data: Data(#"{"message":"Metadata service unavailable"}"#.utf8)
            )
        }
        defer { GradeyAuthURLProtocol.reset() }

        let client = Self.makeClient(sessionStore: sessionStore, urlSession: urlSession)
        let session = try await client.signInWithApple(
            identityToken: "apple-id-token",
            nonce: nil,
            fullName: "  Apple Student  "
        )

        #expect(session.accessToken == "access-token")
        #expect(session.account.fullName == "Apple Student")
        #expect(sessionStore.session == session)
        #expect(GradeyAuthURLProtocol.capturedRequests.count == 2)

        let metadataRequest = GradeyAuthURLProtocol.capturedRequests[1]
        #expect(metadataRequest.request.httpMethod == "PUT")
        #expect(metadataRequest.request.url?.path == "/auth/v1/user")
        #expect(metadataRequest.request.value(forHTTPHeaderField: "Authorization") == "bearer access-token")
        let requestData = try #require(metadataRequest.body)
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let metadata = try #require(requestBody["data"] as? [String: Any])
        #expect(metadata["full_name"] as? String == "Apple Student")
    }

    private static let supabaseConfiguration = SupabaseConfiguration(
        url: URL(string: "https://project-ref.supabase.co")!,
        anonKey: "sb_publishable_test"
    )

    private static let testNow = Date(timeIntervalSince1970: 1_752_332_400)

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GradeyAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func makeClient(
        sessionStore: InMemoryGradeyAuthSessionStore,
        urlSession: URLSession
    ) -> SupabaseGradeyAuthClient {
        SupabaseGradeyAuthClient(
            configuration: supabaseConfiguration,
            sessionStore: sessionStore,
            urlSession: urlSession,
            dateProvider: { testNow }
        )
    }

    private static func makeStoredSession() -> GradeyAuthSession {
        GradeyAuthSession(
            accessToken: "stored-access-token",
            refreshToken: "stored-refresh-token",
            tokenType: "Bearer",
            expiresAt: testNow.addingTimeInterval(3_600),
            account: GradeyAccount(
                id: "user-123",
                email: "stored@example.com",
                fullName: "Stored Student",
                avatarURL: URL(string: "https://example.com/stored-avatar.png"),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    private static let expectedCreatedAt: Date = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: "2026-07-12T15:13:23.044401Z")!
    }()

    private static let appleTokenResponse = """
    {
      "access_token": "access-token",
      "token_type": "bearer",
      "expires_in": 3600,
      "refresh_token": "refresh-token",
      "user": {
        "id": "018f08c6-98d7-7c32-87ef-89f35d3b1822",
        "email": "student@example.com",
        "created_at": "2026-07-12T15:13:23.044401Z",
        "user_metadata": {
          "full_name": "Stored Student",
          "name": { "given": "Wrong JSON type must be ignored" },
          "avatar_url": false,
          "custom_claims": { "auth_time": 1783869203 },
          "email": "student@example.com",
          "email_verified": true,
          "iss": "https://appleid.apple.com",
          "phone_verified": false,
          "provider_id": "001234.abcdef",
          "sub": "001234.abcdef"
        }
      }
    }
    """

    private static let appleTokenResponseWithoutName = """
    {
      "access_token": "access-token",
      "token_type": "bearer",
      "expires_in": 3600,
      "refresh_token": "refresh-token",
      "user": {
        "id": "user-123",
        "email": "student@example.com",
        "created_at": "2026-07-12T15:13:23.044401Z",
        "user_metadata": {
          "email_verified": true,
          "provider_id": "001234.abcdef"
        }
      }
    }
    """

    private static let refreshedUserResponse = """
    {
      "id": "user-123",
      "email": "fresh@example.com",
      "user_metadata": {
        "full_name": "  Remote Student  ",
        "avatar_url": "not an absolute URL",
        "provider_data": { "subject": "ignored" }
      }
    }
    """

    private static let updatedUserResponse = """
    {
      "id": "user-123",
      "user_metadata": {
        "full_name": "Renamed Student",
        "avatar_url": false
      }
    }
    """

    private static let differentUserResponse = """
    {
      "id": "different-user",
      "email": "attacker@example.com",
      "user_metadata": {
        "full_name": "Different User"
      }
    }
    """
}

private final class InMemoryGradeyAuthSessionStore: GradeyAuthSessionStoring {
    var session: GradeyAuthSession?
    var saveError: Error?

    init(session: GradeyAuthSession? = nil) {
        self.session = session
    }

    func loadSession() throws -> GradeyAuthSession? {
        session
    }

    func save(session: GradeyAuthSession) throws {
        if let saveError {
            throw saveError
        }
        self.session = session
    }

    func clearSession() throws {
        session = nil
    }
}

private enum TestSessionStoreError: Error {
    case saveFailed
}

private struct GradeyAuthStubResponse {
    let statusCode: Int
    let data: Data
}

private struct CapturedGradeyAuthRequest {
    let request: URLRequest
    let body: Data?
}

private final class GradeyAuthURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var responseStatusCode = 200
    nonisolated(unsafe) static var requestHandler: ((URLRequest, Data?) -> GradeyAuthStubResponse)?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var capturedRequests: [CapturedGradeyAuthRequest] = []

    static func reset() {
        responseData = nil
        responseStatusCode = 200
        requestHandler = nil
        lastRequest = nil
        lastRequestBody = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(from: request)
        Self.capturedRequests.append(
            CapturedGradeyAuthRequest(request: request, body: Self.lastRequestBody)
        )
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let stub: GradeyAuthStubResponse
        if let requestHandler = Self.requestHandler {
            stub = requestHandler(request, Self.lastRequestBody)
        } else if let responseData = Self.responseData {
            stub = GradeyAuthStubResponse(
                statusCode: Self.responseStatusCode,
                data: responseData
            )
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
