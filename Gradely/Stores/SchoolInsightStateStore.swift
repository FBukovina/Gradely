import Foundation
import CryptoKit

/// Local observation sidecar. Cached hydration establishes continuity; only a successful refresh
/// may create observations. Personal Planner storage is deliberately independent of this file.
@MainActor
final class SchoolInsightStateStore {
    private struct SubjectBaseline: Codable {
        let revision: String
        let average: Double?
        let observedAt: Date
        let marks: [String: String]
        let stableMarkIDs: Set<String>
        let averageBasis: String
        let weightSignatures: [String: String]
    }
    private struct State: Codable {
        var version = 3
        var scope: SchoolDataScope
        var subjects: [String: SubjectBaseline] = [:]
        var observations: [SchoolGradeObservation] = []
    }
    private let directory: URL
    private var states: [SchoolDataScope: State] = [:]
    private(set) var persistenceError: String?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Gradely", directoryHint: .isDirectory)
    }

    /// Call once when installing a scoped cached snapshot, never for subsequent UI rerenders.
    @discardableResult
    func activate(subjects: [Subject], scope: SchoolDataScope, fetchedAt: Date?,
                  preparedCalculations: [String: PreparedGradeCalculation] = [:], now: Date = Date()) -> [SchoolGradeObservation] {
        var state = load(scope: scope)
        let current = baselines(subjects, at: fetchedAt ?? now, prepared: preparedCalculations)
        let matches = state.subjects.count == current.count && current.allSatisfy { id, value in
            state.subjects[id]?.revision == value.revision && state.subjects[id]?.averageBasis == value.averageBasis
                && state.subjects[id]?.weightSignatures == value.weightSignatures
        }
        if !matches || fetchedAt == nil {
            // A sidecar cannot prove changes across a cache clear, failed write or older restore.
            state.subjects = fetchedAt == nil ? [:] : current
            state.observations = []
        }
        prune(&state, now: now)
        commit(state)
        return state.observations
    }

    /// Each successful response advances the baseline even if no notification-worthy change exists.
    @discardableResult
    func observe(subjects: [Subject], scope: SchoolDataScope, fetchedAt: Date,
                 preparedCalculations: [String: PreparedGradeCalculation] = [:]) -> [SchoolGradeObservation] {
        var state = load(scope: scope)
        if let latest = state.subjects.values.map(\.observedAt).max(), fetchedAt < latest {
            return state.observations
        }
        let current = baselines(subjects, at: fetchedAt, prepared: preparedCalculations)
        for removedID in Set(state.subjects.keys).subtracting(current.keys) {
            state.observations.removeAll { $0.subjectID == removedID }
        }
        for (subjectID, next) in current {
            guard let previous = state.subjects[subjectID] else { continue }
            // Reject an older in-flight response rather than rewinding continuity.
            guard fetchedAt >= previous.observedAt else { continue }
            let removed = Set(previous.marks.keys).subtracting(next.marks.keys)
            let existingIDs = Set(previous.marks.keys).intersection(next.marks.keys)
            let assumptionsChanged = previous.averageBasis != next.averageBasis || existingIDs.contains {
                let oldWeight = previous.weightSignatures[$0]
                let newWeight = next.weightSignatures[$0]
                // Editing an explicit school weight is an observed edit, not an inference change.
                if oldWeight?.hasSuffix(":explicit") == true && newWeight?.hasSuffix(":explicit") == true { return false }
                return oldWeight != newWeight
            }
            if !removed.isEmpty || assumptionsChanged || (next.marks.isEmpty && !previous.marks.isEmpty) {
                state.observations.removeAll { $0.subjectID == subjectID }
                continue
            }
            guard previous.revision != next.revision else { continue }
            let added = next.stableMarkIDs.subtracting(previous.marks.keys).sorted()
            let edited = next.marks.keys.filter {
                previous.marks[$0] != nil && previous.marks[$0] != next.marks[$0]
            }.sorted()
            guard previous.average != next.average || !added.isEmpty || !edited.isEmpty else { continue }
            let observation = SchoolGradeObservation(
                id: Self.digest([scope.rawValue, subjectID, previous.revision, next.revision, String(fetchedAt.timeIntervalSince1970)]),
                scope: scope, subjectID: subjectID, observedAt: fetchedAt, previousObservedAt: previous.observedAt,
                previousAverage: previous.average, average: next.average,
                addedMarkIDs: added, editedMarkIDs: edited, digest: next.revision, seenAt: nil
            )
            state.observations.append(observation)
        }
        // Retain the most recent baseline if callers race or a clock moves backward.
        state.subjects = current.mapValues { $0 }
        for (subjectID, previous) in load(scope: scope).subjects where previous.observedAt > fetchedAt {
            state.subjects[subjectID] = previous
        }
        prune(&state, now: fetchedAt)
        commit(state)
        return state.observations
    }

    func observations(scope: SchoolDataScope, now: Date = Date()) -> [SchoolGradeObservation] {
        var state = load(scope: scope)
        prune(&state, now: now)
        states[scope] = state
        return state.observations
    }

    func markSeen(_ observationIDs: [String], scope: SchoolDataScope, at date: Date = Date()) {
        guard !observationIDs.isEmpty else { return }
        var state = load(scope: scope)
        let ids = Set(observationIDs)
        for index in state.observations.indices where ids.contains(state.observations[index].id) {
            if state.observations[index].seenAt == nil { state.observations[index].seenAt = date }
        }
        prune(&state, now: date)
        commit(state)
    }

    func clear(scope: SchoolDataScope) {
        states[scope] = nil
        do {
            let url = fileURL(scope)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    func clearAll() {
        states.removeAll()
        do {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.lastPathComponent.hasPrefix("school-insight-state-v1-") && file.pathExtension == "json" {
                try FileManager.default.removeItem(at: file)
            }
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    private func baselines(_ subjects: [Subject], at date: Date,
                           prepared: [String: PreparedGradeCalculation]) -> [String: SubjectBaseline] {
        var result: [String: SubjectBaseline] = [:]
        let grouped = Dictionary(grouping: subjects, by: \.id)
        for (id, group) in grouped where group.count == 1 {
            let subject = group[0]
            let calculation = prepared[id] ?? GradeMath.prepare(subject)
            // No attribution, including average changes, can cross an ambiguous identity snapshot.
            guard !calculation.issues.contains(.conflictingDuplicateIDs) else { continue }
            var marks: [String: String] = [:]
            var stableIDs: Set<String> = []
            for (markID, values) in Dictionary(grouping: subject.marks, by: \.id) {
                guard let mark = values.first,
                      Set(values.map { GradeMath.revision(for: $0) }).count == 1 else { continue }
                // Use the calculation's canonical comparison: read flags and bookkeeping
                // changes cannot make an otherwise identical duplicate disappear/reappear.
                marks[markID] = GradeMath.revision(for: mark)
                if mark.hasStableProviderID { stableIDs.insert(markID) }
            }
            let average = calculation.confidence == .unavailable ? nil : calculation.displayAverage.flatMap { $0.isFinite ? $0 : nil }
            let basis = average == nil ? "unavailable" : (calculation.officialAverage != nil ? "provider" : "reconstructed")
            let weightSignatures = calculation.resolvedWeights.mapValues { "\($0.value):\(String(describing: $0.source))" }
            result[id] = SubjectBaseline(revision: calculation.revision, average: average,
                observedAt: date, marks: marks, stableMarkIDs: stableIDs,
                averageBasis: basis, weightSignatures: weightSignatures)
        }
        return result
    }

    private func load(scope: SchoolDataScope) -> State {
        if let state = states[scope] { return state }
        do {
            let data = try Data(contentsOf: fileURL(scope))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(State.self, from: data)
            guard state.version == 3, state.scope == scope,
                  Set(state.observations.map(\.id)).count == state.observations.count else {
                throw CocoaError(.coderReadCorrupt)
            }
            states[scope] = state
            return state
        } catch {
            // This is reconstructible derived data; a failed decode starts a quiet baseline.
            let empty = State(scope: scope)
            states[scope] = empty
            return empty
        }
    }

    private func commit(_ state: State) {
        states[state.scope] = state
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: fileURL(state.scope), options: [.atomic, .completeFileProtection])
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    private func prune(_ state: inout State, now: Date) {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        state.observations = Array(state.observations.filter {
            $0.observedAt >= cutoff && $0.observedAt <= now && $0.scope == state.scope
        }.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.id < $1.id
        }.prefix(100))
    }

    private func fileURL(_ scope: SchoolDataScope) -> URL {
        directory.appending(path: scope.filename(prefix: "school-insight-state-v1"))
    }

    private static func digest(_ components: [String]) -> String {
        let data = (try? JSONEncoder().encode(components)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
