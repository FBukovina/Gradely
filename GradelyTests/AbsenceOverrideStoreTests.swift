import Foundation
import Testing
@testable import Gradely

struct AbsenceOverrideStoreTests {
    @Test func diskRoundTripPreservesScopedEditsAndPausedStatusAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstScope = SchoolDataScope(rawValue: "student-one"), secondScope = SchoolDataScope(rawValue: "student-two")
        let original = entry(scope: firstScope, pauseReason: .dayChanged)
        let store = try AbsenceOverrideStore(directory: directory)
        try store.save([original], scope: firstScope)
        let reopened = try AbsenceOverrideStore(directory: directory)
        #expect(try reopened.load(scope: firstScope) == [original])
        #expect(try reopened.load(scope: secondScope).isEmpty)
        try reopened.save([entry(scope: secondScope)], scope: secondScope)
        try reopened.clear(scope: firstScope)
        #expect(try reopened.load(scope: firstScope).isEmpty)
        #expect(try reopened.load(scope: secondScope).count == 1)
    }

    @Test func wrongScopeAndDuplicateDaysAreRejectedBeforeReplacingSavedData() throws {
        let scope = SchoolDataScope(rawValue: "student-one"), other = SchoolDataScope(rawValue: "student-two")
        let store = InMemoryAbsenceOverrideStore()
        let saved = entry(scope: scope)
        try store.save([saved], scope: scope)
        #expect(throws: AbsenceOverrideStoreError.scopeMismatch) { try store.save([entry(scope: other)], scope: scope) }
        #expect(throws: AbsenceOverrideStoreError.duplicateDay) { try store.save([saved, saved], scope: scope) }
        #expect(try store.load(scope: scope) == [saved])
    }

    @Test func futureVersionAndCorruptPayloadDoNotSilentlyBecomeEmptyEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = SchoolDataScope(rawValue: "student-one")
        let store = try AbsenceOverrideStore(directory: directory)
        try store.save([entry(scope: scope)], scope: scope)
        let url = directory.appending(path: scope.filename(prefix: "absence-overrides-v1"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = 2
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(throws: AbsenceOverrideStoreError.unsupportedVersion) { try store.load(scope: scope) }
        try Data("not-json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try store.load(scope: scope) }
    }

    @Test func failedDurableWriteAndUnavailableStoreNeverAcknowledgeVolatileSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = SchoolDataScope(rawValue: "student-one")
        let store = try AbsenceOverrideStore(directory: directory)
        try FileManager.default.removeItem(at: directory)
        try Data("blocks directory".utf8).write(to: directory)
        #expect(throws: (any Error).self) { try store.save([entry(scope: scope)], scope: scope) }
        #expect(throws: AbsenceOverrideStoreError.unavailable) { try UnavailableAbsenceOverrideStore().save([entry(scope: scope)], scope: scope) }
        #expect(throws: AbsenceOverrideStoreError.unavailable) { try UnavailableAbsenceOverrideStore().load(scope: scope) }
    }

    @Test func clearingEditsLeavesOtherLocalFilesIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = SchoolDataScope(rawValue: "student-one")
        let store = try AbsenceOverrideStore(directory: directory)
        let other = directory.appending(path: "absence-cache.json")
        try Data("provider-data".utf8).write(to: other)
        try store.save([entry(scope: scope)], scope: scope)
        try store.clearAll()
        #expect(try store.load(scope: scope).isEmpty)
        #expect(try String(contentsOf: other, encoding: .utf8) == "provider-data")
    }

    private func entry(scope: SchoolDataScope, pauseReason: AbsenceOverridePauseReason? = nil) -> AbsenceDayOverride {
        AbsenceDayOverride(scope: scope, dateKey: "2026-02-02",
            baselineDay: AbsenceDay(date: "2026-02-02", unsolved: 0, ok: 1, missed: 0, late: 0, soon: 0, school: 0, distanceTeaching: 0),
            allocations: [AbsenceOverrideAllocation(id: "one", subjectName: "Matematika", category: .ok)],
            hiddenAllocationIDs: ["one"], pauseReason: pauseReason)
    }
}
