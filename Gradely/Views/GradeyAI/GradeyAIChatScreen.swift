import SwiftUI

/// The main Gradey AI surface. A new chat (nil or draft conversation) shows the
/// welcome state; otherwise the conversation. The dock keeps what will be
/// shared, its Compute cost and the composer together at the bottom.
struct GradeyAIChatScreen: View {
    @Bindable var viewModel: GradeyAIViewModel
    let hasEarlyAccess: Bool
    let showsUpgradeCTA: Bool
    let onUpgrade: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isComposerFocused: Bool

    init(
        viewModel: GradeyAIViewModel,
        hasEarlyAccess: Bool,
        showsUpgradeCTA: Bool,
        onUpgrade: @escaping () -> Void
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.hasEarlyAccess = hasEarlyAccess
        self.showsUpgradeCTA = showsUpgradeCTA
        self.onUpgrade = onUpgrade
    }

    private static let bottomID = "gradeyAIMessageBottom"

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var isBusy: Bool {
        viewModel.isStreaming || viewModel.isPreparingReply
    }

    var body: some View {
        VStack(spacing: 0) {
            if isAccessibilityLayout {
                accessibleContent
            } else {
                regularContent
            }
            dock
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var regularContent: some View {
        if viewModel.isOpeningConversation, viewModel.messages.isEmpty {
            VStack(spacing: 0) {
                pausedBanner
                    .padding(.horizontal, 20)
                GradeyAIProgressState(message: "gradey.ai.loading")
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("gradeyAIOpeningConversation")
            }
        } else if viewModel.messages.isEmpty {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    pausedBanner
                    welcome
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center, for: .alignment)
            .gradeyAIScrollEdgeFade()
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        } else {
            VStack(spacing: 0) {
                pausedBanner
                    .padding(.horizontal, 20)
                messageList
            }
        }
    }

    private var accessibleContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    pausedBanner
                    contextBar
                    if viewModel.isOpeningConversation, viewModel.messages.isEmpty {
                        GradeyAIProgressState(message: "gradey.ai.loading")
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("gradeyAIOpeningConversation")
                    } else if viewModel.messages.isEmpty {
                        welcome
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("gradeyAIAccessibleContent")
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy, animated: !viewModel.isStreaming)
            }
            .onChange(of: viewModel.messages.last?.content) {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("gradeyAIMessageList")
            .gradeyAIScrollEdgeFade()
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy, animated: !viewModel.isStreaming)
            }
            .onChange(of: viewModel.messages.last?.content) {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func messageRow(_ message: GradeyAIMessage) -> some View {
        GradeyAIMessageRow(
            message: message,
            canRetry: viewModel.canRetry(message),
            onRetry: { Task { await viewModel.retry() } }
        )
        .id(message.id)
    }

    @ViewBuilder
    private var pausedBanner: some View {
        if viewModel.status?.enabled == false {
            GradeyAIBanner(
                kind: .paused,
                title: AppL10n.string("gradey.ai.availability.paused.title"),
                message: AppL10n.string("gradey.ai.availability.paused.message")
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gradeyAIServiceUnavailableBanner")
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                GradeyAIOrb(size: 64)
                    .padding(.bottom, Spacing.xs)

                Text("gradey.ai.chat.empty.title")
                    .font(.gradelyDisplay(size: 32, relativeTo: .title))
                    .foregroundStyle(Brand.gradient)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("gradey.ai.chat.empty.message")
                    .font(.gradely(.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            if viewModel.contextSelection.action == .reply {
                generalSuggestions
            } else {
                focusedAction
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIWelcome")
    }

    private var generalSuggestions: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("gradey.ai.suggestions.school")
                    .padding(.horizontal, Spacing.xs)

                GlassEffectContainer(spacing: 6) {
                    LazyVGrid(columns: suggestionColumns, spacing: 10) {
                        actionCard(.tomorrow, icon: "sun-01")
                        actionCard(.studyPriorities, icon: "target-02")
                        actionCard(.weekSummary, icon: "calendar-check-in-02")
                        subjectCard
                        testCard
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("gradey.ai.suggestions.general")
                    .padding(.horizontal, Spacing.xs)
                starterPrompts
            }
        }
    }

    private var suggestionColumns: [GridItem] {
        #if os(macOS)
        // Wider tiles keep the five suggestions at 3 + 2 instead of 4 + 1.
        let minimumWidth: CGFloat = 190
        #else
        let minimumWidth: CGFloat = 150
        #endif
        return isAccessibilityLayout
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: minimumWidth), spacing: 10)]
    }

    private func actionCard(_ action: GradeyAIAction, icon: String) -> some View {
        Button {
            Task { await viewModel.selectAction(action) }
        } label: {
            suggestionCardLabel(action: action, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("gradeyAIAction-\(action.rawValue)")
    }

    private var subjectCard: some View {
        Menu {
            ForEach(viewModel.availableSubjects) { subject in
                Button(subject.name) {
                    Task { await viewModel.selectAction(.subjectHelp, subjectID: subject.id) }
                }
            }
        } label: {
            suggestionCardLabel(action: .subjectHelp, icon: "book-02")
        }
        .gradeyAIPlainMenu()
        .disabled(isBusy || viewModel.availableSubjects.isEmpty)
        .accessibilityIdentifier("gradeyAIAction-\(GradeyAIAction.subjectHelp.rawValue)")
    }

    private var testCard: some View {
        Menu {
            ForEach(viewModel.availableEvents, id: \.id) { event in
                Button(event.title) {
                    Task {
                        await viewModel.selectAction(
                            .testPreparation,
                            subjectID: event.subjectID,
                            eventID: UUID(uuidString: event.id)
                        )
                    }
                }
            }
        } label: {
            suggestionCardLabel(action: .testPreparation, icon: "check-list")
        }
        .gradeyAIPlainMenu()
        .disabled(isBusy || viewModel.availableEvents.isEmpty)
        .accessibilityIdentifier("gradeyAIAction-\(GradeyAIAction.testPreparation.rawValue)")
    }

    private func suggestionCardLabel(action: GradeyAIAction, icon: String) -> some View {
        GradeyAISuggestionCard(
            title: AppL10n.string(String.LocalizationValue(action.titleKey)),
            icon: icon
        )
    }

    private var starterPrompts: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(viewModel.starterPrompts, id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        GradelyIcon("sparkles", size: 15)
                            .foregroundStyle(Brand.gradient)
                        Text(prompt)
                            .font(.gradely(.subheadline).weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        GradelyIcon("arrow-up-right-01", size: 14)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gradeyAIGlass(cornerRadius: 20, tint: 0.05, interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !viewModel.canAffordSelectedAction)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIStarterPrompts")
    }

    private var focusedAction: some View {
        let action = viewModel.contextSelection.action
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                GradelyIcon(Self.icon(for: action), size: 18)
                    .foregroundStyle(Brand.gradient)
                    .frame(width: 38, height: 38)
                    .background(Brand.primary.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppL10n.string(String.LocalizationValue(action.titleKey)))
                        .font(.gradely(.headline))
                    if let name = viewModel.selectedContextName {
                        Text(name)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    Task { await viewModel.selectAction(.reply, prompt: viewModel.draft) }
                } label: {
                    GradelyIcon("cancel-01", size: 13)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(AppL10n.string("gradey.ai.action.reply"))
                .accessibilityIdentifier("gradeyAIResetActionButton")
            }

            if let summary = viewModel.localTomorrowSummary {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("gradey.ai.context.localTomorrow")
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(Brand.primary)
                    Text(summary)
                        .font(.gradely(.footnote).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gradeyAILocalTomorrow")
            }

            starterPrompts
        }
        .padding(Spacing.lg)
        .gradeyAIGlass(cornerRadius: 26, tint: 0.06)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Brand.gradient, lineWidth: 1)
                .opacity(0.35)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Dock

    private var dock: some View {
        VStack(spacing: Spacing.sm) {
            if showsUpgradeCTA {
                upgradeCTA
            }
            if !isAccessibilityLayout {
                contextBar
            }
            composer
            quotaLine
        }
        .padding(.horizontal, 16)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    contextMenu
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: Spacing.sm)
                    costLabel
                        .fixedSize(horizontal: true, vertical: false)
                    refreshButton
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    contextMenu
                    HStack(spacing: Spacing.sm) {
                        costLabel
                        Spacer(minLength: 0)
                        refreshButton
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                GradelyIcon("shield-01", size: 12)
                    .foregroundStyle(Brand.primary.opacity(0.85))
                    .accessibilityHidden(true)
                Text(viewModel.selectedSharingSummary)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xs)

            contextNotices
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIContextStatus")
    }

    @ViewBuilder
    private var contextNotices: some View {
        if let contextError = viewModel.contextError {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                GradelyIcon(systemName: "exclamationmark.triangle.fill", size: 12)
                    .foregroundStyle(Color.gradelySystemOrange)
                    .accessibilityHidden(true)
                Text(contextError)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xs)
        }

        if viewModel.contextSelection.action == .testPreparation && viewModel.contextSelection.eventID != nil {
            Toggle(AppL10n.string("gradey.ai.context.includeNotes"), isOn: Binding(
                get: { viewModel.contextSelection.includeNotes },
                set: { value in
                    Task {
                        await viewModel.selectAction(
                            .testPreparation,
                            subjectID: viewModel.contextSelection.subjectID,
                            eventID: viewModel.contextSelection.eventID,
                            includeNotes: value,
                            prompt: viewModel.draft
                        )
                    }
                }
            ))
            .font(.gradely(.caption))
            .tint(Brand.primary)
            .disabled(isBusy)
            .padding(.horizontal, Spacing.xs)
        }

        if !viewModel.isConversationPurposeCompatible {
            Text(AppL10n.string("gradey.ai.context.newPurpose"))
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xs)
        }

        if let pending = viewModel.pendingRecoveryMessage {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(pending)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(AppL10n.string("gradey.ai.compute.checkRequest")) {
                    Task { await viewModel.recoverPendingRequest() }
                }
                .font(.gradely(.caption).weight(.semibold))
                .tint(Brand.primary)
                .disabled(viewModel.isRecoveringRequest)
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    private var contextMenu: some View {
        Menu {
            ForEach([GradeyAIAction.reply, .tomorrow, .studyPriorities, .weekSummary], id: \.rawValue) { action in
                Button(AppL10n.string(String.LocalizationValue(action.titleKey))) {
                    Task { await viewModel.selectAction(action, prompt: viewModel.draft) }
                }
            }
            Menu(AppL10n.string(String.LocalizationValue(GradeyAIAction.subjectHelp.titleKey))) {
                ForEach(viewModel.availableSubjects) { subject in
                    Button(subject.name) {
                        Task { await viewModel.selectAction(.subjectHelp, subjectID: subject.id, prompt: viewModel.draft) }
                    }
                }
            }
            .disabled(viewModel.availableSubjects.isEmpty)
            Menu(AppL10n.string(String.LocalizationValue(GradeyAIAction.testPreparation.titleKey))) {
                ForEach(viewModel.availableEvents, id: \.id) { event in
                    Button(event.title) {
                        Task {
                            await viewModel.selectAction(
                                .testPreparation,
                                subjectID: event.subjectID,
                                eventID: UUID(uuidString: event.id),
                                prompt: viewModel.draft
                            )
                        }
                    }
                }
            }
            .disabled(viewModel.availableEvents.isEmpty)
        } label: {
            contextChipLabel
        }
        .gradeyAIPlainMenu()
        .disabled(isBusy)
        .accessibilityLabel(contextMenuAccessibilityLabel)
        .accessibilityIdentifier("gradeyAIContextSelectionMenu")
    }

    private var contextChipLabel: some View {
        let action = viewModel.contextSelection.action
        return HStack(spacing: 6) {
            GradelyIcon(Self.icon(for: action), size: 14)
                .foregroundStyle(Brand.gradient)
            Text(AppL10n.string(String.LocalizationValue(action.titleKey)))
                .font(.gradely(.footnote).weight(.semibold))
                .foregroundStyle(.primary)
            if let name = viewModel.selectedContextName {
                Text(name)
                    .font(.gradely(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GradelyIcon("arrow-down-01", size: 12)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .contentShape(Capsule())
        .glassEffect(.regular.tint(Brand.primary.opacity(0.12)).interactive(), in: Capsule())
    }

    private var contextMenuAccessibilityLabel: String {
        let actionTitle = AppL10n.string(String.LocalizationValue(viewModel.contextSelection.action.titleKey))
        return [AppL10n.string("gradey.ai.context.chooseAction"), actionTitle, viewModel.selectedContextName]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var costLabel: some View {
        Text(
            viewModel.selectedActionCost == Int.max
                ? AppL10n.string("gradey.ai.compute.actionUnavailable")
                : String.localizedStringWithFormat(
                    AppL10n.string("gradey.ai.compute.actionCost"),
                    viewModel.selectedActionCost
                )
        )
        .font(.gradely(.caption).monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshContext() }
        } label: {
            Group {
                if viewModel.isRefreshingContext {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    GradelyIcon(systemName: "arrow.clockwise", size: 15)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(viewModel.isRefreshingContext || isBusy)
        .accessibilityLabel(AppL10n.string("gradey.ai.context.refresh"))
        .accessibilityIdentifier("gradeyAIContextRefreshButton")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField(AppL10n.string("gradey.ai.composer.placeholder"), text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.gradely(.body))
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit {
                    guard viewModel.canSend else { return }
                    Task { await viewModel.send() }
                }
                .padding(.vertical, 9)
                .accessibilityIdentifier("gradeyAIComposer")

            composerActionButton
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .gradeyAIGlass(cornerRadius: 26, tint: 0.08)
        .gradeyAIGlowBorder(
            cornerRadius: 26,
            isActive: isComposerFocused || viewModel.isStreaming,
            isAnimating: viewModel.isStreaming
        )
    }

    @ViewBuilder
    private var composerActionButton: some View {
        if viewModel.isStreaming {
            Button {
                viewModel.stop()
            } label: {
                GradeyAIComposerButton(icon: "stop", isEnabled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string("gradey.ai.stop"))
            .accessibilityIdentifier("gradeyAIStopButton")
        } else {
            Button {
                Task { await viewModel.send() }
            } label: {
                GradeyAIComposerButton(icon: "arrow-up-01", isEnabled: viewModel.canSend)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.messages.count)
            .accessibilityLabel(AppL10n.string("gradey.ai.send"))
            .accessibilityIdentifier("gradeyAISendButton")
        }
    }

    private var quotaLine: some View {
        let isEmpty = (viewModel.status?.remaining ?? 0) == 0
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if hasEarlyAccess {
                    GradeyAIEarlyAccessBadge()
                }
                Text(
                    [GradeyAIQuotaText.remaining(viewModel.status), GradeyAIQuotaText.reset(viewModel.status)]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.gradely(.caption2).weight(.medium).monospacedDigit())
                .foregroundStyle(isEmpty ? GradeBand.poor.foregroundColor : Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gradeyAIRemainingMessages")

            if viewModel.draft.count > 1_800 {
                Text("\(viewModel.draft.count)/2000")
                    .font(.gradely(.caption2).monospacedDigit())
                    .foregroundStyle(viewModel.draft.count > 2_000 ? GradeBand.poor.foregroundColor : .secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var upgradeCTA: some View {
        Button(action: onUpgrade) {
            HStack(spacing: Spacing.md) {
                GradelyIcon("favourite", size: 16)
                    .foregroundStyle(Brand.gradient)
                    .frame(width: 32, height: 32)
                    .background(Brand.primary.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("gradey.ai.compute.upgrade")
                        .font(.gradely(.footnote).weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("gradey.ai.limit.upgrade.action")
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(Brand.primary)
                }
                Spacer(minLength: 0)
                GradelyIcon("arrow-right-01", size: 14)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
            .gradeyAIGlass(cornerRadius: 20, tint: 0.14, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gradeyAISupportUpgradeButton")
    }

    // MARK: - Helpers

    static func icon(for action: GradeyAIAction) -> String {
        switch action {
        case .reply: "sparkles"
        case .tomorrow: "sun-01"
        case .studyPriorities: "target-02"
        case .weekSummary: "calendar-check-in-02"
        case .subjectHelp: "book-02"
        case .testPreparation: "check-list"
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }
}

/// Glass suggestion tile with a gradient icon and rim.
private struct GradeyAISuggestionCard: View {
    let title: String
    let icon: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GradelyIcon(icon, size: 18)
                .foregroundStyle(Brand.gradient)
                .frame(width: 36, height: 36)
                .background(Brand.primary.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(.gradely(.subheadline).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .contentShape(Rectangle())
        .gradeyAIGlass(cornerRadius: 22, tint: 0.06, interactive: isEnabled)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.gradient, lineWidth: 1)
                .opacity(0.3)
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private extension View {
    /// Keeps custom menu labels unstyled on every platform.
    func gradeyAIPlainMenu() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(.plain)
            #if os(macOS)
            .menuIndicator(.hidden)
            #endif
    }

    /// Softens where scrolling content meets the top bar and the dock.
    func gradeyAIScrollEdgeFade() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
        }
    }
}
