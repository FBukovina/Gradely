import Foundation

struct AbsenceLessonSelectionScope: Codable, Equatable, Hashable {
    let baseURL: String
    let userID: String

    var storageKey: String {
        "\(Self.normalized(baseURL))__\(Self.normalized(userID))"
    }

    private static func normalized(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0).lowercased() : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")

        return normalized.isEmpty ? "unknown" : String(normalized.prefix(120))
    }
}

struct AbsenceLessonSelections: Codable, Equatable {
    var selectedLessonIDsByDate: [String: [String]]

    static let empty = AbsenceLessonSelections(selectedLessonIDsByDate: [:])

    func selectedLessonIDs(for dateKey: String) -> Set<String> {
        Set(selectedLessonIDsByDate[dateKey] ?? [])
    }
}

protocol AbsenceLessonSelectionStoring {
    func load(scope: AbsenceLessonSelectionScope) throws -> AbsenceLessonSelections
    func save(_ selections: AbsenceLessonSelections, scope: AbsenceLessonSelectionScope) throws
    func clear(scope: AbsenceLessonSelectionScope) throws
    func clearAll() throws
}

final class AbsenceLessonSelectionStore: AbsenceLessonSelectionStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) throws {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "Gradely", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appending(path: "absence-lesson-selections.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(scope: AbsenceLessonSelectionScope) throws -> AbsenceLessonSelections {
        let payload = try loadPayload()
        return payload.entries[scope.storageKey] ?? .empty
    }

    func save(_ selections: AbsenceLessonSelections, scope: AbsenceLessonSelectionScope) throws {
        var payload = try loadPayload()
        payload.entries[scope.storageKey] = selections
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear(scope: AbsenceLessonSelectionScope) throws {
        var payload = try loadPayload()
        payload.entries.removeValue(forKey: scope.storageKey)
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clearAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func loadPayload() throws -> Payload {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Payload(entries: [:])
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Payload.self, from: data)
    }

    private struct Payload: Codable {
        var entries: [String: AbsenceLessonSelections]
    }
}

final class InMemoryAbsenceLessonSelectionStore: AbsenceLessonSelectionStoring {
    private var selectionsByScope: [String: AbsenceLessonSelections]

    init(selectionsByScope: [String: AbsenceLessonSelections] = [:]) {
        self.selectionsByScope = selectionsByScope
    }

    func load(scope: AbsenceLessonSelectionScope) throws -> AbsenceLessonSelections {
        selectionsByScope[scope.storageKey] ?? .empty
    }

    func save(_ selections: AbsenceLessonSelections, scope: AbsenceLessonSelectionScope) throws {
        selectionsByScope[scope.storageKey] = selections
    }

    func clear(scope: AbsenceLessonSelectionScope) throws {
        selectionsByScope.removeValue(forKey: scope.storageKey)
    }

    func clearAll() throws {
        selectionsByScope = [:]
    }
}
