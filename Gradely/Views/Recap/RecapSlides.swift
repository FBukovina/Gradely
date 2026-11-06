import os
import SwiftUI

// MARK: - Palette

/// Gradey Recap's solid slide colours. Light and saturated, so the dark ink
/// text keeps at least 4.5 : 1 on every one, in light and dark mode alike.
enum RecapPalette {
    static let ink = Brand.onAccent
    static let emerald = Color(.sRGB, red: 0.239, green: 0.863, blue: 0.592)
    static let teal = Color(.sRGB, red: 0.235, green: 0.812, blue: 0.812)
    static let sky = Color(.sRGB, red: 0.486, green: 0.784, blue: 1.0)
    static let lime = Color(.sRGB, red: 0.776, green: 0.953, blue: 0.420)
    static let amber = Color(.sRGB, red: 1.0, green: 0.757, blue: 0.271)
    static let rose = Color(.sRGB, red: 1.0, green: 0.561, blue: 0.639)
    static let lilac = Color(.sRGB, red: 0.725, green: 0.651, blue: 1.0)

    static func background(for slide: RecapSlide, in recap: Recap) -> Color {
        switch slide {
        case .intro, .reportCard: emerald
        case .marks, .summary, .lastYear: sky
        case .average: band(GradeMath.band(for: recap.average))
        case .topSubject, .personality: lilac
        case .toughestSubject: amber
        case .moments: teal
        case .absence: rose
        case .timetable: lime
        }
    }

    static func band(_ band: GradeBand) -> Color {
        switch band {
        case .excellent: lime
        case .good, .neutral: teal
        case .average: amber
        case .poor: rose
        }
    }
}

// MARK: - Text

enum RecapText {
    private static var isChronicallyOnline: Bool { AppLanguageOverride.state.withLock { $0 }.isChronicallyOnline }

    /// For keys built at runtime: an interpolated literal would look up
    /// "recap.intro.quarter.%lld" instead of "recap.intro.quarter.1".
    static func localized(_ key: String) -> String {
        AppL10n.string(String.LocalizationValue(key))
    }

