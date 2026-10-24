import SwiftUI

struct StravaCZView: View {
    @State private var viewModel: StravaCZViewModel
    private let repository: StravaCZRepository
    private let onOpenGradeyAI: () -> Void

    init(
        repository: StravaCZRepository,
        linkedAccountRepository: LinkedAccountRepository? = nil,
        onOpenGradeyAI: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.onOpenGradeyAI = onOpenGradeyAI
        _viewModel = State(initialValue: StravaCZViewModel(
            repository: repository,
            linkedAccountRepository: linkedAccountRepository
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(AppL10n.string("stravacz.title"))
                .gradelyNavigationTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .gradelyTopBarLeading) {
                        GradeyAIToolbarButton(onOpen: onOpenGradeyAI)
                    }

                    #if !os(macOS)
                    ToolbarItem(placement: .gradelyTopBarTrailing) {
                        AccountSettingsButton()
                    }
                    #endif

                    if viewModel.phase == .signedIn {
                        ToolbarItem(placement: .gradelyTopBarTrailing) {
                            Button {
                                Task { await viewModel.refresh(forceRefresh: true) }
                            } label: {
                                GradelyIcon(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                            }
                            .disabled(viewModel.isBusy)
                            .accessibilityLabel(AppL10n.string("action.refresh"))
                            .accessibilityIdentifier("stravaCZRefreshButton")
                        }
                    }
                }
        }
        .task {
            await viewModel.bootstrap()
        }
        .gradelyOnRefreshCommand { await viewModel.refresh(forceRefresh: true) }
        .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
            Button(AppL10n.string("action.ok"), role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            AppL10n.string("stravacz.replace.title"),
            isPresented: replacementDialogBinding,
            titleVisibility: .visible
        ) {
            if viewModel.pendingReplacement != nil {
                Button(AppL10n.string("stravacz.replace.confirm")) {
                    Task { await viewModel.confirmReplacement() }
                }
            }
            Button(AppL10n.string("action.cancel"), role: .cancel) {}
        } message: {
            if let replacement = viewModel.pendingReplacement {
                Text(String(
                    format: AppL10n.string("stravacz.replace.message"),
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
            StravaCZConnectView(
                repository: repository,
                initialCanteenNumber: viewModel.canteenNumber,
                initialUsername: viewModel.username,
                usesScreenBackground: true
            ) { session in
                await viewModel.didConnect(session)
            }
        case .signedIn:
            menuView
        }
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
            ContentUnavailableView {
                GradelyLabel(
                    AppL10n.string("stravacz.menu.empty.title"),
                    systemImage: "fork.knife",
                    iconSize: 28
                )
            } description: {
                Text("stravacz.menu.empty.message")
            }
            .accessibilityIdentifier("stravaCZEmptyView")
        } else {
            List {
                if let session = viewModel.session {
                    StravaCZHeader(session: session, orderedCount: viewModel.menu?.orderedMeals.count ?? 0)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if viewModel.isRefreshing {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("stravacz.menu.refreshing")
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(viewModel.menu?.days ?? []) { day in
                    StravaCZDayCard(
                        day: day,
                        submittingMealID: viewModel.submittingMealID
                    ) { meal in
                        Task { await viewModel.toggleMeal(meal) }
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.md, trailing: Spacing.lg))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .gradelyScreenBackground()
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
    @ScaledMetric(relativeTo: .largeTitle) private var balanceFontSize: CGFloat = 42

    let session: StravaCZStoredSession
    let orderedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("stravacz.balance")
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(session.formattedBalance)
                    .font(.gradely(size: balanceFontSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .accessibilityIdentifier("stravaCZBalance")
            }

            HStack(spacing: Spacing.md) {
                StatTile(
                    title: AppL10n.string("stravacz.ordered"),
                    value: "\(orderedCount)",
                    systemImage: "checkmark.circle.fill"
                )
                StatTile(
                    title: AppL10n.string("stravacz.canteen"),
                    value: session.canteenName ?? session.canteenNumber,
                    systemImage: "building.2.fill"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
    }
}

private struct StravaCZDayCard: View {
    let day: StravaCZMenuDay
    let submittingMealID: Int?
    let onToggle: (StravaCZMeal) -> Void

    var body: some View {
        PlainSection {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(verbatim: weekdayText ?? day.displayDate)
                    .font(.gradely(.title3).weight(.bold))
                    .foregroundStyle(.primary)
                if let date {
                    Text(verbatim: SchoolDateFormatting.shortDate(date))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } content: {
            ForEach(day.meals.indices, id: \.self) { index in
                let meal = day.meals[index]
                StravaCZMealRow(
                    meal: meal,
                    isSubmitting: submittingMealID == meal.id
                ) {
                    onToggle(meal)
                }
            }
        }
    }

    /// "Monday" / "Pondělí"
    private var weekdayText: String? {
        guard let date else { return nil }

        let formatter = DateFormatter()
        formatter.locale = AppLanguageOverride.locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        return weekday.prefix(1).uppercased() + weekday.dropFirst()
    }

    private var date: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day.dateKey)
    }
}

private struct StravaCZMealRow: View {
    let meal: StravaCZMeal
    let isSubmitting: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(meal.type.localizedTitle)
                    .font(.gradely(.caption2).weight(.bold))
                    .foregroundStyle(meal.type == .main ? Brand.primary : .secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background((meal.type == .main ? Brand.primary : Color.secondary).opacity(0.10), in: Capsule())

                Text(meal.name)
                    .font(meal.type == .main ? .gradely(.headline).weight(.semibold) : .gradely(.subheadline).weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    GradelyLabel(meal.formattedPrice, systemImage: "creditcard.fill")
                    if !meal.allergenText.isEmpty {
                        GradelyLabel(meal.allergenText, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if meal.canModify {
                StravaCZMealSelectionButton(
                    meal: meal,
                    isSubmitting: isSubmitting,
                    onToggle: onToggle
                )
            } else if meal.ordered {
                StravaCZMealOrderedIndicator(mealID: meal.id)
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct StravaCZMealSelectionButton: View {
    let meal: StravaCZMeal
    let isSubmitting: Bool
    let onToggle: () -> Void

    #if os(macOS)
    // Checkbox-sized for a pointer.
    private let boxSize: CGFloat = 20
    private let tapSize: CGFloat = 28
    private let cornerRadius: CGFloat = 5
    #else
    private let boxSize: CGFloat = 36
    private let tapSize: CGFloat = 44
    private let cornerRadius: CGFloat = 8
    #endif

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(meal.ordered ? Brand.primary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(meal.ordered ? Brand.primary : Color.secondary.opacity(0.55), lineWidth: boxSize < 30 ? 1.5 : 2)
                    )

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(meal.ordered ? Brand.onAccent : Brand.primary)
                } else if meal.ordered {
                    GradelyIcon(systemName: "checkmark", size: boxSize * 0.42)
                        .foregroundStyle(Brand.onAccent)
                }
            }
            .frame(width: boxSize, height: boxSize)
            .frame(width: tapSize, height: tapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityLabel(meal.ordered ? AppL10n.string("stravacz.meal.cancel") : AppL10n.string("stravacz.meal.order"))
        .accessibilityIdentifier(meal.ordered ? "stravaCZCancelButton-\(meal.id)" : "stravaCZOrderButton-\(meal.id)")
    }
}

private struct StravaCZMealOrderedIndicator: View {
    let mealID: Int

    var body: some View {
        GradelyIcon(systemName: "checkmark.circle.fill", size: 28)
            .foregroundStyle(Brand.primary)
            .frame(width: 40, height: 40)
            .accessibilityLabel(AppL10n.string("stravacz.meal.ordered"))
            .accessibilityIdentifier("stravaCZOrderedIndicator-\(mealID)")
    }
}

#Preview("Connect") {
    StravaCZView(repository: AppEnvironment.makeMockStravaCZRepository())
}

#Preview("Menu") {
    StravaCZView(repository: AppEnvironment.makeMockStravaCZRepository(session: PreviewData.stravaCZSession))
}
