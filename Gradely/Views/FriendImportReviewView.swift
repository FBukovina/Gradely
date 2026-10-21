import SwiftUI

/// What Gradey read from the PDF or photo, ready to fix before saving: tap a
/// lesson to edit it, switch off groups the friend isn't in, check the times.
struct FriendImportReviewView: View {
    @Bindable var viewModel: AddFriendViewModel
    let onSave: () -> Void

    @State private var editingLessonID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsModalFlowHero(
                title: viewModel.pages.isEmpty ? "friends.review.blank.title" : "friends.review.title",
                message: viewModel.pages.isEmpty ? "friends.review.blank.message" : "friends.review.message"
            )

            if viewModel.parsedPages.count > 1 {
                Picker(AppL10n.string("friends.review.page"), selection: Binding(
                    get: { viewModel.selectedPageID ?? 0 },
                    set: { viewModel.selectPage($0) }
                )) {
                    ForEach(viewModel.parsedPages) { page in
                        Text(verbatim: page.title ?? String(format: AppL10n.string("friends.review.pageNumber"), page.id + 1))
                            .tag(page.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Brand.primary)
                .accessibilityIdentifier("friendReviewPagePicker")
            }

            if let draft = viewModel.draft {
                if !draft.groups.isEmpty {
                    groupsSection(draft.groups)
                }

                ForEach(days(in: draft), id: \.self) { day in
                    daySection(day, draft: draft)
                }

                hoursSection

                Button(action: onSave) {
                    Text("friends.add.save")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!draft.lessons.contains { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty })
                .accessibilityIdentifier("friendReviewSaveButton")
            }
        }
    }

    // MARK: - Sections

