using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using Gradely.Core.Models;
using Gradely.Core.Support;

namespace Gradely.Windows.Converters;

public sealed class BoolToVisibilityConverter : IValueConverter
{
    public bool Invert { get; set; }

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        bool flag = value is bool b && b;
        if (Invert || string.Equals(parameter as string, "invert", StringComparison.OrdinalIgnoreCase))
            flag = !flag;
        return flag ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is Visibility v && (Invert ? v != Visibility.Visible : v == Visibility.Visible);
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public bool Invert { get; set; }

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        bool hasValue = value is string s ? !string.IsNullOrWhiteSpace(s) : value is not null;
        if (Invert || string.Equals(parameter as string, "invert", StringComparison.OrdinalIgnoreCase))
            hasValue = !hasValue;
        return hasValue ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class CountToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        int count = value is int i ? i : 0;
        bool invert = string.Equals(parameter as string, "invert", StringComparison.OrdinalIgnoreCase);
        bool visible = invert ? count == 0 : count > 0;
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class GradeBandBrushConverter : IValueConverter
{
    public bool Soft { get; set; }

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var band = value is GradeBand b ? b : GradeBand.Neutral;
        bool useSoft = Soft || string.Equals(parameter as string, "soft", StringComparison.OrdinalIgnoreCase);
        var key = (band, useSoft) switch
        {
            (GradeBand.Excellent, false) => "BandExcellentBrush",
            (GradeBand.Excellent, true) => "BandExcellentSoftBrush",
            (GradeBand.Good, false) => "BandGoodBrush",
            (GradeBand.Good, true) => "BandGoodSoftBrush",
            (GradeBand.Average, false) => "BandAverageBrush",
            (GradeBand.Average, true) => "BandAverageSoftBrush",
            (GradeBand.Poor, false) => "BandPoorBrush",
            (GradeBand.Poor, true) => "BandPoorSoftBrush",
            (_, true) => "BandNeutralSoftBrush",
            _ => "BandNeutralBrush"
        };
        return Application.Current.TryFindResource(key) ?? Brushes.Gray;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class AbsenceRiskBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var risk = value is AbsenceRiskLevel r ? r : AbsenceRiskLevel.Unavailable;
        var key = risk switch
        {
            AbsenceRiskLevel.OverLimit or AbsenceRiskLevel.High => "BandPoorBrush",
            AbsenceRiskLevel.Watch => "WarningOrangeBrush",
            AbsenceRiskLevel.Safe => "BrandPrimaryBrush",
            _ => "SecondaryLabelBrush"
        };
        return Application.Current.TryFindResource(key) ?? Brushes.Gray;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class LessonChangeBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var kind = value is LessonChangeKind k ? k : LessonChangeKind.None;
        var key = kind switch
        {
            LessonChangeKind.Canceled => "BandPoorBrush",
            LessonChangeKind.Substitution => "BandAverageBrush",
            LessonChangeKind.RoomChanged => "BandGoodBrush",
            LessonChangeKind.Added => "AddedPurpleBrush",
            _ => "BrandPrimaryBrush"
        };
        return Application.Current.TryFindResource(key) ?? Brushes.Teal;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
