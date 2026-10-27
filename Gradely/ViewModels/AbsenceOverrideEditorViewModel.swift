import Foundation
import Observation

/// A draft always describes the original missed units first. Hiding is a separate
/// selection so a six-lesson absence never becomes a five-lesson partial-day guess.
@MainActor
@Observable
final class AbsenceOverrideEditorViewModel {
    struct DraftAllocation: Identifiable, Equatable {
        let id: String
        var lessonID: String?
        var lessonTitle: String
        var subjectKey: String?
        var subjectName: String
        var category: AbsenceOverrideCategory?
        var isHidden: Bool
    }

    let dateKey: String
    var context: AbsenceOverrideEditorContext?
    var allocations: [DraftAllocation] = []
    var originalLessonIDs: Set<String> = []
    var usesManualAllocations = false
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var didSave = false
    private let repository: SchoolRepository
    private let user: UserResponse?
    private let onSave: (AbsenceData) -> Void

    init(dateKey: String, repository: SchoolRepository, user: UserResponse?, onSave: @escaping (AbsenceData) -> Void) {
        self.dateKey = dateKey
        self.repository = repository
        self.user = user
        self.onSave = onSave
    }

    var title: String {
        guard let date = MarkDateFormatter.date(from: dateKey) else { return dateKey }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    var originalCount: Int { context.map { AbsenceCounts(day: $0.rawDay).total } ?? 0 }
    var hiddenCount: Int { allocations.filter(\.isHidden).count }
    var resultingCount: Int { originalCount - hiddenCount }
    var availableCategories: [AbsenceOverrideCategory] {
        guard let context else { return [] }
        return AbsenceOverrideCategory.allCases.filter { $0.count(in: context.rawDay) > 0 }
    }
    var hasOriginalSelection: Bool { allocations.count == originalCount && originalCount > 0 }
    var hiddenSubjectMappingError: String? {
        guard let context, !context.data.rawResponse.absencesPerSubject.isEmpty else { return nil }
        let officialSubjects = context.data.rawResponse.absencesPerSubject
        let unmatched = Set(allocations.filter { allocation in
            allocation.isHidden && !allocation.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && AbsenceOverrideProjection.uniqueSubjectIndex(subjectKey: nil, subjectName: allocation.subjectName,
                    subjects: officialSubjects, stableIDHints: []) == nil
        }.map(\.subjectName)).sorted()
        guard !unmatched.isEmpty else { return nil }
        return String(format: AppL10n.string("absence.override.subjectMappingUnavailable"), unmatched.joined(separator: ", "))
    }

    /// Timetable lessons behind the missed (not late or early) hours, once every
    /// recorded hour has its lesson and category.
    var pickedLessonIDs: Set<String>? {
        guard let context, hasOriginalSelection else { return nil }
        let categoriesMatch = AbsenceOverrideCategory.allCases.allSatisfy { category in
            allocations.filter { $0.category == category }.count == category.count(in: context.rawDay)
        }
        let missed = allocations.filter { $0.category?.contributesToBase == true }
        let ids = Set(missed.compactMap(\.lessonID))
        guard categoriesMatch, !ids.isEmpty, ids.count == missed.count else { return nil }
        return ids
    }

    var canSave: Bool {
        if hiddenCount == 0 {
            guard let context, !isLoading, !isSaving else { return false }
            // Nothing removed: restore the day, or remember a new lesson pick.
            if context.existingOverride != nil { return true }
            guard let pickedLessonIDs else { return false }
            return pickedLessonIDs != context.selectedLessonIDs
        }
        guard let context, hasOriginalSelection, !isLoading, !isSaving,
              hiddenSubjectMappingError == nil else { return false }
        guard allocations.allSatisfy({ !$0.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.category != nil }) else { return false }
        return AbsenceOverrideCategory.allCases.allSatisfy { category in
            allocations.filter { $0.category == category }.count == category.count(in: context.rawDay)
        }
    }

    func load() async {
        guard context == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await repository.loadAbsenceOverrideEditorContext(dateKey: dateKey, user: user)
            context = loaded
            originalLessonIDs = loaded.selectedLessonIDs.intersection(Set(loaded.lessons.map(\.id)))
            if let existing = loaded.existingOverride, AbsenceCounts(day: existing.baselineDay) == AbsenceCounts(day: loaded.rawDay) {
                allocations = existing.allocations.map {
                    DraftAllocation(id: $0.id, lessonID: $0.lessonID, lessonTitle: $0.lessonTitle,
                                    subjectKey: $0.subjectKey, subjectName: $0.subjectName,
                                    category: $0.category, isHidden: existing.hiddenAllocationIDs.contains($0.id))
                }
                originalLessonIDs = Set(allocations.compactMap(\.lessonID))
                usesManualAllocations = allocations.contains { $0.lessonID == nil }
            } else if loaded.lessons.count == originalCount {
                originalLessonIDs = Set(loaded.lessons.map(\.id))
                confirmOriginalLessons()
            } else if loaded.selectedLessonIDs.count == originalCount,
                      loaded.selectedLessonIDs.isSubset(of: Set(loaded.lessons.map(\.id))) {
                originalLessonIDs = loaded.selectedLessonIDs
                confirmOriginalLessons()
            } else if loaded.lessons.count < originalCount {
                useManualAllocations()
                fillManualAllocations(from: loaded.lessons)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleOriginalLesson(_ id: String) {
        if originalLessonIDs.contains(id) { originalLessonIDs.remove(id) }
        else if originalLessonIDs.count < originalCount { originalLessonIDs.insert(id) }
    }

    func confirmOriginalLessons() {
        guard let context, originalLessonIDs.count == originalCount else { return }
        let singleCategory = availableCategories.count == 1 ? availableCategories.first : nil
        allocations = context.lessons.filter { originalLessonIDs.contains($0.id) }.map { lesson in
            let subject = subject(for: lesson, in: context)
            return DraftAllocation(id: lesson.id, lessonID: lesson.id, lessonTitle: lesson.displayTitle,
                                   subjectKey: subject.key, subjectName: subject.name,
                                   category: singleCategory, isHidden: false)
        }
        usesManualAllocations = false
    }

    /// The school can record more hours than the timetable shows. The lessons it
    /// does show fill the first rows, so only the extra hours need a subject.
    private func fillManualAllocations(from lessons: [AbsenceLessonCandidate]) {
        guard let context, availableCategories.count == 1 else { return }
        for (index, lesson) in zip(allocations.indices, lessons) {
            let subject = subject(for: lesson, in: context)
            allocations[index].lessonID = lesson.id
            allocations[index].lessonTitle = lesson.displayTitle
            allocations[index].subjectKey = subject.key
            allocations[index].subjectName = subject.name
        }
    }

    private func subject(for lesson: AbsenceLessonCandidate,
                         in context: AbsenceOverrideEditorContext) -> (key: String?, name: String) {
        let matches = context.subjects.filter {
            $0.subjectKey == lesson.subjectKey || normalized($0.subjectName) == normalized(lesson.subjectName)
        }
        if matches.count == 1 { return (matches[0].subjectKey, matches[0].subjectName) }
        return context.subjects.isEmpty ? (lesson.subjectKey, lesson.subjectName) : (nil, "")
    }

    func useManualAllocations() {
        guard let context else { return }
        originalLessonIDs = []
        usesManualAllocations = true
        allocations = AbsenceOverrideCategory.allCases.flatMap { category in
            (0..<max(0, category.count(in: context.rawDay))).map { index in
                DraftAllocation(id: "manual-\(dateKey)-\(category.rawValue)-\(index)", lessonID: nil,
                                lessonTitle: "", subjectKey: nil, subjectName: "", category: category, isHidden: false)
            }
        }
    }

    func reviseOriginalLessons() {
        allocations = []
        usesManualAllocations = false
    }

    func hideEntireDay() {
        for index in allocations.indices { allocations[index].isHidden = true }
    }

    func clearHiddenSelection() {
        for index in allocations.indices { allocations[index].isHidden = false }
    }

    func selectSubject(_ subjectID: String, allocationID: String) {
        guard let index = allocations.firstIndex(where: { $0.id == allocationID }) else { return }
        let subject = context?.subjects.first { $0.id == subjectID }
        allocations[index].subjectKey = subject?.subjectKey
        allocations[index].subjectName = subject?.subjectName ?? ""
    }

    func selectedSubjectID(for allocation: DraftAllocation) -> String {
        context?.subjects.first { $0.subjectName == allocation.subjectName && $0.subjectKey == allocation.subjectKey }?.id ?? ""
    }

    func save() async {
        guard canSave, let context else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // Nothing left hidden means the override is restored instead of saved.
        // A complete pick is kept, so the day still lists its subjects.
        if hiddenCount == 0 {
            do {
                let data = if let pickedLessonIDs {
                    try await repository.saveAbsenceDayLessonPick(pickedLessonIDs, context: context, user: user)
                } else {
                    try await repository.restoreAbsenceOverride(
                        dateKey: dateKey,
                        scope: context.scope,
                        overrideScope: context.overrideScope,
                        sessionGeneration: context.sessionGeneration,
                        user: user
                    )
                }
                onSave(data)
                didSave = true
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        let saved = AbsenceDayOverride(
            id: context.existingOverride?.id ?? UUID(), scope: context.overrideScope, dateKey: dateKey,
            baselineDay: context.rawDay,
            allocations: allocations.compactMap { allocation in
                guard let category = allocation.category else { return nil }
                return AbsenceOverrideAllocation(id: allocation.id, lessonID: allocation.lessonID,
                    subjectKey: allocation.subjectKey, subjectName: allocation.subjectName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lessonTitle: allocation.lessonTitle, category: category)
            },
            hiddenAllocationIDs: Set(allocations.filter(\.isHidden).map(\.id))
        )
        do {
            let data = try await repository.saveAbsenceOverride(saved, context: context, user: user)
            onSave(data)
            didSave = true
        } catch {
            // The draft intentionally remains intact when durable persistence fails.
            errorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String {
        AbsenceTimetableLessonResolver.normalized(value)
    }
}
