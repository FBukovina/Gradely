import Foundation
import CryptoKit

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
            if session.provider == .eduPage {
                // A linked EduPage login can contain several children with the same
                // subject IDs. Keep their data separate without guessing old ownership.
                let components = [linkedAccountID, session.baseURL.absoluteString,
                                  session.eduPage?.userID ?? "",
                                  session.eduPage?.activeStudent == nil ? "unselected" : "student",
                                  session.eduPage?.activeStudent?.id ?? ""]
                let identity = components.map { "\($0.utf8.count):\($0)" }.joined()
                let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                self.init(rawValue: "edupage-linked-v2-\(digest)")
            } else {
                self.init(rawValue: "linked-\(linkedAccountID)")
            }
        } else {
            self.init(rawValue: session.cacheScope)
        }
    }

    func filename(prefix: String, extension fileExtension: String = "json") -> String {
        "\(prefix)-\(rawValue).\(fileExtension)"
    }
}
