import Foundation

struct SchoolDirectoryMunicipality: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let schoolCount: Int

    var id: String { name }
}

struct SchoolDirectorySchool: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let town: String
    let schoolURL: String

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTown: String {
        town.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSchoolURL: String {
        schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CachedSchoolDirectory: Codable, Equatable, Sendable {
    static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60
    static let currentFormatVersion = 2

    let schools: [SchoolDirectorySchool]
    let cachedAt: Date
    let formatVersion: Int?

    init(
        schools: [SchoolDirectorySchool],
        cachedAt: Date,
        formatVersion: Int? = Self.currentFormatVersion
    ) {
        self.schools = schools
        self.cachedAt = cachedAt
        self.formatVersion = formatVersion
    }

    var isCurrentFormat: Bool {
        formatVersion == Self.currentFormatVersion
    }

    func isStale(now: Date = Date(), maxAge: TimeInterval = Self.defaultMaxAge) -> Bool {
        now.timeIntervalSince(cachedAt) >= maxAge
    }
}
