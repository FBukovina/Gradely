import Foundation
import Testing
@testable import Gradely

@MainActor
struct SchoolDirectoryTests {
    @Test func providerDecodesMunicipalityAndSchoolPayloads() async throws {
        let serviceURL = URL(string: "https://example.test/api/v1/municipality")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SchoolDirectoryURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        SchoolDirectoryURLProtocol.responses = [
            "https://example.test/api/v1/municipality": """
            [
              { "name": "", "schoolCount": 13 },
              { "name": "Praha", "schoolCount": 1 },
              { "name": "Brno", "schoolCount": 1 }
            ]
            """,
            "https://example.test/api/v1/municipality?name=Praha": """
            {
              "name": "Praha",
              "schools": [
                {
                  "id": "demo",
                  "name": "Demo Gymnázium",
                  "schoolUrl": "https://demo.bakalari.cz"
                }
              ]
            }
            """,
            "https://example.test/api/v1/municipality?name=Brno": """
            {
              "name": "Brno",
              "schools": [
                {
                  "id": "future",
                  "name": "Future School",
                  "schoolUrl": "https://future.bakalari.cz"
                }
              ]
            }
            """
        ].compactMapValues { $0.data(using: .utf8) }

        let cache = InMemorySchoolDirectoryCache()
        let provider = URLSessionSchoolDirectoryProvider(
            urlSession: urlSession,
            cache: cache,
            serviceURL: serviceURL,
            maxConcurrentTownRequests: 1
        )

        let schools = try await provider.refreshDirectory()

        #expect(schools.count == 2)
        #expect(schools.contains {
            $0.id == "demo"
                && $0.name == "Demo Gymnázium"
                && $0.town == "Praha"
                && $0.schoolURL == "https://demo.bakalari.cz"
        })
        #expect(try cache.load()?.schools == schools)
    }

    @Test func schoolDirectoryCacheSavesLoadsAndReportsStaleData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = try SchoolDirectoryCache(directory: directory)
        let cachedAt = Date(timeIntervalSince1970: 1_800_000_000)

        try cache.save(PreviewData.schoolDirectorySchools, cachedAt: cachedAt)

        let loaded = try #require(try cache.load())
        #expect(loaded.schools == PreviewData.schoolDirectorySchools)
        #expect(!loaded.isStale(now: cachedAt.addingTimeInterval(CachedSchoolDirectory.defaultMaxAge - 1)))
        #expect(loaded.isStale(now: cachedAt.addingTimeInterval(CachedSchoolDirectory.defaultMaxAge + 1)))

        try cache.clear()
        #expect((try? cache.load()) == nil)
    }

    @Test func searchMatchesCaseAndDiacriticsAndRanksSchoolNamesFirst() {
        let schools = [
            SchoolDirectorySchool(
                id: "omska",
                name: "Gymnázium Praha 10, Omská",
                town: "Praha",
                schoolURL: "https://bakalari.omska.cz"
            ),
            SchoolDirectorySchool(
                id: "eden",
                name: "Základní škola Eden",
                town: "Praha",
                schoolURL: "https://zseden.bakalari.cz"
            ),
            SchoolDirectorySchool(
                id: "brno",
                name: "Střední škola Brno",
                town: "Brno",
                schoolURL: "https://gymnazium.example.cz"
            )
        ]

        let gymnasiumResults = SchoolDirectorySearch.results(for: "gymnazium", in: schools)
        #expect(gymnasiumResults.first?.id == "omska")

        let multiTokenResults = SchoolDirectorySearch.results(for: "praha eden", in: schools)
        #expect(multiTokenResults.map(\.id) == ["eden"])

        let urlResults = SchoolDirectorySearch.results(for: "zseden", in: schools)
        #expect(urlResults.map(\.id) == ["eden"])
    }

    @Test func loginViewModelSelectsSchoolAndKeepsManualFallbackWhenRefreshFails() async {
        let cachedDirectory = CachedSchoolDirectory(
            schools: PreviewData.schoolDirectorySchools,
            cachedAt: Date().addingTimeInterval(-CachedSchoolDirectory.defaultMaxAge - 10)
        )
        let provider = MockSchoolDirectoryProvider(
            cachedDirectory: cachedDirectory,
            refreshError: SchoolDirectoryError.invalidResponse
        )
        let store = InMemorySessionStore()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: store,
            marksCache: InMemoryMarksCache()
        )
        let viewModel = LoginViewModel(repository: repository, schoolDirectoryProvider: provider)

        await viewModel.loadSchoolDirectoryIfNeeded()

        #expect(provider.didRefresh)
        #expect(viewModel.directorySchools == PreviewData.schoolDirectorySchools)
        #expect(viewModel.schoolLookupErrorMessage == nil)

        viewModel.updateSchoolSearch("demo")
        let selectedSchool = viewModel.schoolSearchResults[0]
        viewModel.selectSchool(selectedSchool)

        #expect(viewModel.schoolURL == "https://demo.bakalari.cz")
        #expect(viewModel.schoolSearchText == "Demo Gymnazium")

        viewModel.schoolURL = "demo.bakalari.cz"
        viewModel.username = "student"
        viewModel.password = "secret"

        let didLogin = await viewModel.login()

        #expect(didLogin)
        #expect(store.session?.baseURL.absoluteString == "https://demo.bakalari.cz/")
    }
}

private final class SchoolDirectoryURLProtocol: URLProtocol {
    static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: SchoolDirectoryError.invalidResponse)
            return
        }

        let data = Self.responses[url.absoluteString] ?? Data()
        let statusCode = Self.responses[url.absoluteString] == nil ? 404 : 200
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
