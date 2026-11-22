using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Gradely.Core.Models;
using Gradely.Core.Support;

namespace Gradely.Windows.Controls;

/// <summary>
/// Faithful recreation of Gradey's AverageHistoryChart:
/// Reversed Y-axis (1 at top, 5 at bottom), smooth curve with area fill, weight-scaled dots, and interactive hover scrub.
/// </summary>
public sealed class AverageHistoryChart : FrameworkElement
{
    public static readonly DependencyProperty EntriesProperty = DependencyProperty.Register(
        nameof(Entries),
        typeof(IReadOnlyList<AverageTimelineEntry>),
        typeof(AverageHistoryChart),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty LineBandProperty = DependencyProperty.Register(
        nameof(LineBand),
        typeof(GradeBand),
        typeof(AverageHistoryChart),
        new FrameworkPropertyMetadata(GradeBand.Excellent, FrameworkPropertyMetadataOptions.AffectsRender));

    private int? _hoveredIndex;

    public IReadOnlyList<AverageTimelineEntry>? Entries
    {
        get => (IReadOnlyList<AverageTimelineEntry>?)GetValue(EntriesProperty);
        set => SetValue(EntriesProperty, value);
    }

    public GradeBand LineBand
    {
        get => (GradeBand)GetValue(LineBandProperty);
        set => SetValue(LineBandProperty, value);
    }

    public AverageHistoryChart()
    {
        ClipToBounds = true;
        MouseMove += OnMouseMove;
        MouseLeave += (_, _) =>
        {
            if (_hoveredIndex is not null)
            {
                _hoveredIndex = null;
                InvalidateVisual();
            }
        };
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        var entries = Entries;
        if (entries is null || entries.Count < 2) return;

        var pos = e.GetPosition(this);
        var plot = GetPlotRect();
        if (plot.Width <= 0) return;

        var points = ComputePoints(entries, plot, out _, out _);
        int closest = 0;
        double bestDist = double.MaxValue;
        for (int i = 0; i < points.Count; i++)
        {
            double d = Math.Abs(points[i].X - pos.X);
            if (d < bestDist)
            {
                bestDist = d;
                closest = i;
            }
        }

        if (_hoveredIndex != closest)
        {
            _hoveredIndex = closest;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        var entries = Entries;
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0) return;

        // Transparent hit-test surface
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, h));

        var secondaryBrush = TryFindResource("SecondaryLabelBrush") as Brush ?? Brushes.Gray;
        var labelBrush = TryFindResource("LabelBrush") as Brush ?? Brushes.Black;
        var hairlineBrush = TryFindResource("HairlineBrush") as Brush ?? Brushes.LightGray;
        var fontFamily = TryFindResource("GradelyFont") as FontFamily ?? new FontFamily("Segoe UI");
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        if (entries is null || entries.Count < 2)
        {
            var emptyText = new FormattedText(
                LocalizationService.Instance["marks.history.empty"],
                CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight,
                new Typeface(fontFamily, FontStyles.Normal, FontWeights.Regular, FontStretches.Normal),
                13,
                secondaryBrush,
                dpi);
            dc.DrawText(emptyText, new Point((w - emptyText.Width) / 2, (h - emptyText.Height) / 2));
            return;
        }

        var plot = GetPlotRect();
        var points = ComputePoints(entries, plot, out double minY, out double maxY);

        // Top readout bar when hovering
        if (_hoveredIndex is int hi && hi >= 0 && hi < entries.Count)
        {
            var hovered = entries[hi];
            var readout = $"{hovered.Date.LocalDateTime:d. M. yyyy} · Ø {GradeMath.FormatAverage(hovered.RunningAverage, LocalizationService.Instance.ActiveCulture)}  ({hovered.MarkValue:0.##} · w{GradeMath.FormatWeight(hovered.Weight)})";
            var ft = new FormattedText(
                readout,
                CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight,
                new Typeface(fontFamily, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal),
                12,
                labelBrush,
                dpi);
            dc.DrawText(ft, new Point(plot.Left, 2));
        }

