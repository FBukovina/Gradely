import QuickLook
import SwiftUI

// MARK: - Row

/// A school homework in a list: the done tick, then the summary that opens it.
struct HomeworkRow: View {
    let homework: Homework
    let store: HomeworkStore
    /// Off in the Planner, whose day heading already says when it's due.
    var showsDue = true
    let onOpen: () -> Void
    let onError: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            HomeworkDoneButton(homework: homework, store: store, onError: onError)

            Button(action: onOpen) {
                HStack(spacing: Spacing.sm) {
                    HomeworkSummary(homework: homework, showsDue: showsDue)
                    Spacer(minLength: 0)
                    SettingsDisclosureIcon()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeworkItem-\(homework.id)")
        }
    }
}

struct HomeworkDoneButton: View {
    let homework: Homework
    let store: HomeworkStore
    let onError: (String) -> Void

    var body: some View {
        Button {
            Task {
                do { try await store.setDone(!homework.isDone, id: homework.id) }
                catch { onError(error.localizedDescription) }
            }
        } label: {
            // Leading-aligned so the circle lines up with the section title.
            GradelyIcon(systemName: homework.isDone ? "checkmark.circle.fill" : "circle", size: 22)
                .foregroundStyle(Brand.primary)
                .frame(width: 40, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.pendingIDs.contains(homework.id))
        .accessibilityLabel(AppL10n.string(homework.isDone ? "planner.markIncomplete" : "planner.markComplete"))
        .accessibilityIdentifier("homeworkDone-\(homework.id)")
    }
}

/// Title, "School homework · subject" and the due day, laid out like a Planner item.
struct HomeworkSummary: View {
    let homework: Homework
    var showsDue = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: homework.title)
                .font(.gradely(.headline))
                .strikethrough(homework.isDone)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            HStack(spacing: Spacing.sm) {
                GradelyLabel(AppL10n.string("homework.school"), systemImage: "mortarboard-02", iconSize: 12)
                if let subject = homework.subjectLabel {
                    Text(verbatim: subject)
                }
                if !homework.attachments.isEmpty {
                    GradelyIcon("attachment-01", size: 12)
                }
            }
            .font(.gradely(.caption))
            .foregroundStyle(.secondary)

