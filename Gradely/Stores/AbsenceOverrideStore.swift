import Foundation

enum AbsenceOverrideCategory: String, Codable, CaseIterable, Identifiable {
    case unsolved, ok, missed, late, soon, school, distanceTeaching

    var id: String { rawValue }
    var contributesToBase: Bool { self == .unsolved || self == .ok || self == .missed }

    func count(in day: AbsenceDay) -> Int {
        switch self {
        case .unsolved: day.unsolved
        case .ok: day.ok
        case .missed: day.missed
        case .late: day.late
        case .soon: day.soon
        case .school: day.school
        case .distanceTeaching: day.distanceTeaching
        }
    }
}

/// One original recorded absence unit. A missing lesson is an explicit manual
/// subject allocation, not a timetable match inferred by the app.
struct AbsenceOverrideAllocation: Codable, Equatable, Identifiable {
    let id: String
    let lessonID: String?
    let subjectKey: String?
    let subjectName: String
    let lessonTitle: String
    let category: AbsenceOverrideCategory

    init(id: String = UUID().uuidString, lessonID: String? = nil, subjectKey: String? = nil,
         subjectName: String, lessonTitle: String = "", category: AbsenceOverrideCategory) {
        self.id = id
        self.lessonID = lessonID
        self.subjectKey = subjectKey
        self.subjectName = subjectName
        self.lessonTitle = lessonTitle
        self.category = category
    }
}

enum AbsenceOverridePauseReason: String, Codable, Equatable {
    case dayMissing
    case dayChanged
    case ambiguousDay
    case invalidAllocation
    case subjectMappingChanged
    case lessonMappingChanged
    case insufficientSubjectCount
}

struct AbsenceDayOverride: Codable, Equatable, Identifiable {
    let id: UUID
    let scope: SchoolDataScope
    let dateKey: String
    let baselineDay: AbsenceDay
    let allocations: [AbsenceOverrideAllocation]
    let hiddenAllocationIDs: Set<String>
    var pauseReason: AbsenceOverridePauseReason?
    let savedAt: Date

    init(id: UUID = UUID(), scope: SchoolDataScope, dateKey: String, baselineDay: AbsenceDay,
         allocations: [AbsenceOverrideAllocation], hiddenAllocationIDs: Set<String>,
         pauseReason: AbsenceOverridePauseReason? = nil, savedAt: Date = Date()) {
        self.id = id
        self.scope = scope
        self.dateKey = dateKey
        self.baselineDay = baselineDay
        self.allocations = allocations
        self.hiddenAllocationIDs = hiddenAllocationIDs
        self.pauseReason = pauseReason
        self.savedAt = savedAt
    }

    var hiddenAllocations: [AbsenceOverrideAllocation] {
        allocations.filter { hiddenAllocationIDs.contains($0.id) }
    }
    var hidesEntireDay: Bool { !allocations.isEmpty && hiddenAllocationIDs == Set(allocations.map(\.id)) }
}

struct AbsenceOverrideMetadata: Equatable {
    let activeOverrides: [AbsenceDayOverride]
    let reviewOverrides: [AbsenceDayOverride]

    init(activeOverrides: [AbsenceDayOverride] = [], reviewOverrides: [AbsenceDayOverride] = []) {
        self.activeOverrides = activeOverrides
        self.reviewOverrides = reviewOverrides
    }

    static let empty = Self(activeOverrides: [], reviewOverrides: [])
    var hiddenCount: Int { activeOverrides.reduce(0) { $0 + $1.hiddenAllocationIDs.count } }
    var hasLocalAdjustments: Bool { !activeOverrides.isEmpty }
    var hasSavedOverrides: Bool { !activeOverrides.isEmpty || !reviewOverrides.isEmpty }
}

protocol AbsenceOverrideStoring {
    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride]
    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws
    func clear(scope: SchoolDataScope) throws
    func clearAll() throws
}

enum AbsenceOverrideStoreError: LocalizedError, Equatable {
    case unavailable
    case unsupportedVersion
    case scopeMismatch
    case duplicateDay

    var errorDescription: String? {
        switch self {
        case .unavailable: AppL10n.string("absence.override.storage.unavailable")
        case .unsupportedVersion: AppL10n.string("absence.override.storage.unsupportedVersion")
        case .scopeMismatch, .duplicateDay: AppL10n.string("absence.override.storage.invalidData")
        }
    }
}

/// User edits are stored separately from disposable provider caches. Callers
/// must surface errors; a failed write must never become an in-memory success.
final class AbsenceOverrideStore: AbsenceOverrideStoring {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let prefix = "absence-overrides-v1"

    init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.directory = try directory ?? fileManager.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "Gradely", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride] {
        let url = fileURL(scope)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let payload = try decoder.decode(Payload.self, from: Data(contentsOf: url))
        guard payload.version == 1 else { throw AbsenceOverrideStoreError.unsupportedVersion }
        guard payload.scope == scope else { throw AbsenceOverrideStoreError.scopeMismatch }
        try Self.validate(payload.overrides, scope: scope)
        return payload.overrides
    }

    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws {
        try Self.validate(overrides, scope: scope)
        let payload = Payload(version: 1, scope: scope, overrides: overrides)
        let data = try encoder.encode(payload)
        try data.write(to: fileURL(scope), options: [.atomic, .completeFileProtection])
    }

    func clear(scope: SchoolDataScope) throws {
        let url = fileURL(scope)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func clearAll() throws {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in urls where url.lastPathComponent.hasPrefix(Self.prefix + "-") && url.pathExtension == "json" {
            try fileManager.removeItem(at: url)
        }
    }

    private func fileURL(_ scope: SchoolDataScope) -> URL {
        directory.appending(path: scope.filename(prefix: Self.prefix))
    }

    fileprivate static func validate(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws {
        guard overrides.allSatisfy({ $0.scope == scope }) else { throw AbsenceOverrideStoreError.scopeMismatch }
        guard Set(overrides.map(\.dateKey)).count == overrides.count,
              Set(overrides.map(\.id)).count == overrides.count else { throw AbsenceOverrideStoreError.duplicateDay }
    }

    private struct Payload: Codable {
        let version: Int
        let scope: SchoolDataScope
        let overrides: [AbsenceDayOverride]
    }
}

final class InMemoryAbsenceOverrideStore: AbsenceOverrideStoring {
    private var values: [SchoolDataScope: [AbsenceDayOverride]]

    init(overridesByScope: [SchoolDataScope: [AbsenceDayOverride]] = [:]) { values = overridesByScope }
    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride] { values[scope] ?? [] }
    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws {
        try AbsenceOverrideStore.validate(overrides, scope: scope)
        values[scope] = overrides
    }
    func clear(scope: SchoolDataScope) throws { values.removeValue(forKey: scope) }
    func clearAll() throws { values.removeAll() }
}

/// Used when durable storage cannot be initialized in a live environment.
/// Unlike an in-memory fallback it cannot falsely acknowledge a saved edit.
struct UnavailableAbsenceOverrideStore: AbsenceOverrideStoring {
    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride] { throw AbsenceOverrideStoreError.unavailable }
    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws { throw AbsenceOverrideStoreError.unavailable }
    func clear(scope: SchoolDataScope) throws { throw AbsenceOverrideStoreError.unavailable }
    func clearAll() throws { throw AbsenceOverrideStoreError.unavailable }
}
