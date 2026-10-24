import SwiftUI

extension VavruskaEventKind {
    var tint: Color {
        switch self {
        case .lesson: Brand.primary
        case .specialLesson: .gradelySystemOrange
        case .extendedLesson, .ball: .gradelySystemPurple
        }
    }
}

enum VavruskaFormatting {
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguageOverride.locale))
    }

    /// "16:30–18:10"
    static func timeRange(_ event: VavruskaEvent) -> String {
        event.end > event.start ? time(event.start) + "–" + time(event.end) : time(event.start)
    }

    /// "ne 25. 10. · 16:30–18:10 · Obecní dům"
    static func dayLine(_ event: VavruskaEvent, includeVenue: Bool = true) -> String {
        var parts = [SchoolDateFormatting.weekdayShortDate(event.start), timeRange(event)]
        if includeVenue, let venue = event.venue { parts.append(venue) }
        return parts.joined(separator: " · ")
    }

    /// "Prodej vstupenek od po 12. 10. v 18:00" or "Prodej vstupenek běží".
    static func saleLine(_ sale: VavruskaTicketSale, now: Date) -> String {
        if sale.saleStart <= now {
            return AppL10n.string("vavruska.sale.open")
        }
        return String(
            format: AppL10n.string("vavruska.sale.opens"),
            SchoolDateFormatting.weekdayShortDate(sale.saleStart),
            time(sale.saleStart)
        )
    }

    static func attributed(_ runs: [VavruskaTextRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if let link = run.link {
                piece.link = link
                piece.foregroundColor = Brand.primary
            }
            if run.isBold {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            result += piece
        }
        return result
    }

    static func mapsURL(_ event: VavruskaEvent) -> URL? {
        let query = [event.venue, event.address].compactMap { $0 }.joined(separator: ", ")
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

/// Date tile, title and "time · venue" line, as on Today's planner rows.
struct VavruskaEventRow: View {
    let event: VavruskaEvent
    var isPast = false
    var showsDisclosure = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(spacing: 0) {
                Text(verbatim: event.start.formatted(dateStyle.day()))
                    .font(.gradely(.title3).weight(.bold).monospacedDigit())
                Text(verbatim: event.start.formatted(dateStyle.month(.abbreviated)))
                    .font(.gradely(.caption2).weight(.bold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title)
                    .font(.gradely(.subheadline).weight(.bold))
                    .foregroundStyle(isPast ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: VavruskaFormatting.dayLine(event))
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if showsDisclosure {
                GradelyIcon("arrow-right-01", size: 13)
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        isPast ? .secondary : event.kind.tint
    }

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: AppLanguageOverride.locale)
    }
}

// MARK: - Timetable

/// Dance lessons under a weekday's school lessons on iOS.
struct VavruskaAfterSchoolBlock: View {
    let events: [VavruskaEvent]
    let viewModel: VavruskaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("timetable.afterSchool")
                .padding(.bottom, Spacing.sm)
            ForEach(events) { event in
                Divider()
                NavigationLink {
                    VavruskaView(viewModel: viewModel)
                } label: {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(spacing: 2) {
                            GradelyIcon(event.kind.iconName, size: 16)
                                .foregroundStyle(event.kind.tint)
                                .frame(height: 22)
                            Text(verbatim: VavruskaFormatting.time(event.start))
                                .font(.gradely(.caption2))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(verbatim: VavruskaFormatting.time(event.end))
                                .font(.gradely(.caption2))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .frame(width: 44)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: event.title)
                                .font(.gradely(.headline))
                                .lineLimit(1)
                            if let venue = event.venue {
                                Text(verbatim: venue)
                                    .font(.gradely(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timetableDanceEvent-\(event.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timetableAfterSchoolBlock")
    }
}

/// Row label of the week grid's extra "after school" row.
struct VavruskaWeekGridLabel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GradelyIcon("music-note-03", size: 14)
                .foregroundStyle(Brand.primary)
            Text("timetable.afterSchool")
                .font(.gradely(.caption2).weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 52, alignment: .leading)
        .padding(.vertical, Spacing.sm)
    }
}

struct VavruskaWeekGridEvent: View {
    let event: VavruskaEvent
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Capsule()
                    .fill(event.kind.tint)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title)
                        .font(.gradely(.subheadline).weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: [VavruskaFormatting.timeRange(event), event.venue].compactMap { $0 }.joined(separator: " · "))
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Brand.primary.opacity(isHovering ? 0.08 : 0))
                    .padding(-Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(event.title)
        .accessibilityIdentifier("timetableDanceEvent-\(event.id)")
    }
}