    private func groupsSection(_ groups: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: "friends.review.groups")
            SettingsSurface(padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    ForEach(groups, id: \.self) { group in
                        Toggle(isOn: Binding(
                            get: { !viewModel.excludedGroups.contains(group) },
                            set: { isOn in
                                if isOn { viewModel.excludedGroups.remove(group) } else { viewModel.excludedGroups.insert(group) }
                            }
                        )) {
                            Text(verbatim: group).font(.gradely(.body))
                        }
                        .tint(Brand.primary)
                    }
                }
            }
        }
    }

    private func daySection(_ day: Int, draft: ImportedTimetableDraft) -> some View {
        let lessons = draft.lessons
            .filter { $0.dayOfWeek == day }
            .sorted { hourIndex($0.hourID, in: draft) < hourIndex($1.hourID, in: draft) }

        return PlainSection {
            PlainSectionTitle(verbatim: Self.weekdayName(day))
        } content: {
            ForEach(lessons) { lesson in
                if editingLessonID == lesson.id {
                    LessonEditor(
                        lesson: binding(for: lesson.id),
                        hours: draft.hours,
                        onDelete: {
                            viewModel.draft?.lessons.removeAll { $0.id == lesson.id }
                            editingLessonID = nil
                        },
                        onDone: { editingLessonID = nil }
                    )
                } else {
                    lessonRow(lesson, draft: draft)
                }
            }

            Button {
                addLesson(on: day, draft: draft)
            } label: {
                GradelyLabel("friends.review.addLesson", systemImage: "plus")
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(Brand.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friendReviewAddLesson-\(day)")
        }
    }

    private func lessonRow(_ lesson: ImportedTimetableDraft.Lesson, draft: ImportedTimetableDraft) -> some View {
        let excluded = !lesson.group.isEmpty && viewModel.excludedGroups.contains(lesson.group)
        let detail = [lesson.room, lesson.teacher, lesson.group].filter { !$0.isEmpty }.joined(separator: " · ")
        return Button {
            editingLessonID = lesson.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(verbatim: draft.hours.first { $0.id == lesson.hourID }?.caption ?? "")
                    .font(.gradely(.subheadline).weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lesson.subject.isEmpty ? AppL10n.string("friends.review.noSubject") : lesson.subject)
                        .font(.gradely(.body).weight(.semibold))
                        .foregroundStyle(lesson.subject.isEmpty ? .secondary : .primary)
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                GradelyIcon("edit-02", size: 14)
                    .foregroundStyle(.secondary)
            }
            .opacity(excluded ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("friendReviewLesson-\(lesson.id)")
    }

    private var hoursSection: some View {
        PlainSection {
            PlainSectionTitle("friends.review.times")
        } content: {
            ForEach(Binding(get: { viewModel.draft?.hours ?? [] }, set: { viewModel.draft?.hours = $0 })) { $hour in
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: hour.caption)
                        .font(.gradely(.subheadline).weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                    TextField("8:00", text: $hour.beginTime)
                        .gradelyKeyboardType(.numbersAndPunctuation)
                        .brandField()
                    Text(verbatim: "–").foregroundStyle(.secondary)
                    TextField("8:45", text: $hour.endTime)
                        .gradelyKeyboardType(.numbersAndPunctuation)
                        .brandField()
                }
            }
        }
    }

    // MARK: - Helpers

    private func binding(for id: UUID) -> Binding<ImportedTimetableDraft.Lesson> {
        Binding(
            get: { viewModel.draft?.lessons.first { $0.id == id } ?? ImportedTimetableDraft.Lesson(dayOfWeek: 1, hourID: 1, subject: "") },
            set: { updated in
                guard let index = viewModel.draft?.lessons.firstIndex(where: { $0.id == id }) else { return }
                viewModel.draft?.lessons[index] = updated
            }
        )
    }

    private func addLesson(on day: Int, draft: ImportedTimetableDraft) {
        let used = Set(draft.lessons.filter { $0.dayOfWeek == day }.map(\.hourID))
        let hourID = draft.hours.first { !used.contains($0.id) }?.id ?? draft.hours.first?.id ?? 1
        let lesson = ImportedTimetableDraft.Lesson(dayOfWeek: day, hourID: hourID, subject: "")
        viewModel.draft?.lessons.append(lesson)
        editingLessonID = lesson.id
    }

    private func days(in draft: ImportedTimetableDraft) -> [Int] {
        let weekend = Set(draft.lessons.map(\.dayOfWeek).filter { $0 > 5 })
        return Array(1...5) + weekend.sorted()
    }

    private func hourIndex(_ id: Int, in draft: ImportedTimetableDraft) -> Int {
        draft.hours.firstIndex { $0.id == id } ?? .max
    }

    static func weekdayName(_ dayOfWeek: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguageOverride.locale
        let name = calendar.standaloneWeekdaySymbols[dayOfWeek % 7]
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// One lesson opened for editing in place.
private struct LessonEditor: View {
    @Binding var lesson: ImportedTimetableDraft.Lesson
    let hours: [ImportedTimetableDraft.Hour]
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker(AppL10n.string("friends.review.lesson"), selection: $lesson.hourID) {
                ForEach(hours) { hour in
                    Text(verbatim: [hour.caption, hour.beginTime.isEmpty ? nil : "\(hour.beginTime) – \(hour.endTime)"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .tag(hour.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Brand.primary)

            field("friends.review.subject", text: $lesson.subject)
                .accessibilityIdentifier("friendReviewSubjectField")
            HStack(spacing: Spacing.sm) {
                field("friends.review.room", text: $lesson.room)
                field("friends.review.teacher", text: $lesson.teacher)
            }
            field("friends.review.group", text: $lesson.group)

            HStack {
                Button(role: .destructive, action: onDelete) {
                    GradelyLabel("friends.review.deleteLesson", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Button(action: onDone) {
                    Text("action.done")
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
                .accessibilityIdentifier("friendReviewDoneButton")
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(AppL10n.string(String.LocalizationValue(title)), text: text)
            .autocorrectionDisabled()
            .gradelyTextInputAutocapitalization(.never)
            .brandField()
    }
}
