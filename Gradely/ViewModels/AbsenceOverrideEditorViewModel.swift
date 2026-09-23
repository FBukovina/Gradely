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

    var canSave: Bool {
        guard let context, hasOriginalSelection, hiddenCount > 0, !isLoading, !isSaving,
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
            let matches = context.subjects.filter {
                $0.subjectKey == lesson.subjectKey || normalized($0.subjectName) == normalized(lesson.subjectName)
            }
            let match = matches.count == 1 ? matches.first : nil
            return DraftAllocation(id: lesson.id, lessonID: lesson.id, lessonTitle: lesson.displayTitle,
                                   subjectKey: match?.subjectKey ?? (context.subjects.isEmpty ? lesson.subjectKey : nil),
                                   subjectName: match?.subjectName ?? (context.subjects.isEmpty ? lesson.subjectName : ""),
                                   category: singleCategory, isHidden: false)
        }
        usesManualAllocations = false
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
