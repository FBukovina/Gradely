import SwiftUI

struct StravaCZView: View {
    @State private var viewModel: StravaCZViewModel

    init(repository: StravaCZRepository) {
        _viewModel = State(initialValue: StravaCZViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "stravacz.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if viewModel.phase == .signedIn {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await viewModel.refresh(forceRefresh: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                            }
                            .disabled(viewModel.isBusy)
                            .accessibilityLabel(String(localized: "action.refresh"))
                            .accessibilityIdentifier("stravaCZRefreshButton")
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button(role: .destructive) {
                                    Task { await viewModel.disconnect() }
                                } label: {
                                    Label(String(localized: "stravacz.disconnect"), systemImage: "rectangle.portrait.and.arrow.right")
                                }
                                .accessibilityIdentifier("stravaCZDisconnectButton")
                            } label: {
                                Image(systemName: "fork.knife.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Brand.primary)
                            }
                            .accessibilityLabel(String(localized: "stravacz.account.menu"))
                            .accessibilityIdentifier("stravaCZAccountMenuButton")
                        }
                    }
                }
        }
        .task {
            await viewModel.bootstrap()
        }
        .alert(String(localized: "error.title"), isPresented: errorBinding) {
            Button(String(localized: "action.ok"), role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "stravacz.replace.title"),
            isPresented: replacementDialogBinding,
            titleVisibility: .visible
        ) {
            if viewModel.pendingReplacement != nil {
                Button(String(localized: "stravacz.replace.confirm")) {
                    Task { await viewModel.confirmReplacement() }
                }
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            if let replacement = viewModel.pendingReplacement {
                Text(String(
                    format: String(localized: "stravacz.replace.message"),
                    replacement.existingMeal.name,
                    replacement.newMeal.name
                ))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .checking:
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text("stravacz.checking")
            }
            .accessibilityIdentifier("stravaCZCheckingView")
        case .signedOut:
            connectView
        case .signedIn:
            menuView
        }
    }

    private var connectView: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Brand.onAccent)
                            .frame(width: 64, height: 64)
                            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .shadow(color: Brand.primary.opacity(0.35), radius: 14, x: 0, y: 8)
                            .accessibilityHidden(true)

                        Text("stravacz.connect.title")
                            .font(.title.bold())
                            .foregroundStyle(.primary)

                        Text("stravacz.connect.message")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Card {
                        VStack(spacing: Spacing.lg) {
                            TextField(String(localized: "stravacz.canteenNumber"), text: $viewModel.canteenNumber)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .submitLabel(.next)
                                .brandField()
                                .accessibilityIdentifier("stravaCZCanteenField")

                            TextField(String(localized: "stravacz.username"), text: $viewModel.username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .brandField()
                                .accessibilityIdentifier("stravaCZUsernameField")

                            passwordField

                            Button {
                                Task { await viewModel.connect() }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    if viewModel.isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(Brand.onAccent)
                                    }
                                    Text(viewModel.isConnecting ? String(localized: "stravacz.connect.loading") : String(localized: "stravacz.connect.button"))
                                    if !viewModel.isConnecting {
                                        Image(systemName: "chevron.right")
                                            .font(.subheadline.weight(.bold))
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(viewModel.isConnecting)
                            .accessibilityIdentifier("stravaCZConnectButton")
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("stravaCZConnectView")
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if viewModel.isPasswordVisible {
                    TextField(String(localized: "stravacz.password"), text: $viewModel.password)
                } else {
                    SecureField(String(localized: "stravacz.password"), text: $viewModel.password)
                }
            }
            .textContentType(.password)
            .submitLabel(.done)
            .accessibilityIdentifier("stravaCZPasswordField")

            Button {
                viewModel.isPasswordVisible.toggle()
            } label: {
                Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(viewModel.isPasswordVisible ? String(localized: "login.hidePassword") : String(localized: "login.showPassword"))
            }
            .buttonStyle(.plain)
        }
        .brandField()
    }

    @ViewBuilder
    private var menuView: some View {
        if viewModel.isLoading && viewModel.menu == nil {
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text("stravacz.menu.loading")
            }
            .accessibilityIdentifier("stravaCZLoadingView")
        } else if let menu = viewModel.menu, menu.days.isEmpty {
            ContentUnavailableView(
                String(localized: "stravacz.menu.empty.title"),
                systemImage: "fork.knife",
                description: Text("stravacz.menu.empty.message")
            )
            .accessibilityIdentifier("stravaCZEmptyView")
        } else {
            List {
                if let session = viewModel.session {
                    StravaCZHeader(session: session, orderedCount: viewModel.menu?.orderedMeals.count ?? 0)
                        .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("stravacz.menu.refreshing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(viewModel.menu?.days ?? []) { day in
                    Section {
                        ForEach(day.meals) { meal in
                            StravaCZMealRow(
                                meal: meal,
                                isSubmitting: viewModel.submittingMealID == meal.id
                            ) {
                                Task { await viewModel.toggleMeal(meal) }
                            }
                        }
                    } header: {
                        Text(day.displayDate)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .refreshable {
                await viewModel.refresh(forceRefresh: true)
            }
            .accessibilityIdentifier("stravaCZMenuList")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }

    private var replacementDialogBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingReplacement != nil },
            set: { newValue in
                if !newValue {
                    viewModel.pendingReplacement = nil
                }
            }
        )
    }
}

private struct StravaCZHeader: View {
    let session: StravaCZStoredSession
    let orderedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("stravacz.balance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.onAccent.opacity(0.75))

                    Text(session.formattedBalance)
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.onAccent)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .accessibilityIdentifier("stravaCZBalance")
                }

                Spacer()

                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Brand.onAccent.opacity(0.45))
            }

            Divider()
                .overlay(Brand.onAccent.opacity(0.2))

            HStack(spacing: Spacing.md) {
                StatTile(
                    title: String(localized: "stravacz.ordered"),
                    value: "\(orderedCount)",
                    systemImage: "checkmark.circle.fill"
                )
                StatTile(
                    title: String(localized: "stravacz.canteen"),
                    value: session.canteenName ?? session.canteenNumber,
                    systemImage: "building.2.fill"
                )
            }
        }
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