    /// "Říjen 2026", "1. čtvrtletí 2026/27", "1. pololetí 2026/27", "Rok 2026".
    static func title(_ period: RecapPeriod) -> String {
        switch period.kind {
        case .month:
            let title = period.start.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale, timeZone: Homework.timeZone).month(.wide).year())
            return isChronicallyOnline ? title.lowercased() : title.prefix(1).uppercased() + title.dropFirst()
        case .quarter:
            return String(format: RecapText.localized("recap.period.quarter.\(period.number)"), schoolYear(period.year))
        case .semester:
            return ReportCardText.term(ReportCardPeriod(startYear: period.year, semester: period.number))
        case .calendarYear:
            return String(format: AppL10n.string("recap.period.year"), String(period.year))
        }
    }

    /// "Tvůj říjen", "Tvoje 1. čtvrtletí", "Tvůj rok 2026".
    static func headline(_ period: RecapPeriod) -> String {
        switch period.kind {
        case .month:
            let month = period.start.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale, timeZone: Homework.timeZone).month(.wide))
            return String(format: AppL10n.string("recap.intro.month"), month)
        case .quarter:
            return RecapText.localized("recap.intro.quarter.\(period.number)")
        case .semester:
            return RecapText.localized("recap.intro.semester.\(period.number)")
        case .calendarYear:
            return String(format: AppL10n.string("recap.intro.year"), String(period.year))
        }
    }

    static func schoolYear(_ startYear: Int) -> String {
        ReportCardPeriod(startYear: startYear, semester: 1).schoolYear
    }

    /// "3 známky": picks the plural form by the app's language. With
    /// `localizedStringWithFormat` a Czech app on an English phone would
    /// follow English rules and say "3 známek".
    static func plural(_ key: String, _ count: Int) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: AppLanguageOverride.locale, count)
    }

    /// The word under a big number: "známek" for 47. Plural strings must
    /// contain the number, so it's formatted and then taken out again.
    static func noun(_ key: String, count: Int) -> String {
        let text = plural(key, count)
        guard let range = text.range(of: String(count)) else { return text }
        return text.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
    }

    /// "23 známek".
    static func marks(_ count: Int) -> String {
        plural("recap.marksCount", count)
    }

    /// "23 známek · průměr 1,62", for list rows.
    static func summary(_ recap: Recap) -> String {
        var parts: [String] = []
        if recap.markCount > 0 { parts.append(marks(recap.markCount)) }
        if let average = recap.average {
            parts.append(String(format: AppL10n.string("recap.row.average"), GradeMath.formattedAverage(average)))
        }
        if recap.markCount == 0, let absence = recap.absence {
            parts.append(hours(absence.counts.total))
        }
        if recap.isOngoing { parts.append(AppL10n.string("recap.ongoing")) }
        return parts.joined(separator: " · ")
    }

    /// "22 h".
    static func hours(_ value: Int) -> String {
        String(format: AppL10n.string("recap.hours"), value.formatted())
    }

    static func personalityTitle(_ personality: RecapPersonality) -> String {
        switch personality {
        case .specialty(let subject): String(format: AppL10n.string("recap.personality.specialty.title"), subject)
        default: localized("recap.personality.\(personalityKey(personality)).title")
        }
    }

    static func personalityDetail(_ personality: RecapPersonality) -> String {
        localized("recap.personality.\(personalityKey(personality)).detail")
    }

    static func personalityIcon(_ personality: RecapPersonality) -> String {
        switch personality {
        case .straightAs: "crown"
        case .comeback: "rocket-01"
        case .rollercoaster: "roller-coaster"
        case .lastMinute: "clock-01"
        case .specialty: "target-02"
        case .steady: "mountain"
        }
    }

    private static func personalityKey(_ personality: RecapPersonality) -> String {
        switch personality {
        case .straightAs: "straightAs"
        case .comeback: "comeback"
        case .rollercoaster: "rollercoaster"
        case .lastMinute: "lastMinute"
        case .specialty: "specialty"
        case .steady: "steady"
        }
    }

    static func bandLine(_ average: Double) -> String {
        switch GradeMath.band(for: average) {
        case .excellent: AppL10n.string("recap.average.band.excellent")
        case .good, .neutral: AppL10n.string("recap.average.band.good")
        case .average: AppL10n.string("recap.average.band.average")
        case .poor: AppL10n.string("recap.average.band.poor")
        }
    }

    /// "Minulý měsíc 1,74 · o 0,12 líp".
    static func comparison(_ comparison: RecapComparison, average: Double) -> String {
        let basis = comparison.basis == .previousMonth ? "recap.average.previousMonth" : "recap.average.previousReportCard"
        var line = String(format: RecapText.localized(basis), GradeMath.formattedAverage(comparison.average))
        let difference = comparison.average - average
        if abs(difference) >= 0.005 {
            let key = difference > 0 ? "recap.average.delta.better" : "recap.average.delta.worse"
            line += " · " + String(format: RecapText.localized(key), GradeMath.formattedAverage(abs(difference)))
        }
        return line
    }
}

// MARK: - Slide content

/// One slide's content, without the story chrome. The story and the share
/// image both draw it; `animated` counts the big numbers up.
struct RecapSlideView: View {
    let recap: Recap
    let slide: RecapSlide
    var animated = true

