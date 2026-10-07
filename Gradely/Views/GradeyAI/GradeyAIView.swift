import SwiftUI

/// Gradey AI sheet. Opens straight into a new chat once consent is given;
/// past chats and data controls live in the History sheet.
struct GradeyAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GradeyAIViewModel
    @State private var supportViewModel: SupportTipViewModel
    @State private var isSupportPresented = false
    @State private var isHistoryPresented = false
    @State private var didCompleteGuestSignIn = false

    private let isGuestMode: Bool
    private let authClient: any GradeyAuthClient
    private let onGuestSignedIn: (() async -> Void)?

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
        .gradelyMacSheetSize(minWidth: 560, idealWidth: 720, minHeight: 520, idealHeight: 660)
    }

    private var signInContent: some View {
        ModalNavigationContainer {
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
        ModalNavigationContainer {
            ZStack {
                GradeyAIBackground(isActive: viewModel.isStreaming || viewModel.isPreparingReply)

                VStack(spacing: 0) {
                    topBar

                    if viewModel.status != nil, let errorMessage = viewModel.errorMessage {
                        GradeyAIBanner(kind: .error, message: errorMessage) {
                            viewModel.clearError()
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("gradeyAIInlineError")
                        .padding(.horizontal, 16)
                        .padding(.bottom, Spacing.sm)
                        .frame(maxWidth: 760)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    content
                        .frame(maxHeight: .infinity)
                }
                .animation(.easeOut(duration: 0.2), value: viewModel.errorMessage)
            }
            .settingsModalNavigationChrome()
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
        .onChange(of: viewModel.hasConsent) {
            if !viewModel.hasConsent { isHistoryPresented = false }
        }
        .sheet(isPresented: $isSupportPresented, onDismiss: {
            Task {
                await supportViewModel.refreshEntitlement()
                applySupportTierFromCatalog()
                await viewModel.refreshStatus(refreshEntitlement: true)
                applySupportTierFromCatalog()
            }
        }) {
            SupportTipView(viewModel: supportViewModel)
        }
        .sheet(isPresented: $isHistoryPresented) {
            GradeyAIHistorySheet(
                viewModel: viewModel,
                hasEarlyAccess: supportViewModel.entitlement.hasEarlyAccess
            )
        }
        .accessibilityIdentifier("gradeyAIView")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.status == nil {
            GradeyAIProgressState(message: "gradey.ai.loading")
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("gradeyAILoading")
        } else if let status = viewModel.status {
            if status.consentRequired {
                GradeyAIConsentScreen(viewModel: viewModel)
            } else {
                GradeyAIChatScreen(
                    viewModel: viewModel,
                    hasEarlyAccess: supportViewModel.entitlement.hasEarlyAccess,
                    showsUpgradeCTA: showsSupportUpgradeCTA,
                    onUpgrade: { isSupportPresented = true }
                )
            }
        } else {
            GradeyAIUnavailableState(
                title: AppL10n.string("gradey.ai.loadFailed.title"),
                message: viewModel.errorMessage ?? AppL10n.string("gradey.ai.loadFailed.message"),
                onRetry: { Task { await viewModel.bootstrap() } }
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            title
                .padding(.horizontal, 44 * 2 + Spacing.sm * 2)

            HStack(spacing: Spacing.sm) {
                if viewModel.hasConsent {
                    GradeyAICircleButton(
                        icon: "message-multiple-01",
                        accessibilityLabel: AppL10n.string("gradey.ai.history.open")
                    ) {
                        isHistoryPresented = true
                    }
                    .accessibilityIdentifier("gradeyAIHistoryButton")
                }

                Spacer(minLength: 0)

                if viewModel.hasConsent {
                    GradeyAICircleButton(
                        icon: "edit-02",
                        accessibilityLabel: AppL10n.string("gradey.ai.newChat")
                    ) {
                        viewModel.beginDraftChat()
                    }
                    .disabled(!viewModel.canStartNewChat)
                    .accessibilityIdentifier("gradeyAINewChatButton")
                }

                GradeyAICircleButton(icon: "cancel-01", accessibilityLabel: AppL10n.string("action.ok")) {
                    viewModel.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("modalDismissButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private var title: some View {
        if let conversation = viewModel.currentConversation, !viewModel.isDraftChat {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
        } else {
            HStack(spacing: Spacing.sm) {
                GradeyAIOrb(size: 22, isActive: viewModel.isStreaming)
                Text("gradey.ai.title")
                    .font(.gradelyDisplay(size: 19, relativeTo: .headline))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    // MARK: - Support

    private var showsSupportUpgradeCTA: Bool {
        (viewModel.status?.remaining ?? 1) == 0 && supportViewModel.entitlement.tier.canUpgrade
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
}
