import Foundation

enum SchoolDirectorySearch {
    static func results(
        for query: String,
        in schools: [SchoolDirectorySchool],
        limit: Int = 8
    ) -> [SchoolDirectorySchool] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let normalizedQuery = normalized(trimmedQuery)
        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return schools
            .compactMap { school -> (school: SchoolDirectorySchool, score: Int)? in
                guard let score = score(school, query: normalizedQuery, tokens: tokens) else {
                    return nil
                }
                return (school, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.school.trimmedTown.localizedCompare(rhs.school.trimmedTown) != .orderedSame {
                    return lhs.school.trimmedTown.localizedCompare(rhs.school.trimmedTown) == .orderedAscending
                }
                return lhs.school.trimmedName.localizedCompare(rhs.school.trimmedName) == .orderedAscending
            }
            .prefix(limit)
            .map(\.school)
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
    }

    private static func acronym(for value: String) -> String {
        normalized(value)
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private static func score(
        _ school: SchoolDirectorySchool,
        query: String,
        tokens: [String]
    ) -> Int? {
        let name = normalized(school.name)
        let town = normalized(school.town)
        let url = normalized(school.schoolURL)
        let nameAcronym = acronym(for: name)
        let searchable = [name, town, url, nameAcronym].joined(separator: " ")

        guard tokens.allSatisfy({ searchable.contains($0) }) else { return nil }

        if name == query { return 0 }
        if nameAcronym == query || nameAcronym.hasPrefix(query) { return 5 }
        if name.hasPrefix(query) { return 10 }
        if town.hasPrefix(query) { return 20 }
        if name.contains(query) { return 30 }
        if town.contains(query) { return 40 }
        if url.contains(query) { return 50 }
        return 60
    }
}
