using System.Windows;
using System.Windows.Media;

namespace Gradely.Windows.Controls;

/// <summary>
/// Renders Gradey's signature 3-orb ambient teal/emerald Aurora backdrop.
/// </summary>
public sealed class AuroraBackgroundControl : FrameworkElement
{
    public AuroraBackgroundControl()
    {
        IsHitTestVisible = false;
    }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0) return;

        var baseBg = TryFindResource("CanvasBackgroundBrush") as Brush ?? Brushes.White;
        dc.DrawRectangle(baseBg, null, new Rect(0, 0, w, h));

        var primary = GetColor("BrandPrimaryColor", Color.FromRgb(23, 161, 133));
        var secondary = GetColor("BrandSecondaryColor", Color.FromRgb(29, 165, 101));

        // 1. Primary orb top-center (30% alpha in SwiftUI, softened gently for crisp Windows readability)
        DrawGlowOrb(dc, new Point(w * 0.52, h * 0.02), w * 0.80, primary, 0.20);

        // 2. Secondary orb upper-right
        DrawGlowOrb(dc, new Point(w * 1.02, h * 0.26), w * 0.58, secondary, 0.16);

        // 3. Primary orb mid-left
        DrawGlowOrb(dc, new Point(-w * 0.08, h * 0.62), w * 0.52, primary, 0.12);
    }

    private static void DrawGlowOrb(DrawingContext dc, Point center, double radius, Color color, double peakAlpha)
    {
        if (radius <= 0) return;
        byte a0 = (byte)(255 * peakAlpha);
        byte a1 = (byte)(255 * peakAlpha * 0.35);

        var brush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5
        };
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(a0, color.R, color.G, color.B), 0.0));
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(a1, color.R, color.G, color.B), 0.48));
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(0, color.R, color.G, color.B), 1.0));
        brush.Freeze();

        dc.DrawEllipse(brush, null, center, radius, radius);
    }

    private Color GetColor(string key, Color fallback) =>
        TryFindResource(key) is Color c ? c : fallback;
}