            if showsDue, let due = HomeworkText.due(homework) {
                GradelyLabel(due, systemImage: "clock", iconSize: 12)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum HomeworkText {
    /// "Due today", "Due tomorrow" or "Due Thu 24. 10.".
    static func due(_ homework: Homework, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let day = homework.dueDay(in: calendar) else { return nil }
        if calendar.isDate(day, inSameDayAs: now) { return AppL10n.string("homework.due.today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return AppL10n.string("homework.due.tomorrow")
        }
        return String(format: AppL10n.string("homework.due.date"), SchoolDateFormatting.weekdayShortDate(day))
    }

    /// Homework text with its links made tappable.
    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let textRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(textRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(textRange.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = url
        }
        return attributed
    }
}

// MARK: - Detail

/// The whole homework: text, teacher, dates, attachments and the done tick.
/// Reads from the store so a tick made elsewhere shows here too.
struct HomeworkDetailView: View {
    let homeworkID: String
    let store: HomeworkStore
    /// Presented as a sheet (its own bar and close button) rather than pushed.
    var isModal = true
    @State private var errorMessage: String?
    @State private var downloadingID: String?
    @State private var previewURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .quickLookPreview($previewURL)
            .alert(AppL10n.string("error.title"), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(AppL10n.string("action.done")) {}
            } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        if isModal {
            modal
                .presentationDetents([.medium, .large])
                .gradelyMacSheetSize(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 520)
        } else {
            detailScroll
                .navigationTitle(navigationTitle)
                .gradelyNavigationTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var modal: some View {
        #if os(macOS)
        // The header carries the title and close button; a NavigationStack
        // would only add a grey strip repeating it.
        detailScroll
        #else
        NavigationStack {
            detailScroll
                .navigationTitle(navigationTitle)
                .gradelyNavigationTitleDisplayMode(.inline)
                .gradelyModalDismissButton { dismiss() }
        }
        #endif
    }

    private var homework: Homework? { store.homework(id: homeworkID) }

    private var navigationTitle: String {
        homework?.subjectLabel ?? AppL10n.string("planner.type.homework")
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if isModal { macHeader }

                if let homework {
                    Text(HomeworkText.linkified(homework.content.isEmpty ? homework.title : homework.content))
                        .font(.gradely(.body))
                        .tint(Brand.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("homeworkDetailContent")

                    details(homework)

                    if !homework.attachments.isEmpty {
                        attachments(homework)
                    }

                    doneButton(homework)
                } else {
                    ContentUnavailableView("today.destination.unavailable", systemImage: "checklist")
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background {
            SettingsBackground()
        }
        .accessibilityIdentifier("homeworkDetail")
    }

    private func details(_ homework: Homework) -> some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let due = homework.dueDay() {
                    DetailRow(systemImage: "clock", title: "homework.detail.due", value: SchoolDateFormatting.weekdayShortDate(due))
                }
                if let assigned = homework.assignedDay() {
                    DetailRow(systemImage: "calendar", title: "homework.detail.assigned", value: SchoolDateFormatting.weekdayShortDate(assigned))
                }
                if let teacher = homework.teacherName {
                    DetailRow(systemImage: "person.fill", title: "timetable.detail.teacher", value: teacher)
                }
                if let notice = homework.notice {
                    DetailRow(systemImage: "text.book.closed.fill", title: "homework.detail.notice", value: notice)
                }
                if homework.isElectronic {
                    DetailRow(systemImage: "checklist", title: "homework.detail.handIn", value: AppL10n.string("homework.detail.electronic"))
                }
                if homework.isClosed {
                    DetailRow(systemImage: "lock.shield.fill", title: "homework.detail.status", value: AppL10n.string("homework.closed"))
                }
            }
        }
    }

    private func attachments(_ homework: Homework) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SettingsModalSectionHeader(title: "homework.attachments")
            SettingsSurface(padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(homework.attachments.enumerated()), id: \.element.id) { index, attachment in
                        if index > 0 { Divider() }
                        Button { open(attachment) } label: {
                            HStack(spacing: Spacing.md) {
                                GradelyIcon("attachment-01", size: 18)
                                    .foregroundStyle(Brand.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: attachment.name)
                                        .font(.gradely(.subheadline))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    if let size = attachment.size {
                                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                            .font(.gradely(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if downloadingID == attachment.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    SettingsDisclosureIcon()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(downloadingID != nil)
                        .accessibilityIdentifier("homeworkAttachment-\(attachment.id)")
                    }
                }
            }
        }
    }

    private func doneButton(_ homework: Homework) -> some View {
        Button {
            Task {
                do { try await store.setDone(!homework.isDone, id: homework.id) }
                catch { errorMessage = error.localizedDescription }
            }
        } label: {
            GradelyLabel(
                AppL10n.string(homework.isDone ? "homework.markNotDone" : "homework.markDone"),
                systemImage: homework.isDone ? "undo-02" : "checkmark"
            )
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(store.pendingIDs.contains(homework.id))
        .accessibilityIdentifier("homeworkDetailDoneButton")
    }

    private func open(_ attachment: HomeworkAttachment) {
        downloadingID = attachment.id
        Task {
            defer { downloadingID = nil }
            do { previewURL = try await store.download(attachment) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// macOS has no navigation bar in a sheet, so the view names itself and
    /// carries the close button.
    @ViewBuilder private var macHeader: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(verbatim: navigationTitle)
                .font(.gradely(.title2).bold())
                .lineLimit(2)
            Spacer(minLength: Spacing.sm)
            Button { dismiss() } label: { GradelyModalCloseLabel() }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(AppL10n.string("action.done"))
                .accessibilityIdentifier("modalDismissButton")
        }
        #endif
    }
}
