import SwiftUI

/// Past chats, today's Compute allowance and the data controls (delete chats,
/// revoke consent). Confirmation dialogs live here because dialogs attached to
/// the presenting view can't appear over this sheet.
struct GradeyAIHistorySheet: View {
    let viewModel: GradeyAIViewModel
    let hasEarlyAccess: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeletion: GradeyAIConversation? = nil
    @State private var dangerousAction: DangerousAction? = nil

    init(viewModel: GradeyAIViewModel, hasEarlyAccess: Bool) {
        self.viewModel = viewModel
        self.hasEarlyAccess = hasEarlyAccess
    }

    private enum DangerousAction {
        case deleteAll
        case revokeConsent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradeyAIBackground()

                VStack(spacing: 0) {
                    header
                    list
                }
            }
            .settingsModalNavigationChrome()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 640)
        #endif
        .confirmationDialog(
            AppL10n.string("gradey.ai.conversation.delete.title"),
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            if let conversation = pendingDeletion {
                Button(AppL10n.string("gradey.ai.conversation.delete.action"), role: .destructive) {
                    pendingDeletion = nil
                    Task { await viewModel.delete(conversation) }
                }
            }
            Button(AppL10n.string("action.cancel"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("gradey.ai.conversation.delete.message")
        }
        .confirmationDialog(
            dangerousActionTitle,
            isPresented: dangerousActionBinding,
            titleVisibility: .visible
        ) {
            switch dangerousAction {
            case .deleteAll:
                Button(AppL10n.string("gradey.ai.deleteAll.action"), role: .destructive) {
                    dangerousAction = nil
                    Task { await viewModel.deleteAll() }
                }
            case .revokeConsent:
                Button(AppL10n.string("gradey.ai.privacy.revoke.action"), role: .destructive) {
                    dangerousAction = nil
                    Task {
                        await viewModel.revokeConsent()
                        if viewModel.status?.consentRequired == true { dismiss() }
                    }
                }
            case nil:
                EmptyView()
            }
            Button(AppL10n.string("action.cancel"), role: .cancel) {
                dangerousAction = nil
            }
        } message: {
            Text(dangerousActionMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text("gradey.ai.conversations.title")
                .font(.gradelyDisplay(size: 30, relativeTo: .title))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            GradeyAICircleButton(icon: "cancel-01", accessibilityLabel: AppL10n.string("action.ok")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("gradeyAIHistoryCloseButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, Spacing.sm)
    }

    private var list: some View {
        List {
            computeCard
                .historyRow()

            if viewModel.conversations.isEmpty {
                emptyState
                    .historyRow()
            } else {
                Section {
                    ForEach(viewModel.conversations) { conversation in
                        conversationRow(conversation)
                            .historyRow(vertical: 4)
                    }
                }
            }

            Section {
                manageButton(
                    icon: "trash",
                    title: "gradey.ai.deleteAll.action",
                    identifier: "gradeyAIDeleteAllButton"
                ) {
                    dangerousAction = .deleteAll
                }
                .disabled(viewModel.conversations.isEmpty || viewModel.isStreaming)
                .historyRow(vertical: 4)

                manageButton(
                    icon: "hand.raised.slash",
                    title: "gradey.ai.privacy.revoke.action",
                    identifier: "gradeyAIRevokeConsentButton"
                ) {
                    dangerousAction = .revokeConsent
                }
                .disabled(viewModel.isStreaming)
                .historyRow(vertical: 4)

                privacyFootnote
                    .historyRow()
            } header: {
                SectionHeader("gradey.ai.history.manage")
                    .padding(.top, Spacing.md)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .accessibilityIdentifier("gradeyAIConversationList")
    }

    private var computeCard: some View {
        let status = viewModel.status
        let limit = max(status?.dailyLimit ?? 0, 1)
        let fraction = min(1, max(0, Double(status?.remaining ?? 0) / Double(limit)))
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                GradeyAIOrb(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GradeyAIQuotaText.remaining(status))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    if let reset = GradeyAIQuotaText.reset(status) {
                        Text(reset)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if hasEarlyAccess {
                    GradeyAIEarlyAccessBadge()
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Brand.gradient)
                        .frame(width: max(6, geometry.size.width * fraction))
                        .shadow(color: Brand.primary.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(Spacing.lg)
        .gradeyAIGlass(cornerRadius: 24, tint: 0.08)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gradeyAIHistoryCompute")
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            GradeyAIOrb(size: 40)
            Text("gradey.ai.empty.title")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIEmptyConversations")
    }

    private func conversationRow(_ conversation: GradeyAIConversation) -> some View {
        let isCurrent = viewModel.currentConversation?.id == conversation.id
        return Button {
            Task { await viewModel.open(conversation) }
            dismiss()
        } label: {
            HStack(spacing: Spacing.md) {
                GradelyIcon("message-multiple-01", size: 16)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary))
                    .frame(width: 32, height: 32)
                    .background(Brand.primary.opacity(isCurrent ? 0.16 : 0.08), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(
                        conversation.lastMessageAt ?? conversation.updatedAt,
                        format: .relative(presentation: .named)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)
                GradelyIcon("arrow-right-01", size: 13)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Brand.primary.opacity(colorScheme == .dark ? (isCurrent ? 0.16 : 0.08) : (isCurrent ? 0.12 : 0.05)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Brand.gradient, lineWidth: 1)
                    .opacity(isCurrent ? 0.6 : 0.12)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDeletion = conversation
            } label: {
                GradelyLabel(AppL10n.string("gradey.ai.conversation.delete.action"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = conversation
            } label: {
                GradelyLabel(AppL10n.string("gradey.ai.conversation.delete.action"), systemImage: "trash")
            }
        }
        .accessibilityIdentifier("gradeyAIConversation-\(conversation.id)")
    }

    private func manageButton(
        icon: String,
        title: LocalizedStringKey,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            GradeyAIManageRowLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            GradelyIcon(systemName: "lock.shield.fill", size: 14)
                .foregroundStyle(Brand.primary)
                .accessibilityHidden(true)
            Text("gradey.ai.privacy.footnote")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xl)
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var dangerousActionBinding: Binding<Bool> {
        Binding(
            get: { dangerousAction != nil },
            set: { if !$0 { dangerousAction = nil } }
        )
    }

    private var dangerousActionTitle: String {
        switch dangerousAction {
        case .deleteAll: AppL10n.string("gradey.ai.deleteAll.title")
        case .revokeConsent: AppL10n.string("gradey.ai.privacy.revoke.title")
        case nil: ""
        }
    }

    private var dangerousActionMessage: String {
        switch dangerousAction {
        case .deleteAll: AppL10n.string("gradey.ai.deleteAll.message")
        case .revokeConsent: AppL10n.string("gradey.ai.privacy.revoke.message")
        case nil: ""
        }
    }
}

private struct GradeyAIManageRowLabel: View {
    let icon: String
    let title: LocalizedStringKey

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Spacing.md) {
            GradelyIcon(systemName: icon, size: 16)
                .frame(width: 32, height: 32)
                .background(GradeBand.poor.foregroundColor.opacity(0.12), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(GradeBand.poor.foregroundColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GradeBand.poor.foregroundColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private extension View {
    func historyRow(vertical: CGFloat = Spacing.sm) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: vertical, leading: 20, bottom: vertical, trailing: 20))
    }
}
