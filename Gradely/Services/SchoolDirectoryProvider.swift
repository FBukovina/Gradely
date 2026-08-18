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
    private let requestTimeout: TimeInterval
    private let townBatchTimeout: Duration
    private let maximumTownRequestAttempts: Int

    init(
        urlSession: URLSession = .shared,
        cache: any SchoolDirectoryCaching,
        serviceURL: URL = URL(string: "https://sluzby.bakalari.cz/api/v1/municipality")!,
        maxConcurrentTownRequests: Int = 8,
        requestTimeout: TimeInterval = 12,
        townBatchTimeout: Duration = .seconds(25),
        maximumTownRequestAttempts: Int = 2
    ) {
        self.urlSession = urlSession
        self.cache = cache
        self.serviceURL = serviceURL
        self.maxConcurrentTownRequests = max(1, maxConcurrentTownRequests)
        self.requestTimeout = max(1, requestTimeout)
        self.townBatchTimeout = townBatchTimeout
        self.maximumTownRequestAttempts = max(1, maximumTownRequestAttempts)
    }

    func loadCachedDirectory() throws -> CachedSchoolDirectory? {
        try cache.load()
    }

    func refreshDirectory() async throws -> [SchoolDirectorySchool] {
        let municipalities = try await Self.fetchMunicipalities(
            serviceURL: serviceURL,
            urlSession: urlSession,
            requestTimeout: requestTimeout
        )
        .filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.schoolCount > 0
        }
        guard !municipalities.isEmpty else { throw SchoolDirectoryError.emptyDirectory }

        let batch = await Self.fetchSchools(
            for: municipalities,
            serviceURL: serviceURL,
            urlSession: urlSession,
            maxConcurrentTownRequests: maxConcurrentTownRequests,
            requestTimeout: requestTimeout,
            batchTimeout: townBatchTimeout,
            maximumAttempts: maximumTownRequestAttempts
        )

        let freshSchools = Self.uniqueSortedSchools(batch.schools)
        let cachedDirectory = try? cache.load()
        let cachedSchools = cachedDirectory?.schools ?? []
        let mergedSchools = Self.uniqueSortedSchools(cachedSchools + freshSchools)

        guard !mergedSchools.isEmpty else { throw SchoolDirectoryError.emptyDirectory }

        // A refresh may span hundreds of municipality requests. Keep useful
        // results in memory, but only replace the durable cache when the
        // response covers nearly the whole directory. Merging also prevents a
        // transient outage in one town from deleting schools we already know.
        if batch.isHealthyForCaching(hasTrustedCache: cachedDirectory?.isCurrentFormat == true) {
            try cache.save(mergedSchools)
        }
        return mergedSchools
    }

    nonisolated private static func fetchMunicipalities(
        serviceURL: URL,
        urlSession: URLSession,
        requestTimeout: TimeInterval
    ) async throws -> [SchoolDirectoryMunicipality] {
        var request = URLRequest(url: serviceURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = requestTimeout
        return try await send(request, urlSession: urlSession)
    }

    nonisolated private static func fetchSchools(
        for municipalities: [SchoolDirectoryMunicipality],
        serviceURL: URL,
        urlSession: URLSession,
        maxConcurrentTownRequests: Int,
        requestTimeout: TimeInterval,
        batchTimeout: Duration,
        maximumAttempts: Int
    ) async -> SchoolFetchBatch {
        var allSchools: [SchoolDirectorySchool] = []
        var successfulExpectedSchoolCount = 0
        var nextIndex = 0
        var completedTownCount = 0

        await withTaskGroup(of: SchoolFetchEvent.self) { group in
            func enqueueNextTown() {
                guard nextIndex < municipalities.count else { return }
                let municipality = municipalities[nextIndex]
                nextIndex += 1

                group.addTask {
                    do {
                        let schools = try await fetchSchoolsWithRetry(
                            in: municipality.name,
                            serviceURL: serviceURL,
                            urlSession: urlSession,
                            requestTimeout: requestTimeout,
                            maximumAttempts: maximumAttempts
                        )
                        return .town(TownFetchResult(
                            municipality: municipality,
                            schools: schools,
                            succeeded: true
                        ))
                    } catch {
                        return .town(TownFetchResult(
                            municipality: municipality,
                            schools: [],
                            succeeded: false
                        ))
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(for: batchTimeout)
                return .deadline
            }

            for _ in 0..<min(maxConcurrentTownRequests, municipalities.count) {
                enqueueNextTown()
            }

            fetchLoop: while let event = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break fetchLoop
                }

                switch event {
                case .deadline:
                    group.cancelAll()
                    break fetchLoop
                case .town(let result):
                    completedTownCount += 1
                    if result.succeeded {
                        successfulExpectedSchoolCount += result.municipality.schoolCount
                        allSchools.append(contentsOf: result.schools)
                    }

                    if completedTownCount == municipalities.count {
                        group.cancelAll()
                        break fetchLoop
                    }
                    enqueueNextTown()
                }
            }
        }

        return SchoolFetchBatch(
            schools: allSchools,
            expectedSchoolCount: municipalities.reduce(0) { $0 + $1.schoolCount },
            successfulExpectedSchoolCount: successfulExpectedSchoolCount
        )
    }

    nonisolated private static func fetchSchoolsWithRetry(
        in townName: String,
        serviceURL: URL,
        urlSession: URLSession,
        requestTimeout: TimeInterval,
        maximumAttempts: Int
    ) async throws -> [SchoolDirectorySchool] {
        var mostRecentError: Error?

        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()
            do {
                return try await fetchSchools(
                    in: townName,
                    serviceURL: serviceURL,
                    urlSession: urlSession,
                    requestTimeout: requestTimeout
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                mostRecentError = error
                guard attempt < maximumAttempts else { break }
                try await Task.sleep(for: .milliseconds(attempt * 250))
            }
        }

        throw mostRecentError ?? SchoolDirectoryError.invalidResponse
    }

    nonisolated private static func fetchSchools(
        in townName: String,
        serviceURL: URL,
        urlSession: URLSession,
        requestTimeout: TimeInterval
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
        request.timeoutInterval = requestTimeout

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

    private struct TownFetchResult: Sendable {
        let municipality: SchoolDirectoryMunicipality
        let schools: [SchoolDirectorySchool]
        let succeeded: Bool
    }

    private enum SchoolFetchEvent: Sendable {
        case town(TownFetchResult)
        case deadline
    }

    private struct SchoolFetchBatch: Sendable {
        let schools: [SchoolDirectorySchool]
        let expectedSchoolCount: Int
        let successfulExpectedSchoolCount: Int

        func isHealthyForCaching(hasTrustedCache: Bool) -> Bool {
            guard expectedSchoolCount > 0 else { return false }
            let expected = Double(expectedSchoolCount)
            let requestCoverage = Double(successfulExpectedSchoolCount) / expected
            let responseCoverage = Double(schools.count) / expected
            if hasTrustedCache {
                return requestCoverage >= 0.90 && responseCoverage >= 0.70
            }
            return requestCoverage >= 0.98 && responseCoverage >= 0.90
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