        // Horizontal dashed gridlines (trailing axis labels, 1 at top -> 5 at bottom)
        var gridPen = new Pen(hairlineBrush, 1) { DashStyle = new DashStyle([3, 4], 0) };
        double step = (maxY - minY) <= 1.5 ? 0.5 : 1.0;
        double startTick = Math.Ceiling(minY / step) * step;
        for (double val = startTick; val <= maxY + 0.001; val += step)
        {
            double y = MapY(val, minY, maxY, plot);
            dc.DrawLine(gridPen, new Point(plot.Left, y), new Point(plot.Right, y));

            var tickText = new FormattedText(
                val.ToString(step < 1 ? "F1" : "F0", LocalizationService.Instance.ActiveCulture),
                CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight,
                new Typeface(fontFamily, FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
                11,
                secondaryBrush,
                dpi);
            dc.DrawText(tickText, new Point(plot.Right + 6, y - tickText.Height / 2));
        }

        // Smooth line path + vertical area gradient
        var lineColor = GetBandColor(LineBand);
        var lineGeometry = BuildSmoothGeometry(points);

        var areaGeometry = lineGeometry.Clone();
        var areaFig = areaGeometry.Figures[0];
        areaFig.Segments.Add(new LineSegment(new Point(points[^1].X, plot.Bottom), false));
        areaFig.Segments.Add(new LineSegment(new Point(points[0].X, plot.Bottom), false));
        areaFig.IsClosed = true;

        var areaBrush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1)
        };
        areaBrush.GradientStops.Add(new GradientStop(Color.FromArgb(48, lineColor.R, lineColor.G, lineColor.B), 0));
        areaBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, lineColor.R, lineColor.G, lineColor.B), 1));
        dc.DrawGeometry(areaBrush, null, areaGeometry);

        // Weight-scaled mark dots behind the curve
        for (int i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            double dotY = MapY(Math.Clamp(e.MarkValue, minY, maxY), minY, maxY, plot);
            double diameter = Math.Min(7.0 + e.Weight * 1.4, 15.0);
            var dotColor = GetBandColor(e.Band);
            var dotBrush = new SolidColorBrush(Color.FromArgb(140, dotColor.R, dotColor.G, dotColor.B));
            dc.DrawEllipse(dotBrush, null, new Point(points[i].X, dotY), diameter / 2, diameter / 2);
        }

        // Main average stroke
        var strokePen = new Pen(new SolidColorBrush(lineColor), 2.8)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round
        };
        dc.DrawGeometry(null, strokePen, lineGeometry);

        // Hover vertical rule & ring
        if (_hoveredIndex is int hIdx && hIdx >= 0 && hIdx < points.Count)
        {
            var pt = points[hIdx];
            var rulePen = new Pen(new SolidColorBrush(Color.FromArgb(150, lineColor.R, lineColor.G, lineColor.B)), 1.2)
            {
                DashStyle = new DashStyle([4, 4], 0)
            };
            dc.DrawLine(rulePen, new Point(pt.X, plot.Top), new Point(pt.X, plot.Bottom));

            var bgBrush = TryFindResource("CanvasBackgroundBrush") as Brush ?? Brushes.White;
            dc.DrawEllipse(bgBrush, new Pen(new SolidColorBrush(lineColor), 2.5), pt, 5.5, 5.5);
        }

        // Start & End X-axis date labels
        var firstDate = new FormattedText(
            entries[0].Date.LocalDateTime.ToString("d. M.", LocalizationService.Instance.ActiveCulture),
            CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
            new Typeface(fontFamily, FontStyles.Normal, FontWeights.Regular, FontStretches.Normal),
            11, secondaryBrush, dpi);
        var lastDate = new FormattedText(
            entries[^1].Date.LocalDateTime.ToString("d. M.", LocalizationService.Instance.ActiveCulture),
            CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
            new Typeface(fontFamily, FontStyles.Normal, FontWeights.Regular, FontStretches.Normal),
            11, secondaryBrush, dpi);
        dc.DrawText(firstDate, new Point(plot.Left, plot.Bottom + 6));
        dc.DrawText(lastDate, new Point(plot.Right - lastDate.Width, plot.Bottom + 6));
    }

    private Rect GetPlotRect()
    {
        double left = 8;
        double top = 24;
        double right = Math.Max(left + 20, ActualWidth - 36);
        double bottom = Math.Max(top + 20, ActualHeight - 24);
        return new Rect(left, top, right - left, bottom - top);
    }

    private static List<Point> ComputePoints(IReadOnlyList<AverageTimelineEntry> entries, Rect plot, out double minY, out double maxY)
    {
        double rawMin = entries.Min(e => Math.Min(e.RunningAverage, e.MarkValue));
        double rawMax = entries.Max(e => Math.Max(e.RunningAverage, e.MarkValue));
        minY = Math.Max(1.0, Math.Floor((rawMin - 0.25) * 2) / 2.0);
        maxY = Math.Min(5.0, Math.Ceiling((rawMax + 0.25) * 2) / 2.0);
        if (maxY - minY < 1.0)
        {
            minY = Math.Max(1.0, minY - 0.5);
            maxY = Math.Min(5.0, maxY + 0.5);
        }

        long tMin = entries[0].Date.ToUnixTimeSeconds();
        long tMax = entries[^1].Date.ToUnixTimeSeconds();
        long span = Math.Max(1, tMax - tMin);

        var pts = new List<Point>(entries.Count);
        for (int i = 0; i < entries.Count; i++)
        {
            double xFrac = tMax == tMin
                ? (double)i / Math.Max(1, entries.Count - 1)
                : (double)(entries[i].Date.ToUnixTimeSeconds() - tMin) / span;
            double x = plot.Left + xFrac * plot.Width;
            double y = MapY(entries[i].RunningAverage, minY, maxY, plot);
            pts.Add(new Point(x, y));
        }
        return pts;
    }

    private static double MapY(double value, double minY, double maxY, Rect plot)
    {
        // Reversed Y-axis: 1.0 (minY) at TOP, 5.0 (maxY) at BOTTOM
        double frac = (value - minY) / Math.Max(0.01, maxY - minY);
        return plot.Top + Math.Clamp(frac, 0, 1) * plot.Height;
    }

    private static PathGeometry BuildSmoothGeometry(List<Point> points)
    {
        var figure = new PathFigure { StartPoint = points[0], IsClosed = false };
        if (points.Count == 2)
        {
            figure.Segments.Add(new LineSegment(points[1], true));
        }
        else
        {
            for (int i = 0; i < points.Count - 1; i++)
            {
                var p0 = points[Math.Max(0, i - 1)];
                var p1 = points[i];
                var p2 = points[i + 1];
                var p3 = points[Math.Min(points.Count - 1, i + 2)];

                var cp1 = new Point(p1.X + (p2.X - p0.X) / 6.0, p1.Y + (p2.Y - p0.Y) / 6.0);
                var cp2 = new Point(p2.X - (p3.X - p1.X) / 6.0, p2.Y - (p3.Y - p1.Y) / 6.0);
                figure.Segments.Add(new BezierSegment(cp1, cp2, p2, true));
            }
        }
        return new PathGeometry([figure]);
    }

    private Color GetBandColor(GradeBand band)
    {
        var key = band switch
        {
            GradeBand.Excellent => "BandExcellentColor",
            GradeBand.Good => "BandGoodColor",
            GradeBand.Average => "BandAverageColor",
            GradeBand.Poor => "BandPoorColor",
            _ => "BandNeutralColor"
        };
        return TryFindResource(key) is Color c ? c : Color.FromRgb(23, 161, 133);
    }
}
