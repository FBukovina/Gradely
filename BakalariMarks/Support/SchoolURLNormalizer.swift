import Foundation

enum SchoolURLNormalizer {
    enum NormalizationError: LocalizedError, Equatable {
        case empty
        case invalid
        case insecure

        var errorDescription: String? {
            switch self {
            case .empty:
                return String(localized: "error.schoolURL.empty")
            case .invalid:
                return String(localized: "error.schoolURL.invalid")
            case .insecure:
                return String(localized: "error.schoolURL.insecure")
            }
        }
    }

    static func normalizedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NormalizationError.empty }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate), components.host != nil else {
            throw NormalizationError.invalid
        }

        guard components.scheme?.lowercased() == "https" else {
            throw NormalizationError.insecure
        }

        components.query = nil
        components.fragment = nil

        guard var url = components.url else { throw NormalizationError.invalid }
        if !url.absoluteString.hasSuffix("/") {
            url.append(path: "")
        }
        return url
    }

    static func displayString(from url: URL) -> String {
        var text = url.absoluteString
        if text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }
}
