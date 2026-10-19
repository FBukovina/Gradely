import SwiftUI

/// The "Taneční" screen: upcoming lessons, prodloužená/ball tickets, the
/// school's notice board and its useful links. Pushed from Today, Timetable
/// and Settings, or shown in a sheet for the sale notification.
struct VavruskaView: View {
    let viewModel: VavruskaViewModel
    @Environment(\.openURL) private var openURL
    @State private var showsPast = false

    var body: some View {
        Group {
            if viewModel.course == nil {
                VavruskaConnectView(viewModel: viewModel, usesScreenBackground: true)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(at: context.date)
                }
            }
        }
        .navigationTitle(AppL10n.string("vavruska.title"))
        .gradelyNavigationTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.course != nil {
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    Button {
                        Task { await viewModel.refreshIfNeeded(force: true, includeTicketLinks: true) }
                    } label: {
                        GradelyIcon(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isRefreshing)
                    }
                    .disabled(viewModel.isRefreshing)
                    .accessibilityLabel(AppL10n.string("action.refresh"))
                    .accessibilityIdentifier("vavruskaRefreshButton")
                }
            }
        }
        .task { await viewModel.refreshIfNeeded(includeTicketLinks: true) }
        .gradelyOnRefreshCommand { await viewModel.refreshIfNeeded(force: true, includeTicketLinks: true) }
        .onDisappear { viewModel.markNoticeBoardSeen() }
    }

    private func content(at now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                statusNotice(at: now)
                upcomingSection(at: now)
                ticketSection(at: now)
                noticeBoardSection
                linksSection
                pastSection(at: now)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .gradelyScreenBackground()
        .refreshable { await viewModel.refreshIfNeeded(force: true, includeTicketLinks: true) }
        .accessibilityIdentifier("vavruskaScrollView")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: courseTitle)
                .font(.gradelyDisplay(size: 30))
                .accessibilityAddTraits(.isHeader)
            if let summary = viewModel.course?.scheduleSummary {
                Text(verbatim: summary)
                    .font(.gradely(.callout))
                    .foregroundStyle(.secondary)
            }
            if viewModel.lastRefreshFailed {
                Text("today.cached.warning")
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
    }

    private var courseTitle: String {
        guard let code = viewModel.course?.courseCode else { return AppL10n.string("vavruska.title") }
        return String(format: AppL10n.string("vavruska.course.title"), code)
    }

    @ViewBuilder
    private func statusNotice(at now: Date) -> some View {
        if viewModel.phase == .needsReconnect {
            notice(
                icon: "alert-01",
                tint: .gradelySystemOrange,
                title: "vavruska.reconnect.title",
                message: "vavruska.reconnect.message",
                action: "vavruska.reconnect.button"
            )
        } else if viewModel.isCourseEnded(at: now) {
            notice(
                icon: "flower",
                tint: Brand.primary,
                title: "vavruska.ended.title",
                message: "vavruska.ended.message",
                action: "vavruska.ended.button"
            )
        }
    }

    private func notice(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        action: LocalizedStringKey
    ) -> some View {
        PlainSection {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    SettingsIcon(name: icon, color: tint)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(.gradely(.headline))
                        Text(message)
                            .font(.gradely(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                NavigationLink {
                    VavruskaConnectView(viewModel: viewModel, dismissesOnConnect: true)
                } label: {
                    PlainLinkLabel(action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vavruskaReconnectButton")
            }
        }
        .accessibilityIdentifier("vavruskaStatusNotice")
    }

    // MARK: - Lessons

    private func upcomingSection(at now: Date) -> some View {
        let upcoming = viewModel.upcomingEvents(after: now)
        return PlainSection {
            PlainSectionTitle("vavruska.section.upcoming")
        } content: {
            if upcoming.isEmpty {
                Text("vavruska.upcoming.none")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(8)) { event in
                    eventRow(event, isPast: false)
                }
            }
        }
        .accessibilityIdentifier("vavruskaUpcomingSection")
    }

    @ViewBuilder
    private func pastSection(at now: Date) -> some View {
        let past = viewModel.pastEvents(before: now)
        if !past.isEmpty {
            PlainSection {
                Button {
                    withAnimation(.snappy) { showsPast.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(String(format: AppL10n.string("vavruska.section.past"), past.count))
                            .font(.gradely(.title3).weight(.bold))
                            .foregroundStyle(.primary)
                        GradelyIcon(showsPast ? "arrow-up-01" : "arrow-down-01", size: 15)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vavruskaPastToggle")
            } content: {
                if showsPast {
                    ForEach(past) { event in
                        eventRow(event, isPast: true)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: VavruskaEvent, isPast: Bool) -> some View {
        VavruskaEventRow(event: event, isPast: isPast)
            .contextMenu {
                if let url = VavruskaFormatting.mapsURL(event) {
                    Button(AppL10n.string("vavruska.openInMaps")) { openURL(url) }
                }
            }
            .accessibilityIdentifier("vavruskaEvent-\(event.id)")
    }

    // MARK: - Tickets

    @ViewBuilder
    private func ticketSection(at now: Date) -> some View {
        let sales = viewModel.snapshot.ticketSales.filter { $0.eventStart > now }
        if !sales.isEmpty {
            PlainSection(footer: "vavruska.alerts.footer") {
                PlainSectionTitle("vavruska.section.tickets")
            } content: {
                ForEach(sales) { sale in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            SettingsIcon(name: "ticket-01", color: .gradelySystemPurple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: sale.eventTitle)
                                    .font(.gradely(.subheadline).weight(.bold))
                                Text(verbatim: eventLine(sale))
                                    .font(.gradely(.caption))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: VavruskaFormatting.saleLine(sale, now: now))
                                    .font(.gradely(.caption).weight(.semibold))
                                    .foregroundStyle(sale.saleStart <= now ? Brand.primary : .secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        if sale.saleStart <= now {
                            Button {
                                openURL(sale.ticketURL ?? VavruskaLinks.tickets)
                            } label: {
                                PlainLinkLabel("vavruska.sale.buy")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("vavruskaBuyTickets-\(sale.id)")
                        }
                    }
                    .accessibilityIdentifier("vavruskaSale-\(sale.id)")
                }

                Toggle(isOn: Binding(
                    get: { viewModel.ticketAlertsEnabled },
                    set: { enabled in Task { await viewModel.setTicketAlertsEnabled(enabled) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("vavruska.alerts.toggle")
                            .font(.gradely(.subheadline).weight(.semibold))
                        Text("vavruska.alerts.message")
                            .font(.gradely(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Brand.primary)
                .accessibilityIdentifier("vavruskaTicketAlertsToggle")
            }
            .accessibilityIdentifier("vavruskaTicketsSection")
        }
    }

    private func eventLine(_ sale: VavruskaTicketSale) -> String {
        var parts = [SchoolDateFormatting.weekdayShortDate(sale.eventStart), VavruskaFormatting.time(sale.eventStart)]
        if let venue = sale.venue { parts.append(venue) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Notice board

    @ViewBuilder
    private var noticeBoardSection: some View {
        if let board = viewModel.snapshot.noticeBoard, !board.items.isEmpty {
            PlainSection(footer: board.updatedOn.map { date -> LocalizedStringKey in
                "vavruska.notices.updated \(SchoolDateFormatting.shortDate(date))"
            }) {
                HStack(spacing: Spacing.sm) {
                    PlainSectionTitle("vavruska.section.notices")
                    if viewModel.hasUnreadNotices {
                        StatusChip(text: AppL10n.string("vavruska.notices.new"), color: Brand.primary)
                            .fixedSize()
                    }
                }
            } content: {
                ForEach(board.items) { item in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verbatim: item.title)
                            .font(.gradely(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(item.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(VavruskaFormatting.attributed(paragraph))
                                .font(.gradely(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("vavruskaNoticeBoard")
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        PlainSection {
            PlainSectionTitle("vavruska.section.links")
        } content: {
            if let pdf = viewModel.course?.pdfURL {
                linkRow("vavruska.link.pdf", icon: "pdf-01", url: pdf)
            }
            linkRow("vavruska.link.gallery", icon: "image-01", url: VavruskaLinks.gallery)
            linkRow("vavruska.link.clothing", icon: "dress-01", url: VavruskaLinks.clothing)
            linkRow("vavruska.link.tickets", icon: "ticket-01", url: VavruskaLinks.tickets)
            linkRow("vavruska.link.makeup", icon: "mail-01", url: VavruskaLinks.office)
            linkRow("vavruska.link.noticeBoard", icon: "news", url: VavruskaLinks.noticeBoard)
        }
        .accessibilityIdentifier("vavruskaLinksSection")
    }

    private func linkRow(_ title: LocalizedStringKey, icon: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: Spacing.md) {
                SettingsIcon(name: icon)
                Text(title)
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                GradelyIcon("link-square-02", size: 14)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        VavruskaView(viewModel: VavruskaViewModel(repository: AppEnvironment.makeMockVavruskaRepository(connected: true)))
    }
}
