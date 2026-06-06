import SwiftUI

struct SubjectsView: View {
    @State private var viewModel: SubjectsViewModel
    private let repository: BakalariRepository
    private let supportTipProvider: any SupportTipProviding
    let onSignedOut: () -> Void

    init(
        repository: BakalariRepository,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        onSignedOut: @escaping () -> Void
    ) {
        self.repository = repository
        self.supportTipProvider = supportTipProvider
        _viewModel = State(initialValue: SubjectsViewModel(repository: repository))
        self.onSignedOut = onSignedOut
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.subjects.isEmpty {
                    ContentUnavailableView {
                        ProgressView()
                            .controlSize(.large)
                    } description: {
                        Text("subjects.loading")
                    }
                    .accessibilityIdentifier("subjectsLoadingView")
                } else if let errorMessage = viewModel.errorMessage, viewModel.subjects.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "error.title"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(String(localized: "action.retry")) {
                            Task { await viewModel.refresh(forceRefresh: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .accessibilityIdentifier("subjectsErrorView")
                } else if viewModel.subjects.isEmpty {
                    ContentUnavailableView(
                        String(localized: "subjects.empty.title"),
                        systemImage: "list.bullet.rectangle",
                        description: Text("subjects.empty.message")
                    )
                    .accessibilityIdentifier("subjectsEmptyView")
                } else {
                    subjectsList
                }
            }
            .navigationTitle(String(localized: "subjects.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                    }
                    .disabled(viewModel.isLoading || viewModel.isRefreshing)
                    .accessibilityLabel(String(localized: "action.refresh"))
                    .accessibilityIdentifier("refreshButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    AccountMenu(
                        user: viewModel.user,
                        supportTipProvider: supportTipProvider,
                        onSignedOut: onSignedOut
                    )
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailView(
                    viewModel: SubjectDetailViewModel(
                        subject: subject,
                        absence: viewModel.absence(for: subject),
                        repository: repository
                    )
                )
            }
        }
    }

    private var subjectsList: some View {
        List {
            OverviewHeader(viewModel: viewModel)
                .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if viewModel.isRefreshing {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("subjects.refreshing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.subjects) { subject in
                NavigationLink(value: subject) {
                    SubjectCard(subject: subject)
                }
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("subjectRow-\(subject.id)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable {
            await viewModel.refresh(forceRefresh: true)
        }
        .accessibilityIdentifier("subjectsList")
    }

}

// MARK: - Overview hero

private struct OverviewHeader: View {
    let viewModel: SubjectsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let schoolName = viewModel.schoolName {
                Label {
                    Text(schoolName)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } icon: {
                    Image(systemName: "building.columns.fill")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.onAccent.opacity(0.72))
                .accessibilityLabel(String(format: String(localized: "overview.school.accessibility"), schoolName))
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("overview.overall.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.onAccent.opacity(0.75))

                    Text(GradeMath.formattedAverage(viewModel.overallAverage))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.onAccent)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Brand.onAccent.opacity(0.4))
            }

            Divider()
                .overlay(Brand.onAccent.opacity(0.2))

            HStack(spacing: Spacing.md) {
                StatTile(
                    title: String(localized: "overview.subjects"),
                    value: "\(viewModel.subjects.count)",
                    systemImage: "books.vertical.fill"
                )
                StatTile(
                    title: String(localized: "overview.marks"),
                    value: "\(viewModel.totalMarks)",
                    systemImage: "checkmark.seal.fill"
                )
            }

            if viewModel.bestSubject != nil || viewModel.weakestSubject != nil {
                HStack(alignment: .top, spacing: Spacing.md) {
                    if let best = viewModel.bestSubject {
                        StatTile(
                            title: String(localized: "overview.best"),
                            value: best.trimmedName,
                            systemImage: "trophy.fill"
                        )
                    }
                    if let weakest = viewModel.weakestSubject, viewModel.subjects.count > 1 {
                        StatTile(
                            title: String(localized: "overview.weakest"),
                            value: weakest.trimmedName,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Brand.primary.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Subject row

private struct SubjectCard: View {
    let subject: Subject

    var body: some View {
        let average = GradeMath.subjectAverage(subject)
        let band = GradeMath.band(for: average)

        HStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(band.soft)
                .frame(width: 46, height: 46)
                .overlay {
                    Text(abbrev)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(band.foregroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(subject.trimmedName)
                    .font(.headline)
                    .lineLimit(1)

                Text(String.localizedStringWithFormat(String(localized: "subject.markCount"), subject.marks.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            GradeBadge(text: GradeMath.formattedAverage(average), band: band)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var abbrev: String {
        let trimmed = subject.trimmedAbbrev
        return trimmed.isEmpty ? String(subject.trimmedName.prefix(2)).uppercased() : trimmed
    }
}

#Preview("Light") {
    SubjectsView(
        repository: BakalariRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
        )
    ) {}
}

#Preview("Dark") {
    SubjectsView(
        repository: BakalariRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
        )
    ) {}
    .preferredColorScheme(.dark)
}
