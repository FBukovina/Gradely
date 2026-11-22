using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Gradely.Core.Support;

namespace Gradely.Windows.Controls;

public sealed record MonthlyAbsenceBarItem(
    string MonthLabel,
    int Unsolved,
    int Ok,
    int Missed,
    int Late,
    int Soon,
    int School,
    int DistanceTeaching
)
{
    public int Total => Unsolved + Ok + Missed + Late + Soon + School + DistanceTeaching;
}

public sealed class AbsenceMonthsChart : FrameworkElement
{
    public static readonly DependencyProperty ItemsProperty = DependencyProperty.Register(
        nameof(Items),
        typeof(IReadOnlyList<MonthlyAbsenceBarItem>),
        typeof(AbsenceMonthsChart),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public IReadOnlyList<MonthlyAbsenceBarItem>? Items
    {
        get => (IReadOnlyList<MonthlyAbsenceBarItem>?)GetValue(ItemsProperty);
        set => SetValue(ItemsProperty, value);
    }

    protected override void OnRender(DrawingContext dc)
    {
        var items = Items;
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0 || items is null || items.Count == 0) return;

        var secondaryBrush = TryFindResource("SecondaryLabelBrush") as Brush ?? Brushes.Gray;
        var hairlineBrush = TryFindResource("HairlineBrush") as Brush ?? Brushes.LightGray;
        var fontFamily = TryFindResource("GradelyFont") as FontFamily ?? new FontFamily("Segoe UI");
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        double left = 8;
        double top = 12;
        double right = Math.Max(left + 20, w - 34);
        double bottom = Math.Max(top + 20, h - 26);
        var plot = new Rect(left, top, right - left, bottom - top);

        int maxVal = Math.Max(1, items.Max(i => i.Total));
        int niceMax = ((maxVal + 4) / 5) * 5;
        if (niceMax < 5) niceMax = 5;

        var gridPen = new Pen(hairlineBrush, 1) { DashStyle = new DashStyle([3, 4], 0) };
        for (int step = 0; step <= 2; step++)
        {
            double frac = step / 2.0;
            double y = plot.Bottom - frac * plot.Height;
            dc.DrawLine(gridPen, new Point(plot.Left, y), new Point(plot.Right, y));

            int val = (int)Math.Round(niceMax * frac);
            var ft = new FormattedText(
                val.ToString(CultureInfo.InvariantCulture),
                CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                new Typeface(fontFamily, FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
                11, secondaryBrush, dpi);
            dc.DrawText(ft, new Point(plot.Right + 6, y - ft.Height / 2));
        }

        double slotWidth = plot.Width / items.Count;
        double barWidth = Math.Clamp(slotWidth * 0.48, 12, 34);

        var okBrush = GetBrush("BrandSecondaryBrush", Brushes.MediumSeaGreen);
        var unsolvedBrush = GetBrush("BrandPrimaryBrush", Brushes.Teal);
        var missedBrush = GetBrush("BandPoorBrush", Brushes.Crimson);
        var lateBrush = GetBrush("BandAverageBrush", Brushes.Goldenrod);
        var soonBrush = GetBrush("WarningOrangeBrush", Brushes.Orange);
        var otherBrush = GetBrush("BandGoodBrush", Brushes.CadetBlue);

        for (int i = 0; i < items.Count; i++)
        {
            var item = items[i];
            double centerX = plot.Left + (i + 0.5) * slotWidth;
            double x = centerX - barWidth / 2;
            double currentBottom = plot.Bottom;

            (int Count, Brush Brush)[] segments =
            [
                (item.Ok, okBrush),
                (item.Unsolved, unsolvedBrush),
                (item.Missed, missedBrush),
                (item.Late, lateBrush),
                (item.Soon, soonBrush),
                (item.School + item.DistanceTeaching, otherBrush)
            ];

            foreach (var (count, brush) in segments)
            {
                if (count <= 0) continue;
                double segH = (double)count / niceMax * plot.Height;
                var rect = new Rect(x, currentBottom - segH, barWidth, Math.Max(2, segH));
                dc.DrawRoundedRectangle(brush, null, rect, 3, 3);
                currentBottom -= segH + 1;
            }

            var lbl = new FormattedText(
                item.MonthLabel,
                LocalizationService.Instance.ActiveCulture,
                FlowDirection.LeftToRight,
                new Typeface(fontFamily, FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
                11, secondaryBrush, dpi);
            dc.DrawText(lbl, new Point(centerX - lbl.Width / 2, plot.Bottom + 6));
        }
    }

    private Brush GetBrush(string key, Brush fallback) =>
        TryFindResource(key) as Brush ?? fallback;
}
