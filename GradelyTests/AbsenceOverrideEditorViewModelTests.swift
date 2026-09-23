import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsenceOverrideEditorViewModelTests {
    @Test func mixedCategoriesRequireExplicitAllocationBeforeHidingWholeDay() {
        let day = day(ok: 1, late: 1)
        let editor = editor(day: day, lessons: [lesson(1), lesson(2)])
        editor.originalLessonIDs = Set(editor.context!.lessons.map(\.id))
        editor.confirmOriginalLessons()
        editor.hideEntireDay()

        #expect(editor.allocations.allSatisfy { $0.category == nil })
        #expect(!editor.canSave)
        editor.allocations[0].category = .ok
        editor.allocations[1].category = .ok
        #expect(!editor.canSave)
        editor.allocations[1].category = .late
        #expect(editor.canSave)
        #expect(editor.resultingCount == 0)
    }

    @Test func unresolvedPartialDayRequiresOriginalSelectionBeforeHiding() {
        let editor = editor(day: day(ok: 1), lessons: [lesson(1), lesson(2)])
        editor.hideEntireDay()
        #expect(!editor.hasOriginalSelection)
        #expect(!editor.canSave)

        editor.toggleOriginalLesson(lesson(2).id)
        editor.confirmOriginalLessons()
        editor.hideEntireDay()
        #expect(editor.allocations.map(\.lessonID) == [lesson(2).id])
        #expect(editor.canSave)
    }

    @Test func hidingOneOfSixKeepsAllOriginalAssignments() {
        let editor = editor(day: day(ok: 6), lessons: (1...6).map(lesson))
        editor.originalLessonIDs = Set(editor.context!.lessons.map(\.id))
        editor.confirmOriginalLessons()
        editor.allocations[0].isHidden = true

        #expect(editor.canSave)
        #expect(editor.allocations.count == 6)
        #expect(editor.resultingCount == 5)
        #expect(editor.allocations.filter { !$0.isHidden }.count == 5)
    }

    @Test func manualFallbackPreservesEveryCategoryAndRequiresSubjects() {
        let editor = editor(day: day(ok: 2, late: 1), lessons: [])
        editor.useManualAllocations()
        editor.hideEntireDay()
        #expect(editor.allocations.count == 3)
        #expect(editor.allocations.filter { $0.category == .ok }.count == 2)
        #expect(editor.allocations.filter { $0.category == .late }.count == 1)
        #expect(!editor.canSave)
        for index in editor.allocations.indices { editor.allocations[index].subjectName = "Mathematics" }
        #expect(editor.canSave)
    }

    @Test func ambiguousSubjectNamesAreNotPrefilled() {
        let editor = editor(day: day(ok: 1), lessons: [lesson(1)], subjects: [
            .init(id: "a", subjectKey: "raw-a", subjectName: "Mathematics"),
            .init(id: "b", subjectKey: "raw-b", subjectName: "Mathematics")
        ])
        editor.originalLessonIDs = [lesson(1).id]
        editor.confirmOriginalLessons()
        editor.hideEntireDay()
        #expect(editor.allocations[0].subjectName.isEmpty)
        #expect(!editor.canSave)
    }

    @Test func onlyHiddenUnitsRequireUniqueOfficialSubjectTotals() {
        let official = AbsencePerSubject(subjectName: "Mathematics", lessonsCount: 10, base: 1, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        let biology = AbsenceLessonCandidate(id: "biology", dateKey: "2026-02-02", hourID: 2,
            hourCaption: "2", timeRange: "", subjectKey: "raw-bio", subjectName: "Biology")
        let editor = editor(day: day(ok: 2), lessons: [lesson(1), biology], subjects: [
            .init(id: "math", subjectKey: "raw-math", subjectName: "Mathematics"),
            .init(id: "bio", subjectKey: "raw-bio", subjectName: "Biology")
        ], officialSubjects: [official])
        editor.originalLessonIDs = Set(editor.context!.lessons.map(\.id))
        editor.confirmOriginalLessons()
        editor.allocations[0].isHidden = true
        #expect(editor.canSave)
        #expect(editor.hiddenSubjectMappingError == nil)

        editor.allocations[1].isHidden = true
        #expect(!editor.canSave)
        #expect(editor.hiddenSubjectMappingError?.contains("Biology") == true)
    }

    @Test func ambiguousOfficialTotalsDisableSavingWithSpecificMappingMessage() {
        let official = AbsencePerSubject(subjectName: "Mathematics", lessonsCount: 10, base: 1, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        let editor = editor(day: day(ok: 1), lessons: [lesson(1)], officialSubjects: [official, official])
        editor.originalLessonIDs = [lesson(1).id]
        editor.confirmOriginalLessons()
        editor.hideEntireDay()
        #expect(!editor.canSave)
        #expect(editor.hiddenSubjectMappingError?.contains("Mathematics") == true)
    }

    @Test func failedDurableSaveKeepsDraftAndDoesNotReportSuccess() async throws {
        let absence = AbsenceResponse(percentageThreshold: 25, absences: [day(ok: 1)], absencesPerSubject: [
            AbsencePerSubject(subjectName: "Mathematics", lessonsCount: 10, base: 1, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        ])
        let repository = repository(absence: absence, store: FailingOverrideSaveStore())
        _ = try await repository.loadAbsence(forceRefresh: true)
        var savedCallback = false
        let editor = AbsenceOverrideEditorViewModel(dateKey: "2026-02-02", repository: repository, user: nil) { _ in savedCallback = true }
        await editor.load()
        editor.useManualAllocations()
        editor.allocations[0].subjectName = "Mathematics"
        editor.hideEntireDay()
        let draft = editor.allocations
        #expect(editor.canSave)

        await editor.save()

        #expect(!editor.didSave)
        #expect(!savedCallback)
        #expect(editor.errorMessage == CocoaError(.fileWriteNoPermission).localizedDescription)
        #expect(editor.allocations == draft)
        #expect(editor.canSave)
    }

    private func editor(day: AbsenceDay, lessons: [AbsenceLessonCandidate], subjects: [AbsenceOverrideSubjectOption]? = nil,
                        officialSubjects: [AbsencePerSubject] = []) -> AbsenceOverrideEditorViewModel {
        let absence = AbsenceResponse(percentageThreshold: 25, absences: [day], absencesPerSubject: officialSubjects)
        let repository = repository(absence: absence)
        let editor = AbsenceOverrideEditorViewModel(dateKey: "2026-02-02", repository: repository, user: nil) { _ in }
        editor.context = AbsenceOverrideEditorContext(scope: SchoolDataScope(session: session), overrideScope: SchoolDataScope(session: session), sessionGeneration: repository.sessionGeneration,
            rawDay: day, dateKey: "2026-02-02", lessons: lessons, selectedLessonIDs: [],
            subjects: subjects ?? [.init(id: "raw-math", subjectKey: "raw-math", subjectName: "Mathematics")], existingOverride: nil,
            data: AbsenceData(response: absence, absencesPerSubject: [], subjectResolutionSource: .unavailable, user: nil))
        return editor
    }

    private func repository(absence: AbsenceResponse, store: any AbsenceOverrideStoring = InMemoryAbsenceOverrideStore()) -> SchoolRepository {
        SchoolRepository(client: MockBakalariClient(absenceResult: absence, timetableError: URLError(.notConnectedToInternet)),
                         sessionStore: InMemorySessionStore(session: session), marksCache: InMemoryMarksCache(),
                         absenceCache: InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: absence, cachedAt: Date())),
                         timetableCache: InMemoryTimetableCache(), absenceOverrideStore: store)
    }

    private var session: StoredSession {
        var value = StoredSession(accessToken: "mock-access", refreshToken: "mock-refresh", tokenType: "Bearer",
                      expiresAt: Date().addingTimeInterval(3600), baseURL: URL(string: "https://demo.bakalari.cz/")!)
        value.bakalari = BakalariCredentials(username: "absence-editor-test", password: "mock-password")
        return value
    }

    private func day(ok: Int, late: Int = 0) -> AbsenceDay {
        AbsenceDay(date: "2026-02-02T00:00:00+01:00", unsolved: 0, ok: ok, missed: 0, late: late, soon: 0, school: 0, distanceTeaching: 0)
    }

    private func lesson(_ hour: Int) -> AbsenceLessonCandidate {
        AbsenceLessonCandidate(id: "lesson-2026-02-02-\(hour)-raw-math", dateKey: "2026-02-02", hourID: hour,
                               hourCaption: "\(hour)", timeRange: "", subjectKey: "raw-math", subjectName: "Mathematics")
    }
}

private struct FailingOverrideSaveStore: AbsenceOverrideStoring {
    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride] { [] }
    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws { throw CocoaError(.fileWriteNoPermission) }
    func clear(scope: SchoolDataScope) throws { throw CocoaError(.fileWriteNoPermission) }
    func clearAll() throws { throw CocoaError(.fileWriteNoPermission) }
}
