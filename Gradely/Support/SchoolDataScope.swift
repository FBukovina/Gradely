import Foundation

struct SchoolDataScope: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    static let legacy = SchoolDataScope(rawValue: "legacy")

    init(rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0).lowercased() : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")

        self.rawValue = normalized.isEmpty ? "legacy" : String(normalized.prefix(160))
    }

    init(session: StoredSession) {
        if let linkedAccountID = session.linkedAccountID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !linkedAccountID.isEmpty {
            self.init(rawValue: "linked-\(linkedAccountID)")
        } else {
            self.init(rawValue: session.cacheScope)
        }
    }

    func filename(prefix: String, extension fileExtension: String = "json") -> String {
        "\(prefix)-\(rawValue).\(fileExtension)"
    }
}
