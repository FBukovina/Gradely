import SwiftUI
import Charts

// MARK: - Average history chart

/// A single sample of an average at a point in time, source-agnostic
/// (cloud history events or locally computed running averages).
struct AveragePoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
}

/// Shared grade-average chart: axis-less sparkline in list rows, full axes in
/// the subject detail. The Y axis is reversed so grade 1 (best) sits on top.
struct AverageHistoryChart: View {
    enum Style {
        case sparkline
        case detail
    }

    let points: [AveragePoint]
    var band: GradeBand = .neutral
    var style: Style = .sparkline
    /// Detail style only: actual marks drawn as dots behind the average line,
    /// sized by weight.
    var overlayMarks: [AverageTimelineEntry] = []

    /// Detail style only: the date under the reader's finger while scrubbing.
    @State private var selectedDate: Date?

    private var lineColor: Color {
        band == .neutral ? Brand.primary : band.foregroundColor
    }

    /// Explicit reversed domain: predictable padding for flat or tiny series,
    /// wide enough that overlay marks are never clipped.
    private var yDomain: [Double] {
        let values = points.map(\.value) + overlayMarks.map(\.markValue)
        let low = (values.min() ?? 1) - 0.25
        let high = (values.max() ?? 5) + 0.25
        return [min(high, 5.9), max(low, 0.7)]
    }

    /// Whole grades inside the visible range, falling back to half grades when
    /// the range is too narrow to show two whole ones.
    private var yTicks: [Double] {
        let best = yDomain[1]
        let worst = yDomain[0]
        let whole = Array(stride(from: best.rounded(.up), through: worst, by: 1))
        guard whole.count < 2 else { return whole }
        return Array(stride(from: (best * 2).rounded(.up) / 2, through: worst, by: 0.5))
    }

    /// The average sample nearest to the scrubbed date.
    private var selectedPoint: AveragePoint? {
        guard style == .detail, let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        switch style {
        case .sparkline:
            chart
        case .detail:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                AverageHistoryReadout(selected: selectedPoint, lineColor: lineColor)
                chart
                    .chartXSelection(value: $selectedDate)
                    .sensoryFeedback(.selection, trigger: selectedPoint?.id)
            }
        }
    }

    private var chart: some View {
        Chart {
            if points.count > 1 {
                ForEach(points) { point in
                    // Explicit baseline at the worst-grade edge: with the reversed
                    // Y domain the default zero baseline sits above the plot and
                    // the fill would escape upward.
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", yDomain[0]),
                        yEnd: .value("Average", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lineColor.opacity(style == .detail ? 0.18 : 0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            // Marks sit behind the line so the average stays the dominant read.
            if style == .detail {
                ForEach(overlayMarks) { entry in
                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Mark", entry.markValue)
                    )
                    .symbol {
                        MarkDot(color: entry.band.foregroundColor, diameter: min(7 + entry.weight * 1.4, 16))
                    }
                    .opacity(selectedPoint == nil ? 1 : 0.55)
                }
            }

            if points.count > 1 {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Average", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: style == .detail ? 3 : 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("Date", selectedPoint.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }

            if let highlighted = selectedPoint ?? points.last {
                PointMark(
                    x: .value("Date", highlighted.date),
                    y: .value("Average", highlighted.value)
                )
                .symbol {
                    if style == .detail {
                        Circle()
                            .fill(Color.gradelySecondaryGroupedBackground)
                            .overlay(Circle().strokeBorder(lineColor, lineWidth: 3))
                            .frame(width: 13, height: 13)
                    } else {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .modifier(AverageHistoryAxes(style: style, yTicks: yTicks))
    }

    private var xDomain: ClosedRange<Date> {
        let dates = points.map(\.date) + overlayMarks.map(\.date)
        let first = dates.min() ?? Date()
        let last = dates.max() ?? Date()
        guard first < last else {
            // Single sample: pad ±3 days so the lone point floats mid-chart.
            return first.addingTimeInterval(-3 * 86_400)...last.addingTimeInterval(3 * 86_400)
        }
        // A little breathing room so the first and last dots are not cut in
        // half by the clipped plot edge.
        let padding = max(last.timeIntervalSince(first) * 0.04, 3_600)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
}

/// A single mark on the detail chart: tinted fill with a solid ring, so
/// overlapping marks stay distinguishable.
private struct MarkDot: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(color.opacity(0.22))
            .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
            .frame(width: diameter, height: diameter)
    }
}

/// Legend above the detail chart; while scrubbing it turns into a readout of
/// the average on the selected date, so the chart itself stays uncluttered.
private struct AverageHistoryReadout: View {
    let selected: AveragePoint?
    let lineColor: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let selected {
                Text(selected.date.formatted(
                    Date.FormatStyle(locale: AppLanguageOverride.locale).day().month(.abbreviated).year()
                ))
                .foregroundStyle(.secondary)

                Spacer(minLength: Spacing.sm)

                HStack(spacing: Spacing.xs) {
                    Text(AppL10n.string("detail.average.title"))
                        .foregroundStyle(.secondary)
                    Text(GradeMath.formattedAverage(selected.value))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(lineColor)
                }
            } else {
                HStack(spacing: Spacing.xs + 2) {
                    MarkDot(color: .secondary, diameter: 9)
                    Text(AppL10n.string("detail.marks.section"))
                }
                HStack(spacing: Spacing.xs + 2) {
                    Capsule()
                        .fill(lineColor)
                        .frame(width: 14, height: 3)
                    Text(AppL10n.string("detail.average.title"))
                }
                Spacer(minLength: 0)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(minHeight: 20)
        .animation(.snappy(duration: 0.2), value: selected == nil)
        .accessibilityHidden(selected == nil)
    }
}

private struct AverageHistoryAxes: ViewModifier {
    let style: AverageHistoryChart.Style
    let yTicks: [Double]

    func body(content: Content) -> some View {
        switch style {
        case .sparkline:
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        case .detail:
            content
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yTicks) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
        }
    }
}

// MARK: - Absence months chart

/// One absence category's monthly counts, pre-mapped by the caller so the
/// chart stays decoupled from the absence view's category enum.
struct AbsenceChartSeries: Identifiable {
    struct Sample: Identifiable {
        let id: String
        let month: Date
        let count: Int
    }

    let id: String
    let label: String
    let color: Color
    let samples: [Sample]
}

/// Stacked bars of absence hours per month, colored by category.
struct AbsenceMonthsChart: View {
    let series: [AbsenceChartSeries]

    var body: some View {
        Chart {
            ForEach(series) { entry in
                ForEach(entry.samples) { sample in
                    BarMark(
                        x: .value("Month", sample.month, unit: .month),
                        y: .value("Hours", sample.count)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(3)
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(height: 160)
    }
}
