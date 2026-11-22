using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Gradely.Windows.Native;
using Gradely.Windows.ViewModels;

namespace Gradely.Windows.Views;

public partial class ReportCardWindow : Window
{
    public ReportCardWindow(ReportCardViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
        var app = (App)Application.Current;
        Color? cap = TryFindResource("SettingsBackgroundColor") is Color c ? c : null;
        WindowsThemeInterop.ApplyWindowChrome(this, app.IsDarkThemeActive, cap);
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
    }
}
