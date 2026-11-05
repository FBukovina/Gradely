import QuickLook
import SwiftUI

// MARK: - Toolbar

/// The envelope on Today, with the number of unread Komens messages.
struct KomensToolbarButton: View {
    let store: KomensStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GradelyIcon(systemName: "envelope.fill")
        }
        .badge(store.unreadCount)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("todayKomensButton")
    }

    private var accessibilityLabel: String {
        let title = AppL10n.string("komens.title")
        guard store.unreadCount > 0 else { return title }
        return title + ", " + String.localizedStringWithFormat(AppL10n.string("komens.unreadCount"), store.unreadCount)
    }
}

// MARK: - Sheet

/// Komens: messages from the school and its noticeboard. Opening a message
/// marks it read in Bakaláři too.
struct KomensView: View {
    let store: KomensStore
    @State private var box: KomensBox = .received
    /// Mac only: the message shown beside the list.
    @State private var selectedID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .task { await store.refresh() }
            .gradelyMacSheetSize(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 620)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        // A NavigationStack in a Mac sheet draws a grey strip, so the message
        // opens beside the list, like Mail.
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("komens.title")
                    .font(.gradely(.title2).bold())
                Spacer(minLength: Spacing.sm)
                boxPicker
                    .frame(maxWidth: 260)
                Button { dismiss() } label: { GradelyModalCloseLabel() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(AppL10n.string("action.done"))
                    .accessibilityIdentifier("modalDismissButton")
            }
            .padding(Spacing.lg)

            Divider()

            HStack(spacing: 0) {
                messageList(showsPicker: false)
                    .frame(width: 320)
                Divider()
                Group {
                    if let selectedID, store.message(id: selectedID) != nil {
                        KomensMessageView(messageID: selectedID, store: store)
                            .id(selectedID)
                    } else {
                        ContentUnavailableView {
                            GradelyLabel(AppL10n.string("komens.select"), systemImage: "envelope.fill", iconSize: 28)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { SettingsBackground() }
        #else
        NavigationStack {
            messageList(showsPicker: true)
                .background { SettingsBackground() }
                .navigationTitle(AppL10n.string("komens.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                .gradelyModalDismissButton { dismiss() }
                .navigationDestination(for: String.self) { messageID in
                    KomensMessageView(messageID: messageID, store: store)
                }
        }
        #endif
    }

    private var boxPicker: some View {
        Picker(AppL10n.string("komens.title"), selection: $box) {
            Text("komens.box.received").tag(KomensBox.received)
            Text("komens.box.noticeboard").tag(KomensBox.noticeboard)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("komensBoxPicker")
    }

    private func messageList(showsPicker: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsPicker {
                    boxPicker
                        .padding(.bottom, Spacing.md)
                }

                let messages = store.messages(in: box)
                if messages.isEmpty {
                    emptyState
                        .padding(.top, Spacing.xl)
                } else {
                    ForEach(messages) { message in
                        Divider()
                        row(message)
                            .padding(.vertical, Spacing.md)
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refresh(force: true) }
        .accessibilityIdentifier("komensList")
    }

    @ViewBuilder
    private func row(_ message: KomensMessage) -> some View {
        #if os(macOS)
        Button { selectedID = message.id } label: {
            KomensMessageRow(message: message)
                .background {
                    if selectedID == message.id {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Brand.primary.opacity(0.12))
                            .padding(.horizontal, -Spacing.sm)
                            .padding(.vertical, -Spacing.sm)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedID == message.id ? .isSelected : [])
        .accessibilityIdentifier("komensRow-\(message.messageID)")
        #else
        NavigationLink(value: message.id) {
            KomensMessageRow(message: message)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("komensRow-\(message.messageID)")
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        if !store.hasLoaded, store.isRefreshing {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        } else if !store.hasLoaded, let errorMessage = store.errorMessage {
            VStack(spacing: Spacing.md) {
                Text(verbatim: errorMessage)
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(AppL10n.string("action.retry")) {
                    Task { await store.refresh(force: true) }
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text(box == .received ? "komens.empty.received" : "komens.empty.noticeboard")
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("komensEmpty")
        }
    }
}

// MARK: - Row

private struct KomensMessageRow: View {
    let message: KomensMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(Brand.primary)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .opacity(message.isRead ? 0 : 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(verbatim: message.heading)
                        .font(.gradely(.headline).weight(message.isRead ? .semibold : .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Spacing.sm)
                    if let sentAt = message.sentAt {
                        Text(verbatim: KomensDates.short(sentAt))
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if let sender = message.senderName {
                    HStack(spacing: Spacing.xs) {
                        Text(verbatim: sender)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !message.attachments.isEmpty {
                            GradelyIcon("attachment-01", size: 13)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !message.preview.isEmpty {
                    Text(verbatim: message.preview)
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.isRead ? Text(verbatim: "") : Text("komens.unread"))
    }
}

enum KomensDates {
    /// Today's messages show the time, older ones the day.
    static func short(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).hour().minute())
        }
        return SchoolDateFormatting.shortDate(date)
    }

    static func full(_ date: Date) -> String {
        SchoolDateFormatting.weekdayShortDate(date) + " " + date.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).hour().minute())
    }
}

// MARK: - Message

/// One message: heading, sender, text and attachments. Reads from the store,
/// and marks the message read when it's shown.
struct KomensMessageView: View {
    let messageID: String
    let store: KomensStore
    @State private var downloadingID: String?
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let message {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: message.heading)
                            .font(.gradely(.title2).bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: byline(message))
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }

                    if !message.body.isEmpty {
                        Text(HomeworkText.linkified(message.body))
                            .font(.gradely(.body))
                            .tint(Brand.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("komensMessageBody")
                    }

                    if !message.attachments.isEmpty {
                        SchoolAttachmentsSection(
                            attachments: message.attachments,
                            downloadingID: downloadingID,
                            identifierPrefix: "komensAttachment",
                            onOpen: open
                        )
                    }
                } else {
                    ContentUnavailableView("today.destination.unavailable", systemImage: "envelope")
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { SettingsBackground() }
        #if !os(macOS)
        .navigationTitle(message.map { $0.box == .noticeboard ? AppL10n.string("komens.box.noticeboard") : AppL10n.string("komens.title") } ?? "")
        .gradelyNavigationTitleDisplayMode(.inline)
        #endif
        .quickLookPreview($previewURL)
        .alert(AppL10n.string("error.title"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(AppL10n.string("action.done")) {}
        } message: { Text(errorMessage ?? "") }
        .task(id: messageID) {
            if let message { await store.markRead(message) }
        }
        .accessibilityIdentifier("komensMessage")
    }

    private var message: KomensMessage? { store.message(id: messageID) }

    private func byline(_ message: KomensMessage) -> String {
        [message.senderName, message.sentAt.map { KomensDates.full($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    private func open(_ attachment: SchoolAttachment) {
        downloadingID = attachment.id
        Task {
            defer { downloadingID = nil }
            do { previewURL = try await store.download(attachment) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