private struct StravaCZMealRow: View {
    let meal: StravaCZMeal
    let isSubmitting: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    StatusChip(text: meal.type.localizedTitle, color: meal.type == .soup ? .secondary : Brand.primary)
                    if meal.orderType != .normal {
                        StatusChip(text: meal.orderType.localizedTitle, color: meal.orderType == .restricted ? GradeBand.poor.foregroundColor : GradeBand.average.foregroundColor)
                    }
                    if meal.ordered {
                        StatusChip(text: String(localized: "stravacz.meal.ordered"), color: GradeBand.excellent.foregroundColor)
                    }
                }

                Text(meal.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    Label(meal.formattedPrice, systemImage: "creditcard.fill")
                    if !meal.allergenText.isEmpty {
                        Label(meal.allergenText, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if meal.canModify {
                Button(action: onToggle) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(meal.ordered ? String(localized: "stravacz.meal.cancel") : String(localized: "stravacz.meal.order"))
                            .accessibilityIdentifier(meal.ordered ? "stravaCZCancelButton-\(meal.id)" : "stravaCZOrderButton-\(meal.id)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(meal.ordered ? GradeBand.poor.foregroundColor : Brand.primary)
                .disabled(isSubmitting)
                .accessibilityLabel(meal.ordered ? String(localized: "stravacz.meal.cancel") : String(localized: "stravacz.meal.order"))
                .accessibilityIdentifier(meal.ordered ? "stravaCZCancelButton-\(meal.id)" : "stravaCZOrderButton-\(meal.id)")
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .accessibilityLabel(String(localized: "stravacz.meal.readOnly"))
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

#Preview("Connect") {
    StravaCZView(repository: AppEnvironment.makeMockStravaCZRepository())
}

#Preview("Menu") {
    StravaCZView(repository: AppEnvironment.makeMockStravaCZRepository(session: PreviewData.stravaCZSession))
}
