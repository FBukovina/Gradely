import Foundation

/// Someone whose timetable you can look at next to yours. Friends live only
/// on this device: their Bakaláři login is in the Keychain, never synced.
struct Friend: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var source: FriendTimetableSource
    let addedAt: Date
}

enum FriendTimetableSource: Codable, Equatable, Hashable, Sendable {
    /// Their own Bakaláři account; the session is stored under the friend's id.
    case bakalari(schoolURL: URL, schoolName: String?, username: String)
    /// The school's public class timetable. `groups` nil means every group.
    case publicClass(schoolURL: URL, schoolName: String?, classID: String, className: String, groups: [String]?)
    /// Read from a PDF or photo; the timetable is stored with the friend.
    case imported(fileName: String?)

    var schoolName: String? {
        switch self {
        case .bakalari(let url, let name, _), .publicClass(let url, let name, _, _, _):
            name ?? url.host
        case .imported:
            nil
        }
    }

    /// One line for Settings, such as "Public timetable · 1.A".
    var summary: String {
        switch self {
        case .bakalari:
            [AppL10n.string("friends.source.bakalari"), schoolName].compactMap { $0 }.joined(separator: " · ")
        case .publicClass(_, _, _, let className, _):
            [AppL10n.string("friends.source.public"), className].joined(separator: " · ")
        case .imported(let fileName):
            [AppL10n.string("friends.source.imported"), fileName].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var supportsPermanentTimetable: Bool {
        switch self {
        case .bakalari, .publicClass: true
        case .imported: false
        }
    }
}
