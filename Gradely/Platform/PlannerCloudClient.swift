import Foundation

/// Explicit content-only wire format. Calendar permissions, event IDs and export work are device-local.
struct PlannerCloudItem: Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String?
    var type: PlannerItemType
    var subject: PlannerSubjectReference?
    var lesson: PlannerLessonReference?
    var linkedDate: Date?
    var dueDate: Date?
    var dueHasTime: Bool
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var timeZoneIdentifier: String
    var deletedAt: Date?

    init(_ item: PlannerItem) {
        id = item.id; title = item.title; notes = item.notes; type = item.type
        subject = item.subject; lesson = item.lesson; linkedDate = item.linkedDate
        dueDate = item.dueDate; dueHasTime = item.dueHasTime; isCompleted = item.isCompleted
        createdAt = item.createdAt; updatedAt = item.updatedAt
        timeZoneIdentifier = item.timeZoneIdentifier; deletedAt = item.deletedAt
    }

    func local(preserving existing: PlannerItem?) -> PlannerItem {
        var item = existing ?? PlannerItem()
        item.id = id; item.title = title; item.notes = notes; item.type = type
        item.subject = subject; item.lesson = lesson; item.linkedDate = linkedDate
        item.dueDate = dueDate; item.dueHasTime = dueHasTime; item.isCompleted = isCompleted
        item.createdAt = createdAt; item.updatedAt = updatedAt
        item.timeZoneIdentifier = timeZoneIdentifier; item.deletedAt = deletedAt
        if existing == nil { item.calendarSyncEnabled = false }
        if deletedAt != nil { item.calendarSyncEnabled = false }
        if let existing, PlannerCloudItem(existing) != self {
            item.calendarNeedsSync = existing.calendarSyncEnabled || existing.calendarEventIdentifier != nil || existing.calendarLastStart != nil
        }
        return item
    }
}

struct PlannerCloudRecord: Codable, Equatable {
    var item: PlannerCloudItem
    var revision: Int64
}
struct PlannerCloudChange: Codable, Equatable {
    var item: PlannerCloudItem
    var baseRevision: Int64
    var mutationId: UUID
}
struct PlannerCloudConflict: Codable, Equatable, Identifiable {
    var itemId: UUID
    var remote: PlannerCloudRecord?
    /// A competing local-window edit may still be queued rather than acknowledged by the server.
    var pendingAlternative: PlannerCloudChange? = nil
    var id: UUID { itemId }
}
struct PlannerCloudRequest: Codable {
    var changes: [PlannerCloudChange]
    var cursor: Int64
}
struct PlannerCloudResult: Codable {
    var items: [PlannerCloudRecord]
    var conflicts: [PlannerCloudConflict]
    var cursor: Int64
    var acceptedMutationIds: [UUID]
}

protocol PlannerCloudSyncing {
    func sync(_ request: PlannerCloudRequest, session: GradeyAuthSession) async throws -> PlannerCloudResult
}

final class SupabasePlannerCloudClient: PlannerCloudSyncing {
    private let configuration: SupabaseConfiguration?
    private let urlSession: URLSession
    init(configuration: SupabaseConfiguration? = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration; self.urlSession = urlSession
    }
    func sync(_ payload: PlannerCloudRequest, session: GradeyAuthSession) async throws -> PlannerCloudResult {
        guard let configuration, configuration.isConfigured else { throw GradeyAuthError.notConfigured }
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/planner-sync"))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(session.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try PlannerCloudCoding.encoder().encode(payload)
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw GradeyAuthError.server(AppL10n.string("planner.cloud.error"))
        }
        return try PlannerCloudCoding.decoder().decode(PlannerCloudResult.self, from: data)
    }
}

enum PlannerCloudCoding {
    /// The edge endpoint bounds the whole UTF-8 body as well as the change count.
    static func batch(_ pending: [PlannerCloudChange], cursor: Int64) throws -> [PlannerCloudChange] {
        var changes: [PlannerCloudChange] = []
        for change in pending.prefix(100) {
            if try encoder().encode(PlannerCloudRequest(changes: changes + [change], cursor: cursor)).count > 480_000 {
                guard !changes.isEmpty else { throw PlannerError.cloudContentTooLarge }
                break
            }
            changes.append(change)
        }
        return changes
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO date"))
            }
            return date
        }
        return decoder
    }
}
