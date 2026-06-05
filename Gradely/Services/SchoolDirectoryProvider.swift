import Foundation

protocol SchoolDirectoryProviding {
    func loadCachedDirectory() throws -> CachedSchoolDirectory?
    func refreshDirectory() async throws -> [SchoolDirectorySchool]
}

enum SchoolDirectoryError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
    case emptyDirectory

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "schoolDirectory.error")
        case .httpStatus:
            return String(localized: "schoolDirectory.error")
        case .decoding:
            return String(localized: "schoolDirectory.error")
        case .emptyDirectory:
            return String(localized: "schoolDirectory.error")
        }
    }
}

final class URLSessionSchoolDirectoryProvider: SchoolDirectoryProviding {
    private let urlSession: URLSession
    private let cache: any SchoolDirectoryCaching
    private let serviceURL: URL
    private let maxConcurrentTownRequests: Int

    init(
        urlSession: URLSession = .shared,
        cache: any SchoolDirectoryCaching,
        serviceURL: URL = URL(string: "https://sluzby.bakalari.cz/api/v1/municipality")!,
        maxConcurrentTownRequests: Int = 12
    ) {
        self.urlSession = urlSession
        self.cache = cache
        self.serviceURL = serviceURL
        self.maxConcurrentTownRequests = max(1, maxConcurrentTownRequests)
    }

    func loadCachedDirectory() throws -> CachedSchoolDirectory? {
        try cache.load()
    }

    func refreshDirectory() async throws -> [SchoolDirectorySchool] {
        let municipalities = try await Self.fetchMunicipalities(
            serviceURL: serviceURL,
            urlSession: urlSession
        )
        .filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.schoolCount > 0
        }

        let schools = try await Self.fetchSchools(
            for: municipalities,
            serviceURL: serviceURL,
            urlSession: urlSession,
            maxConcurrentTownRequests: maxConcurrentTownRequests
        )

        guard !schools.isEmpty else { throw SchoolDirectoryError.emptyDirectory }

        let uniqueSchools = Self.uniqueSortedSchools(schools)
        try cache.save(uniqueSchools)
        return uniqueSchools
    }

    nonisolated private static func fetchMunicipalities(
        serviceURL: URL,
        urlSession: URLSession
    ) async throws -> [SchoolDirectoryMunicipality] {
        var request = URLRequest(url: serviceURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, urlSession: urlSession)
    }

    nonisolated private static func fetchSchools(
        for municipalities: [SchoolDirectoryMunicipality],
        serviceURL: URL,
        urlSession: URLSession,
        maxConcurrentTownRequests: Int
    ) async throws -> [SchoolDirectorySchool] {
        var allSchools: [SchoolDirectorySchool] = []
        var nextIndex = 0

        await withTaskGroup(of: Result<[SchoolDirectorySchool], Error>.self) { group in
            func enqueueNextTown() {
                guard nextIndex < municipalities.count else { return }
                let townName = municipalities[nextIndex].name
                nextIndex += 1

                group.addTask {
                    do {
                        let schools = try await fetchSchools(
                            in: townName,
                            serviceURL: serviceURL,
                            urlSession: urlSession
                        )
                        return .success(schools)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for _ in 0..<min(maxConcurrentTownRequests, municipalities.count) {
                enqueueNextTown()
            }

            while let result = await group.next() {
                if case .success(let schools) = result {
                    allSchools.append(contentsOf: schools)
                }
                enqueueNextTown()
            }
        }

        return allSchools
    }

    nonisolated private static func fetchSchools(
        in townName: String,
        serviceURL: URL,
        urlSession: URLSession
    ) async throws -> [SchoolDirectorySchool] {
        guard var components = URLComponents(url: serviceURL, resolvingAgainstBaseURL: false) else {
            throw SchoolDirectoryError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "name", value: townName)]

        guard let url = components.url else {
            throw SchoolDirectoryError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: TownSchoolsResponse = try await send(request, urlSession: urlSession)
        return response.schools.compactMap { school in
            let trimmedName = school.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedURL = school.schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return nil }

            return SchoolDirectorySchool(
                id: school.id,
                name: trimmedName,
                town: response.name.trimmingCharacters(in: .whitespacesAndNewlines),
                schoolURL: trimmedURL
            )
        }
    }

    nonisolated private static func send<Response: Decodable>(
        _ request: URLRequest,
        urlSession: URLSession
    ) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SchoolDirectoryError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SchoolDirectoryError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SchoolDirectoryError.decoding(error.localizedDescription)
        }
    }

    nonisolated private static func uniqueSortedSchools(_ schools: [SchoolDirectorySchool]) -> [SchoolDirectorySchool] {
        var seenKeys = Set<String>()
        return schools
            .sorted { lhs, rhs in
                if lhs.trimmedTown.localizedCompare(rhs.trimmedTown) != .orderedSame {
                    return lhs.trimmedTown.localizedCompare(rhs.trimmedTown) == .orderedAscending
                }
                return lhs.trimmedName.localizedCompare(rhs.trimmedName) == .orderedAscending
            }
            .filter { school in
                let key = school.trimmedSchoolURL.lowercased()
                guard !seenKeys.contains(key) else { return false }
                seenKeys.insert(key)
                return true
            }
    }

    private struct TownSchoolsResponse: Decodable {
        let name: String
        let schools: [TownSchool]
    }

    private struct TownSchool: Decodable {
        let id: String
        let name: String
        let schoolURL: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case schoolURL = "schoolUrl"
        }
    }
}

final class MockSchoolDirectoryProvider: SchoolDirectoryProviding {
    var cachedDirectory: CachedSchoolDirectory?
    var refreshResult: [SchoolDirectorySchool]
    var refreshError: Error?
    private(set) var didRefresh = false

    init(
        cachedDirectory: CachedSchoolDirectory? = nil,
        refreshResult: [SchoolDirectorySchool] = [],
        refreshError: Error? = nil
    ) {
        self.cachedDirectory = cachedDirectory
        self.refreshResult = refreshResult
        self.refreshError = refreshError
    }

    func loadCachedDirectory() throws -> CachedSchoolDirectory? {
        cachedDirectory
    }

    func refreshDirectory() async throws -> [SchoolDirectorySchool] {
        didRefresh = true
        if let refreshError { throw refreshError }
        cachedDirectory = CachedSchoolDirectory(schools: refreshResult, cachedAt: Date())
        return refreshResult
    }
}
