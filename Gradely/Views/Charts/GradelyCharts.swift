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
    /// Detail style only: actual marks drawn as dots against the average line,
    /// sized by weight.
    var overlayMarks: [AverageTimelineEntry] = []

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

    var body: some View {
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
                            colors: [lineColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Average", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)
                }
            }

            if let last = points.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Average", last.value)
                )
                .symbolSize(style == .detail ? 42 : 16)
                .foregroundStyle(lineColor)
            }

            if style == .detail {
                ForEach(overlayMarks) { entry in
                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Mark", entry.markValue)
                    )
                    .symbolSize(30 + entry.weight * 14)
                    .foregroundStyle(entry.band.foregroundColor.opacity(0.85))
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .modifier(AverageHistoryAxes(style: style))
    }

    private var xDomain: ClosedRange<Date> {
        let dates = points.map(\.date) + overlayMarks.map(\.date)
        let first = dates.min() ?? Date()
        let last = dates.max() ?? Date()
        guard first < last else {
            // Single sample: pad ±3 days so the lone point floats mid-chart.
            return first.addingTimeInterval(-3 * 86_400)...last.addingTimeInterval(3 * 86_400)
        }
        return first...last
    }
}

private struct AverageHistoryAxes: ViewModifier {
    let style: AverageHistoryChart.Style

    func body(content: Content) -> some View {
        switch style {
        case .sparkline:
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        case .detail:
            content
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.day().month())
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
                            .font(.caption2)
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