    private let ink = RecapPalette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(ink)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch slide {
        case .intro: intro
        case .marks: marks
        case .average: average
        case .topSubject: subject(kicker: "recap.top.kicker", stat: recap.topSubject, note: nil)
        case .toughestSubject: subject(kicker: "recap.toughest.kicker", stat: recap.toughestSubject, note: AppL10n.string("recap.toughest.note"))
        case .moments: moments
        case .absence: absence
        case .timetable: timetable
        case .personality: personality
        case .reportCard: reportCard
        case .lastYear: lastYear
        case .summary: summary
        }
    }

    // MARK: Slides

    private var intro: some View {
        Group {
            kicker(verbatim: "Gradey Recap")
            Spacer(minLength: Spacing.xl)
            Text(verbatim: RecapText.headline(recap.period))
                .font(.gradely(size: 54, weight: .bold, relativeTo: .largeTitle))
                .lineLimit(3)
                .minimumScaleFactor(0.5)
            Text(verbatim: RecapText.title(recap.period))
                .font(.gradely(.title2).weight(.semibold))
                .opacity(0.75)
            if recap.isOngoing {
                note(AppL10n.string("recap.intro.ongoing"))
            }
            if recap.springFromReportCard {
                note(AppL10n.string("recap.intro.springFromReportCard"))
            }
            Spacer(minLength: Spacing.xl)
            Image("GradeyLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .opacity(0.22)
                .accessibilityHidden(true)
        }
    }

    private var marks: some View {
        Group {
            kicker("recap.marks.kicker")
            Text(verbatim: AppL10n.string("recap.marks.headline"))
                .font(.gradely(.title2).weight(.semibold))
            RecapNumber(value: Double(recap.markCount), animated: animated) { Int($0).formatted() }
            Text(verbatim: RecapText.noun("recap.marks.noun", count: recap.markCount))
                .font(.gradely(.title2).weight(.semibold))
                .padding(.top, -Spacing.md)
            Spacer(minLength: Spacing.md)
            RecapDistribution(counts: recap.distribution, other: recap.otherMarks)
        }
    }

    private var average: some View {
        Group {
            kicker("recap.average.kicker")
            Spacer(minLength: Spacing.lg)
            if let average = recap.average {
                RecapNumber(value: average, animated: animated, from: 5) { GradeMath.formattedAverage($0) }
                Text(verbatim: RecapText.bandLine(average))
                    .font(.gradely(.title2).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let comparison = recap.comparison {
                    note(RecapText.comparison(comparison, average: average))
                }
            }
            Spacer(minLength: Spacing.lg)
        }
    }

    private func subject(kicker key: String.LocalizationValue, stat: RecapSubjectStat?, note text: String?) -> some View {
        Group {
            kicker(verbatim: AppL10n.string(key))
            Spacer(minLength: Spacing.lg)
            if let stat {
                Text(verbatim: stat.name)
                    .font(.gradely(size: 52, weight: .bold, relativeTo: .largeTitle))
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                Text(verbatim: String(format: AppL10n.string("recap.subject.detail"), GradeMath.formattedAverage(stat.average), RecapText.marks(stat.markCount)))
                    .font(.gradely(.title3).weight(.semibold))
                    .opacity(0.8)
            }
            if let text { note(text) }
            Spacer(minLength: Spacing.lg)
        }
    }

    private var moments: some View {
        Group {
            kicker("recap.moments.kicker")
            Spacer(minLength: Spacing.md)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recap.moments.enumerated()), id: \.offset) { offset, moment in
                    if offset > 0 { Rectangle().fill(ink.opacity(0.18)).frame(height: 1) }
                    momentRow(moment)
                        .padding(.vertical, Spacing.lg)
                }
            }
            Spacer(minLength: Spacing.md)
        }
    }

    private func momentRow(_ moment: RecapMoment) -> some View {
        let title: String, value: String
        switch moment {
        case .onesStreak(let count):
            title = AppL10n.string("recap.moment.streak.title")
            value = RecapText.plural("recap.moment.streak.value", count)
        case .comeback(let subject, let from, let to):
            title = AppL10n.string("recap.moment.comeback.title")
            value = "\(subject) · \(GradeMath.formattedAverage(from)) → \(GradeMath.formattedAverage(to))"
        case .heaviestMark(let markText, let subject, let weight):
            title = AppL10n.string("recap.moment.heaviest.title")
            value = "\(markText) · \(subject) · " + String(format: AppL10n.string("recap.moment.heaviest.weight"), GradeMath.formattedWeight(weight))
        case .busiestDay(let date, let count):
            title = AppL10n.string("recap.moment.busiest.title")
            value = SchoolDateFormatting.weekdayShortDate(date) + " · " + RecapText.marks(count)
        }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: title)
                .font(.gradely(.subheadline).weight(.semibold))
                .opacity(0.7)
            Text(verbatim: value)
                .font(.gradely(.title2).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var absence: some View {
        kicker("recap.absence.kicker")
        if let absence = recap.absence {
            let counts = absence.counts
            Spacer(minLength: Spacing.lg)
            RecapNumber(value: Double(counts.total), animated: animated) { Int($0).formatted() }
            if counts.total == 0 {
                Text(verbatim: AppL10n.string("recap.absence.zero.title"))
                    .font(.gradely(.title2).weight(.semibold))
                note(AppL10n.string("recap.absence.zero.detail"))
            } else {
                Text(verbatim: RecapText.noun("recap.absence.noun", count: counts.total))
                    .font(.gradely(.title2).weight(.semibold))
                    .padding(.top, -Spacing.md)
                let parts = [
                    (AppL10n.string("absence.category.short.ok"), counts.ok),
                    (AppL10n.string("absence.category.short.unsolved"), counts.unsolved),
                    (AppL10n.string("absence.category.short.missed"), counts.missed),
                    (AppL10n.string("absence.category.short.late"), counts.late)
                ].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
                if !parts.isEmpty { note(parts.joined(separator: " · ")) }
                if let subject = absence.topSubject {
                    note(String(format: AppL10n.string("recap.absence.topSubject"), subject, RecapText.hours(absence.topSubjectHours)))
                }
            }
            Spacer(minLength: Spacing.lg)
        }
    }

    @ViewBuilder
    private var timetable: some View {
        kicker("recap.timetable.kicker")
        if let timetable = recap.timetable {
            Spacer(minLength: Spacing.lg)
            RecapNumber(value: Double(timetable.canceled), animated: animated) { Int($0).formatted() }
            Text(verbatim: timetable.canceled == 0
                 ? AppL10n.string("recap.timetable.zero")
                 : RecapText.noun("recap.timetable.canceledNoun", count: timetable.canceled))
                .font(.gradely(.title2).weight(.semibold))
                .padding(.top, -Spacing.md)
            note(String(format: AppL10n.string("recap.timetable.substitutions"), timetable.substitutions.formatted())
                 + " · " + String(format: AppL10n.string("recap.timetable.lessons"), timetable.lessons.formatted()))
            if let subject = timetable.topCanceledSubject {
                note(String(format: AppL10n.string("recap.timetable.topCanceled"), subject))
            }
            Spacer(minLength: Spacing.lg)
        }
    }

    @ViewBuilder
    private var personality: some View {
        kicker("recap.personality.kicker")
        if let personality = recap.personality {
            Spacer(minLength: Spacing.lg)
            GradelyIcon(RecapText.personalityIcon(personality), size: 64)
            Text(verbatim: RecapText.personalityTitle(personality))
                .font(.gradely(size: 48, weight: .bold, relativeTo: .largeTitle))
                .lineLimit(3)
                .minimumScaleFactor(0.5)
            Text(verbatim: RecapText.personalityDetail(personality))
                .font(.gradely(.title3).weight(.semibold))
                .opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.lg)
        }
    }

    @ViewBuilder
    private var reportCard: some View {
        kicker("reportCard.title")
        if let card = recap.reportCard {
            Spacer(minLength: Spacing.lg)
            RecapNumber(value: card.average, animated: animated, from: 5) { GradeMath.formattedAverage($0) }
            Text(verbatim: RecapText.localized(card.isEstimate ? "recap.reportCard.estimate" : "recap.reportCard.final"))
                .font(.gradely(.title2).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            let detail = reportCardDetail(card)
            if !detail.isEmpty { note(detail) }
            Spacer(minLength: Spacing.lg)
        }
    }

    @ViewBuilder
    private var lastYear: some View {
        kicker("recap.lastYear.kicker")
        if let lastYear = recap.lastYear {
            Spacer(minLength: Spacing.lg)
            comparisonBlock(title: lastYear.springTerm, average: lastYear.springAverage,
                            hours: lastYear.springAbsentHours.map { Int($0.rounded()) })
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
            comparisonBlock(title: AppL10n.string("recap.lastYear.now"), average: lastYear.autumnAverage, hours: lastYear.autumnAbsentHours)
            Spacer(minLength: Spacing.lg)
        }
    }

    private func reportCardDetail(_ card: RecapReportCard) -> String {
        var parts: [String] = []
        if card.ones > 0 { parts.append(RecapText.plural("recap.reportCard.ones", card.ones)) }
        if card.borderline > 0 { parts.append(RecapText.plural("reportCard.borderlineCount", card.borderline)) }
        return parts.joined(separator: " · ")
    }

    private func comparisonBlock(title: String, average: Double?, hours: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: title)
                .font(.gradely(.subheadline).weight(.semibold))
                .opacity(0.7)
            Text(verbatim: average.map { GradeMath.formattedAverage($0) } ?? "–")
                .font(.gradely(size: 56, weight: .bold, relativeTo: .largeTitle).monospacedDigit())
            if let hours {
                Text(verbatim: String(format: AppL10n.string("recap.lastYear.absence"), RecapText.hours(hours)))
                    .font(.gradely(.title3).weight(.semibold))
                    .opacity(0.8)
            }
        }
    }

    private var summary: some View {
        Group {
            kicker(verbatim: "Gradey Recap")
            Text(verbatim: RecapText.title(recap.period))
                .font(.gradely(size: 36, weight: .bold, relativeTo: .largeTitle))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: Spacing.md)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: Spacing.xl) {
                ForEach(summaryTiles) { tile in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: tile.title)
                            .font(.gradely(.subheadline).weight(.semibold))
                            .opacity(0.7)
                        Text(verbatim: tile.value)
                            .font(.gradely(.title2).weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            Spacer(minLength: Spacing.md)
        }
    }

    private struct SummaryTile: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    private var summaryTiles: [SummaryTile] {
        var tiles: [SummaryTile] = []
        if let average = recap.average {
            tiles.append(SummaryTile(title: AppL10n.string("recap.average.kicker"), value: GradeMath.formattedAverage(average)))
        }
        tiles.append(SummaryTile(title: AppL10n.string("recap.marks.kicker"), value: recap.markCount.formatted()))
        if let top = recap.topSubject {
            tiles.append(SummaryTile(title: AppL10n.string("recap.top.kicker"), value: top.name))
        }
        if let absence = recap.absence {
            tiles.append(SummaryTile(title: AppL10n.string("recap.absence.kicker"), value: RecapText.hours(absence.counts.total)))
        }
        if let timetable = recap.timetable {
            tiles.append(SummaryTile(title: AppL10n.string("recap.summary.canceled"), value: timetable.canceled.formatted()))
        }
        if let personality = recap.personality, recap.period.kind != .month {
            tiles.append(SummaryTile(title: AppL10n.string("recap.summary.personality"), value: RecapText.personalityTitle(personality)))
        }
        return tiles
    }

    // MARK: Pieces

    private func kicker(_ key: String.LocalizationValue) -> some View {
        kicker(verbatim: AppL10n.string(key))
    }

    private func kicker(verbatim text: String) -> some View {
        Text(verbatim: text)
            .font(.gradely(.headline))
            .textCase(nil)
            .opacity(0.75)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.gradely(.title3).weight(.medium))
            .opacity(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A big number that counts up (or down, for averages) when the slide appears.
struct RecapNumber: View {
    let value: Double
    var animated = true
    var from: Double = 0
    let format: (Double) -> String
    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double, animated: Bool = true, from: Double = 0, format: @escaping (Double) -> String) {
        self.value = value
        self.animated = animated
        self.from = from
        self.format = format
    }

    var body: some View {
        Text(verbatim: format(animated && !reduceMotion ? (shown ?? from) : value))
            .font(.gradely(size: 120, weight: .bold, relativeTo: .largeTitle).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: shown ?? from))
            .accessibilityLabel(Text(verbatim: format(value)))
            .onAppear {
                guard animated, !reduceMotion else { return }
                shown = from
                withAnimation(.snappy(duration: 0.9).delay(0.15)) { shown = value }
            }
    }
}

/// Bars for 1 to 5, plus the marks that aren't graded 1–5.
private struct RecapDistribution: View {
    let counts: [Int]
    let other: Int

    var body: some View {
        let largest = max(counts.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(counts.enumerated()), id: \.offset) { offset, count in
                HStack(spacing: Spacing.md) {
                    Text(verbatim: String(offset + 1))
                        .font(.gradely(.title3).weight(.bold).monospacedDigit())
                        .frame(width: 22, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(RecapPalette.ink.opacity(0.85))
                            .frame(width: count == 0 ? 0 : max(6, proxy.size.width * CGFloat(count) / CGFloat(largest)))
                    }
                    .frame(height: 18)
                    Text(verbatim: count.formatted())
                        .font(.gradely(.title3).weight(.semibold).monospacedDigit())
                        .frame(minWidth: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if other > 0 {
                Text(verbatim: String(format: AppL10n.string("recap.marks.other"), other.formatted()))
                    .font(.gradely(.subheadline).weight(.semibold))
                    .opacity(0.7)
            }
        }
    }
}
