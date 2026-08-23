import SwiftUI

struct GradeyAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GradeyAIViewModel
    @State private var supportViewModel: SupportTipViewModel
    @State private var pendingConversationDeletion: GradeyAIConversation?
    @State private var dangerousAction: DangerousAction?
    @State private var isSupportPresented = false
    @State private var didCompleteGuestSignIn = false
    @FocusState private var isComposerFocused: Bool

    private let isGuestMode: Bool
    private let authClient: any GradeyAuthClient
    private let onGuestSignedIn: (() async -> Void)?

    private enum DangerousAction {
        case deleteAll
        case revokeConsent
    }

    init(
        viewModel: GradeyAIViewModel,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        isSignedIn: Bool = false,
        isGuestMode: Bool = false,
        authClient: any GradeyAuthClient = MockGradeyAuthClient(session: nil),
        onGuestSignedIn: (() async -> Void)? = nil
    ) {
        self.isGuestMode = isGuestMode
        self.authClient = authClient
        self.onGuestSignedIn = onGuestSignedIn
        _viewModel = State(initialValue: viewModel)
        _supportViewModel = State(initialValue: SupportTipViewModel(
            supportTipProvider: supportTipProvider,
            isSignedIn: isSignedIn
        ))
    }

    private var needsSignIn: Bool {
        isGuestMode && !didCompleteGuestSignIn
    }

    var body: some View {
        Group {
            if needsSignIn {
                signInContent
            } else {
                aiContent
            }
        }
    }

    private var signInContent: some View {
        NavigationStack {
            GradeyIDLoginView(
                authClient: authClient,
                subtitleKey: "gradey.ai.signIn.subtitle"
            ) {
                Task { await completeGuestSignIn() }
            }
        }
        .gradelyModalDismissButton {
            dismiss()
        }
        .accessibilityIdentifier("gradeyAISignInView")
    }

    private var aiContent: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                content
            }
            .navigationTitle(navigationTitle)
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
        }
        .gradelyModalDismissButton {
            viewModel.stop()
            dismiss()
        }
        .task {
            guard !needsSignIn else { return }
            async let bootstrap: Void = viewModel.bootstrap()
            async let catalog: Void = supportViewModel.loadIfNeeded()
            _ = await (bootstrap, catalog)
            applySupportTierFromCatalog()
        }
        .onChange(of: supportViewModel.entitlement) {
            applySupportTierFromCatalog()
        }
        .sheet(isPresented: $isSupportPresented, onDismiss: {
            Task {
                await supportViewModel.refreshEntitlement()
                applySupportTierFromCatalog()
                await viewModel.refreshStatus()
                applySupportTierFromCatalog()
            }
        }) {
            SupportTipView(viewModel: supportViewModel)
        }
        .confirmationDialog(
            AppL10n.string("gradey.ai.conversation.delete.title"),
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            if let conversation = pendingConversationDeletion {
                Button(AppL10n.string("gradey.ai.conversation.delete.action"), role: .destructive) {
                    pendingConversationDeletion = nil
                    Task { await viewModel.delete(conversation) }
                }
            }
            Button(AppL10n.string("action.cancel"), role: .cancel) {
                pendingConversationDeletion = nil
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
                    Task { await viewModel.revokeConsent() }
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
        .accessibilityIdentifier("gradeyAIView")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.status == nil {
            loadingView
        } else if let status = viewModel.status {
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    inlineErrorBanner(errorMessage)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.sm)
                }

                Group {
                    if status.consentRequired {
                        consentView
                    } else if viewModel.currentConversation != nil {
                        chatView
                    } else {
                        conversationListView
                    }
                }
            }
        } else {
            unavailableView(
                title: AppL10n.string("gradey.ai.loadFailed.title"),
                message: viewModel.errorMessage ?? AppL10n.string("gradey.ai.loadFailed.message")
            )
        }
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            GradelyIcon(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GradeBand.poor.foregroundColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                viewModel.clearError()
            } label: {
                GradelyModalCloseLabel(size: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string("action.done"))
            .accessibilityIdentifier("gradeyAIErrorDismissButton")
        }
        .padding(Spacing.md)
        .background(
            GradeBand.poor.foregroundColor.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(GradeBand.poor.foregroundColor.opacity(0.18), lineWidth: 1)
        }
        .accessibilityIdentifier("gradeyAIInlineError")
    }

    private var navigationTitle: String {
        viewModel.currentConversation?.title ?? AppL10n.string("gradey.ai.title")
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        if viewModel.currentConversation != nil {
            ToolbarItem(placement: .gradelyTopBarLeading) {
                Button {
                    viewModel.closeConversation()
                } label: {
                    GradelyIcon(systemName: "chevron.left")
                }
                .accessibilityLabel(AppL10n.string("gradey.ai.conversations.back"))
                .accessibilityIdentifier("gradeyAIConversationBackButton")
            }
        }

        if viewModel.hasConsent {
            ToolbarItem(placement: .gradelyTopBarTrailing) {
                Menu {
                    if let conversation = viewModel.currentConversation {
                        Button(role: .destructive) {
                            pendingConversationDeletion = conversation
                        } label: {
                            GradelyLabel(AppL10n.string("gradey.ai.conversation.delete.action"), systemImage: "trash")
                        }
                    }

                    Button(role: .destructive) {
                        dangerousAction = .deleteAll
                    } label: {
                        GradelyLabel(AppL10n.string("gradey.ai.deleteAll.action"), systemImage: "trash.slash")
                    }
                    .disabled(viewModel.conversations.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        dangerousAction = .revokeConsent
                    } label: {
                        GradelyLabel(AppL10n.string("gradey.ai.privacy.revoke.action"), systemImage: "hand.raised.slash")
                    }
                } label: {
                    GradelyIcon(systemName: "ellipsis.circle")
                }
                .disabled(viewModel.isStreaming)
                .accessibilityLabel(AppL10n.string("gradey.ai.options"))
                .accessibilityIdentifier("gradeyAIOptionsButton")
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(Brand.primary)
            Text("gradey.ai.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("gradeyAILoading")
    }

    private func unavailableView(title: String, message: String) -> some View {
        ScrollView {
            Card {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    GradelyIcon(systemName: "sparkles", size: 28)
                        .foregroundStyle(Brand.onAccent)
                        .frame(width: 58, height: 58)
                        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(title)
                            .font(.gradelyDisplay(size: 22, relativeTo: .title2))
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await viewModel.bootstrap() }
                    } label: {
                        GradelyLabel(AppL10n.string("action.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("gradeyAIRetryLoadButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("gradeyAIUnavailable")
    }

    private var serviceAvailabilityBanner: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.gradelySystemOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("gradey.ai.availability.paused.title")
                    .font(.subheadline.weight(.semibold))
                Text("gradey.ai.availability.paused.message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            Color.gradelySystemOrange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Color.gradelySystemOrange.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gradeyAIServiceUnavailableBanner")
    }

    private var consentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                GradeyAIHero(
                    icon: "sparkles",
                    title: "gradey.ai.consent.title",
                    subtitle: "gradey.ai.consent.subtitle"
                ) {
                    EmptyView()
                }

                if viewModel.status?.enabled == false {
                    serviceAvailabilityBanner
                }

                consentDetail(
                    icon: "chart.bar.doc.horizontal",
                    title: "gradey.ai.consent.schoolData.title",
                    message: "gradey.ai.consent.schoolData.message"
                )
                consentDetail(
                    icon: "cloud.fill",
                    title: "gradey.ai.consent.azure.title",
                    message: "gradey.ai.consent.azure.message"
                )
                consentDetail(
                    icon: "clock.arrow.circlepath",
                    title: "gradey.ai.consent.retention.title",
                    message: "gradey.ai.consent.retention.message"
                )

                Text("gradey.ai.disclaimer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await viewModel.acceptConsent() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(Brand.onAccent)
                        }
                        Text("gradey.ai.consent.action")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("gradeyAIConsentButton")
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("gradeyAIConsentView")
    }

    private func consentDetail(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.md) {
                GradelyIcon(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Brand.primary)
                    .frame(width: 38, height: 38)
                    .background(Brand.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var conversationListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                conversationHero

                if viewModel.status?.enabled == false {
                    serviceAvailabilityBanner
                }

                contextStatusCard

                if viewModel.conversations.isEmpty {
                    emptyConversations
                } else {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader("gradey.ai.conversations.title")
                        ForEach(viewModel.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .accessibilityIdentifier("gradeyAIConversationList")
                }

                privacyFootnote
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var conversationHero: some View {
        GradeyAIHero(
            icon: "sparkles",
            title: "gradey.ai.welcome.title",
            subtitle: "gradey.ai.welcome.message"
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    limitLabel(onBrand: true)
                    Spacer(minLength: Spacing.md)
                    Button {
                        viewModel.beginDraftChat()
                    } label: {
                        GradelyLabel(AppL10n.string("gradey.ai.newChat"), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.onAccent)
                    .disabled(!viewModel.canStartNewChat)
                    .accessibilityIdentifier("gradeyAINewChatButton")
                }

                if showsSupportUpgradeCTA {
                    supportUpgradeCTA(onBrand: true)
                }
            }
        }
    }

    private var emptyConversations: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("gradey.ai.empty.title")
                    .font(.headline)
                Text("gradey.ai.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                starterPrompts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("gradeyAIEmptyConversations")
    }

    private func conversationRow(_ conversation: GradeyAIConversation) -> some View {
        Button {
            Task { await viewModel.open(conversation) }
        } label: {
            Card(padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    GradelyIcon(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .foregroundStyle(Brand.primary)
                        .frame(width: 40, height: 40)
                        .background(Brand.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(conversation.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(conversation.lastMessageAt ?? conversation.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Spacing.sm)
                    GradelyIcon(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingConversationDeletion = conversation
            } label: {
                GradelyLabel(AppL10n.string("gradey.ai.conversation.delete.action"), systemImage: "trash")
            }
        }
        .accessibilityIdentifier("gradeyAIConversation-\(conversation.id)")
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            if viewModel.status?.enabled == false {
                serviceAvailabilityBanner
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
            }

            contextStatusCard
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

            if viewModel.isOpeningConversation, viewModel.messages.isEmpty {
                openingConversationView
            } else if viewModel.messages.isEmpty {
                emptyChatBody
            } else {
                messageList
            }

            composer

            if showsSupportUpgradeCTA {
                supportUpgradeCTA()
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
        }
    }

    private var openingConversationView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: Spacing.md)
            ProgressView()
                .controlSize(.large)
                .tint(Brand.primary)
            Text("gradey.ai.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("gradeyAIOpeningConversation")
    }

    private var emptyChatBody: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: Spacing.md)
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("gradey.ai.chat.empty.title")
                    .font(.gradelyDisplay(size: 26, relativeTo: .title2))
                Text("gradey.ai.chat.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                starterPrompts
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            Spacer(minLength: Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        GradeyAIMessageBubble(
                            message: message,
                            canRetry: viewModel.canRetry(message),
                            onRetry: {
                                Task { await viewModel.retry() }
                            }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("gradeyAIMessageBottom")
                }
                .padding(Spacing.lg)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("gradeyAIMessageList")
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

    private var starterPrompts: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(viewModel.starterPrompts, id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        GradelyIcon(systemName: "sparkles")
                            .foregroundStyle(Brand.primary)
                        Text(prompt)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(Spacing.md)
                    .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStreaming || viewModel.status?.canSend != true)
            }
        }
        .accessibilityIdentifier("gradeyAIStarterPrompts")
    }

    private var contextStatusCard: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            GradelyIcon(systemName: contextStatusImage)
                .foregroundStyle(contextStatusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(contextStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let contextError = viewModel.contextError {
                    Text(contextError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let generatedAt = viewModel.contextGeneratedAt {
                    Text(generatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: Spacing.sm)

            Button {
                Task { await viewModel.refreshContext() }
            } label: {
                if viewModel.isRefreshingContext {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    GradelyIcon(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshingContext || viewModel.isStreaming)
            .accessibilityLabel(AppL10n.string("gradey.ai.context.refresh"))
            .accessibilityIdentifier("gradeyAIContextRefreshButton")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(contextStatusColor.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIContextStatus")
    }

    private var contextStatusTitle: String {
        if viewModel.isRefreshingContext {
            return AppL10n.string("gradey.ai.context.refreshing")
        }
        if viewModel.contextSnapshot == nil {
            return AppL10n.string("gradey.ai.context.unavailable")
        }
        if viewModel.contextSnapshot?.isStale == true || viewModel.contextSnapshot?.isPartial == true {
            return AppL10n.string("gradey.ai.context.partial")
        }
        return AppL10n.string("gradey.ai.context.ready")
    }

    private var contextStatusImage: String {
        viewModel.contextSnapshot == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var contextStatusColor: Color {
        viewModel.contextSnapshot == nil || viewModel.contextSnapshot?.isPartial == true
            ? .gradelySystemOrange
            : Brand.primary
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField(AppL10n.string("gradey.ai.composer.placeholder"), text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard viewModel.canSend else { return }
                        Task { await viewModel.send() }
                    }
                    .accessibilityIdentifier("gradeyAIComposer")

                composerActionButton
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                limitLabel()
                Spacer(minLength: 0)
                if viewModel.draft.count > 1_800 {
                    Text("\(viewModel.draft.count)/2000")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(viewModel.draft.count > 2_000 ? GradeBand.poor.foregroundColor : .secondary)
                }
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Brand.primary.opacity(isComposerFocused ? 0.26 : 0.12), lineWidth: 1)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    @ViewBuilder
    private var composerActionButton: some View {
        if viewModel.isStreaming {
            Button {
                viewModel.stop()
            } label: {
                GradelyIcon(systemName: "stop.fill", size: 16)
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Brand.gradient, in: Circle())
            }
            .accessibilityLabel(AppL10n.string("gradey.ai.stop"))
            .accessibilityIdentifier("gradeyAIStopButton")
        } else {
            Button {
                Task { await viewModel.send() }
            } label: {
                GradelyIcon(systemName: "arrow.up", size: 16)
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Brand.gradient, in: Circle())
            }
            .disabled(!viewModel.canSend)
            .opacity(viewModel.canSend ? 1 : 0.38)
            .accessibilityLabel(AppL10n.string("gradey.ai.send"))
            .accessibilityIdentifier("gradeyAISendButton")
        }
    }

    private func limitLabel(onBrand: Bool = false) -> some View {
        let zeroRemaining = (viewModel.status?.remaining ?? 0) == 0
        let primaryColor = onBrand ? Brand.onAccent.opacity(0.78) : (zeroRemaining ? GradeBand.poor.foregroundColor : Color.secondary)
        let secondaryColor = onBrand ? Brand.onAccent.opacity(0.55) : Color.secondary.opacity(0.58)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(limitText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(primaryColor)
                if supportViewModel.entitlement.hasEarlyAccess {
                    Text("gradey.ai.earlyAccess.badge")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(onBrand ? Brand.onAccent : Brand.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (onBrand ? Brand.onAccent : Brand.primary).opacity(onBrand ? 0.18 : 0.12),
                            in: Capsule()
                        )
                        .accessibilityIdentifier("gradeyAIEarlyAccessBadge")
                }
            }
            if let resetText {
                Text(resetText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(secondaryColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gradeyAIRemainingMessages")
    }

    private var showsSupportUpgradeCTA: Bool {
        (viewModel.status?.remaining ?? 1) == 0 && supportViewModel.entitlement.tier.canUpgrade
    }

    private func supportUpgradeCTA(onBrand: Bool = false) -> some View {
        Button {
            isSupportPresented = true
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                GradelyIcon("favourite", size: 15)
                    .foregroundStyle(onBrand ? Brand.onAccent : Brand.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("gradey.ai.limit.upgrade")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(onBrand ? Brand.onAccent : .primary)
                        .multilineTextAlignment(.leading)
                    Text("gradey.ai.limit.upgrade.action")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(onBrand ? Brand.onAccent.opacity(0.78) : Brand.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .background(
                (onBrand ? Brand.onAccent : Brand.primary).opacity(onBrand ? 0.12 : 0.08),
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gradeyAISupportUpgradeButton")
    }

    private var limitText: String {
        guard let status = viewModel.status else { return "" }
        return String.localizedStringWithFormat(
            AppL10n.string("gradey.ai.limit.remaining"),
            Int64(status.remaining),
            Int64(status.dailyLimit)
        )
    }

    private var resetText: String? {
        guard let resetAt = viewModel.status?.resetAt else { return nil }
        return String.localizedStringWithFormat(
            AppL10n.string("gradey.ai.limit.resets"),
            resetAt.formatted(date: .omitted, time: .shortened)
        )
    }

    private var privacyFootnote: some View {
        Label {
            Text("gradey.ai.privacy.footnote")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            GradelyIcon(systemName: "lock.shield.fill")
                .foregroundStyle(Brand.primary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.xs)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("gradeyAIMessageBottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("gradeyAIMessageBottom", anchor: .bottom)
        }
    }

    private func completeGuestSignIn() async {
        if let onGuestSignedIn {
            await onGuestSignedIn()
        }
        supportViewModel.isSignedIn = true
        didCompleteGuestSignIn = true
    }

    private func applySupportTierFromCatalog() {
        switch supportViewModel.loadState {
        case .loaded, .empty:
            viewModel.applySupportTier(supportViewModel.entitlement.tier, catalogLoaded: true)
        case .idle, .loading, .failed:
            if supportViewModel.entitlement.tier != .none {
                viewModel.applySupportTier(supportViewModel.entitlement.tier, catalogLoaded: false)
            }
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingConversationDeletion != nil },
            set: { if !$0 { pendingConversationDeletion = nil } }
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

private struct GradeyAIHero<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                GradelyIcon(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Brand.onAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.gradelyDisplay(size: 26, relativeTo: .title2))
                        .foregroundStyle(Brand.onAccent)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.onAccent.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.24), radius: 16, x: 0, y: 8)
    }
}

private struct GradeyAIMessageBubble: View {
    let message: GradeyAIMessage
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            if message.role == .user {
                Spacer(minLength: 44)
            } else {
                GradelyIcon(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Brand.gradient, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.sm) {
                if message.content.isEmpty, message.status == .streaming {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Brand.primary)
                        .padding(.vertical, Spacing.xs)
                        .accessibilityLabel(AppL10n.string("gradey.ai.responding"))
                } else if message.role == .assistant, message.status == .complete {
                    assistantText
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }

                switch message.status {
                case .failed:
                    if canRetry {
                        Button(action: onRetry) {
                            GradelyLabel(AppL10n.string("action.retry"), systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(GradeBand.poor.foregroundColor)
                        .accessibilityIdentifier("gradeyAIRetryMessageButton")
                    }
                case .cancelled:
                    Text("gradey.ai.response.cancelled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .streaming, .complete:
                    EmptyView()
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIMessage-\(message.id)")
    }

    private var assistantText: some View {
        GradeyAIMarkdownText(markdown: message.content)
    }

    private var bubbleColor: Color {
        message.role == .user ? Brand.primary.opacity(0.16) : Color.gradelySecondaryGroupedBackground
    }
}
