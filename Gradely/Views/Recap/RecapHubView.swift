import SwiftUI

/// Opens a recap's story. ContentView owns the presentation, so Today, the
/// Recap list and the Mac menu all show it the same way.
struct OpenRecapAction: Equatable {
    private let open: (RecapPeriod) -> Void

    init(_ open: @escaping (RecapPeriod) -> Void) {
        self.open = open
    }

    func callAsFunction(_ period: RecapPeriod) {
        open(period)
    }

    /// Every value sets the same state in ContentView.
    static func == (lhs: OpenRecapAction, rhs: OpenRecapAction) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var gradeyOpenRecap: OpenRecapAction?
}

// MARK: - List

/// Every recap that's out, grouped by school year.
struct RecapHubView: View {
    let store: RecapStore
    @Environment(\.gradeyOpenRecap) private var openRecap

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                let groups = Dictionary(grouping: store.periods, by: \.schoolYearStart)
                if groups.isEmpty {
                    Text(verbatim: AppL10n.string("recap.hub.empty"))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                }
                ForEach(groups.keys.sorted(by: >), id: \.self) { schoolYear in
                    PlainSection {
                        PlainSectionTitle(verbatim: RecapText.schoolYear(schoolYear))
                    } content: {
                        ForEach(groups[schoolYear] ?? []) { period in
                            row(period)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .navigationTitle(Text(verbatim: "Gradey Recap"))
        .gradelyNavigationTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recapHub")
    }

    private func row(_ period: RecapPeriod) -> some View {
        Button {
            openRecap?(period)
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: RecapText.title(period))
                        .font(.gradely(.headline))
                        .foregroundStyle(.primary)
                    Text(verbatim: RecapText.summary(store.summary(for: period)))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.sm)
                GradelyIcon(systemName: "chevron.right")
                    .font(.gradely(.caption).weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recapRow-\(period.id)")
    }
}

// MARK: - Entry rows

/// The row on Marks under the report card.
struct MarksRecapRow: View {
    let store: RecapStore

    var body: some View {
        if let latest = store.periods.first {
            PlainSection {
                NavigationLink(value: MarksRoute.recap) {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: "Gradey Recap")
                                .font(.gradely(.headline))
                                .foregroundStyle(.primary)
                            Text(verbatim: RecapText.title(latest) + " · " + RecapText.summary(store.summary(for: latest)))
                                .font(.gradely(.subheadline))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: Spacing.sm)
                        GradelyIcon(systemName: "chevron.right")
                            .font(.gradely(.caption).weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("marksRecapRow")
            }
        }
    }
}

/// Today's row while a new recap is out, until it's opened or hidden. Its
/// own view, so hiding it doesn't wait for Today's next minute tick.
struct TodayRecapRow: View {
    let store: RecapStore
    @Environment(\.gradeyOpenRecap) private var openRecap

    var body: some View {
        if let period = store.featured {
            PlainSection {
                HStack(spacing: Spacing.md) {
                    Button {
                        openRecap?(period)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            GradelyIcon("sparkles", size: 16)
                                .dynamicTypeSize(.medium)
                                .foregroundStyle(Brand.primary)
                                .frame(width: 34, height: 34)
                                .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(verbatim: String(format: AppL10n.string("recap.today.title"), RecapText.headline(period)))
                                    .font(.gradely(.subheadline).weight(.bold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: "Gradey Recap · " + RecapText.summary(store.summary(for: period)))
                                    .font(.gradely(.caption))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todayRecapRow")

                    Button {
                        store.hide(period)
                    } label: {
                        GradelyIcon("cancel-01", size: 16)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppL10n.string("recap.today.hide"))
                    .accessibilityIdentifier("todayRecapHideButton")
                }
            }
        }
    }
}
