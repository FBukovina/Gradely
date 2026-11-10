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

// MARK: - Tiles

private extension View {
    /// A flat tile in the recap's own colour with ink text. Recap is the one
    /// place the app fills a surface, so it's set apart from everything else.
    func recapTile(_ period: RecapPeriod, padding: CGFloat = Spacing.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return self
            .foregroundStyle(RecapPalette.ink)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RecapPalette.tile(for: period), in: shape)
            .contentShape(shape)
    }
}

/// A tile's top line: the logo, and the school year for a period that has one.
private struct RecapTileHeader: View {
    let period: RecapPeriod
    var logoSize: CGFloat = 18

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            RecapLogo(size: logoSize)
            Spacer(minLength: Spacing.sm)
            if period.kind != .calendarYear {
                Text(verbatim: RecapText.schoolYear(period.schoolYearStart))
                    .font(.gradely(.subheadline).weight(.semibold))
                    .opacity(0.7)
            }
        }
    }
}

// MARK: - List

/// Every recap that's out: the newest one large, the rest in a grid by
/// school year.
struct RecapHubView: View {
    let store: RecapStore
    @Environment(\.gradeyOpenRecap) private var openRecap

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.md, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if let latest = store.periods.first {
                    featuredTile(latest)

                    let groups = Dictionary(grouping: store.periods.dropFirst(), by: \.schoolYearStart)
                    ForEach(groups.keys.sorted(by: >), id: \.self) { schoolYear in
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            PlainSectionTitle(verbatim: RecapText.schoolYear(schoolYear))
                                .padding(.horizontal, Spacing.xs)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
                                ForEach(groups[schoolYear] ?? []) { period in
                                    tile(period)
                                }
                            }
                        }
                    }
                } else {
                    Text(verbatim: AppL10n.string("recap.hub.empty"))
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
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

    private func featuredTile(_ period: RecapPeriod) -> some View {
        Button {
            openRecap?(period)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                RecapTileHeader(period: period, logoSize: 22)
                HStack(alignment: .bottom, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verbatim: RecapText.headline(period))
                            .font(.gradely(size: 38, weight: .bold, relativeTo: .largeTitle))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: RecapText.summary(store.summary(for: period)))
                            .font(.gradely(.headline))
                            .opacity(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    GradelyIcon("play", size: 18)
                        .dynamicTypeSize(.large)
                        .foregroundStyle(RecapPalette.tile(for: period))
                        .frame(width: 44, height: 44)
                        .background(RecapPalette.ink, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .recapTile(period, padding: Spacing.xl)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recapRow-\(period.id)")
    }

    private func tile(_ period: RecapPeriod) -> some View {
        Button {
            openRecap?(period)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RecapMark()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Spacer(minLength: Spacing.md)
                Text(verbatim: RecapText.shortTitle(period))
                    .font(.gradely(.headline).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: RecapText.summary(store.summary(for: period)))
                    .font(.gradely(.caption).weight(.medium))
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Room for a summary on two lines, so a row of tiles lines up.
            .frame(minHeight: 104, alignment: .topLeading)
            .recapTile(period, padding: Spacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recapRow-\(period.id)")
    }
}

// MARK: - Entry tiles

/// The tile on Marks under the report card: the newest recap, opening the list.
struct MarksRecapRow: View {
    let store: RecapStore

    var body: some View {
        if let latest = store.periods.first {
            NavigationLink(value: MarksRoute.recap) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    RecapTileHeader(period: latest)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: RecapText.headline(latest))
                            .font(.gradely(.title2).weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: RecapText.summary(store.summary(for: latest)))
                            .font(.gradely(.subheadline).weight(.semibold))
                            .opacity(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .recapTile(latest)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marksRecapRow")
        }
    }
}

/// Today's tile while a new recap is out, until it's opened or hidden. Its
/// own view, so hiding it doesn't wait for Today's next minute tick.
struct TodayRecapRow: View {
    let store: RecapStore
    @Environment(\.gradeyOpenRecap) private var openRecap

    var body: some View {
        if let period = store.featured {
            // The X sits on the tile, not in it: a button inside a button
            // would open the story.
            ZStack(alignment: .topTrailing) {
                Button {
                    openRecap?(period)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        RecapLogo()
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: String(format: AppL10n.string("recap.today.title"), RecapText.headline(period)))
                                .font(.gradely(.title2).weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: RecapText.summary(store.summary(for: period)))
                                .font(.gradely(.subheadline).weight(.semibold))
                                .opacity(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .recapTile(period)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayRecapRow")

                Button {
                    store.hide(period)
                } label: {
                    GradelyIcon("cancel-01", size: 16)
                        .dynamicTypeSize(.medium)
                        .foregroundStyle(RecapPalette.ink.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.string("recap.today.hide"))
                .accessibilityIdentifier("todayRecapHideButton")
            }
        }
    }
}
