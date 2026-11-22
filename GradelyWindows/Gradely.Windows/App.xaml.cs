using System.Windows;
using System.Windows.Media;
using Gradely.Core.Services;
using Gradely.Core.Stores;
using Gradely.Windows.Controls;
using Gradely.Windows.Native;
using Gradely.Windows.ViewModels;
using Gradely.Windows.Views;
using Microsoft.Win32;

namespace Gradely.Windows;

public partial class App : Application
{
    private AppThemePreference _currentPreference = AppThemePreference.System;
    public bool IsDarkThemeActive { get; private set; }

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var repository = new SchoolRepository();
        if (e.Args.Any(a => a.Equals("--demo", StringComparison.OrdinalIgnoreCase) || a.Equals("-demo", StringComparison.OrdinalIgnoreCase)))
        {
            await repository.SignInDemoAsync();
        }

        var mainVm = new MainViewModel(repository, ApplyTheme);
        var window = new MainWindow(mainVm);
        MainWindow = window;

        SystemEvents.UserPreferenceChanged += OnSystemPreferenceChanged;
        ApplyTheme(mainVm.Settings.Theme);

        window.Show();
        await mainVm.InitializeAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnSystemPreferenceChanged;
        base.OnExit(e);
    }

    private void OnSystemPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category == UserPreferenceCategory.General && _currentPreference == AppThemePreference.System)
        {
            Dispatcher.Invoke(() => ApplyTheme(AppThemePreference.System));
        }
    }

    public void ApplyTheme(AppThemePreference preference)
    {
        _currentPreference = preference;
        bool useDark = preference switch
        {
            AppThemePreference.Dark => true,
            AppThemePreference.Light => false,
            _ => WindowsThemeInterop.IsSystemDarkMode()
        };
        IsDarkThemeActive = useDark;

        var themeUri = new Uri(useDark ? "Themes/DarkTheme.xaml" : "Themes/LightTheme.xaml", UriKind.Relative);
        var newDict = new ResourceDictionary { Source = themeUri };

        var merged = Resources.MergedDictionaries;
        if (merged.Count > 0)
            merged[0] = newDict;
        else
            merged.Insert(0, newDict);

        Color? captionColor = TryFindResource("CanvasBackgroundColor") is Color c ? c : null;
        foreach (Window win in Windows)
        {
            WindowsThemeInterop.ApplyWindowChrome(win, useDark, captionColor);
            InvalidateAuroraControls(win);
        }
    }

    private static void InvalidateAuroraControls(DependencyObject root)
    {
        if (root is AuroraBackgroundControl aurora)
            aurora.InvalidateVisual();

        int count = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
            InvalidateAuroraControls(VisualTreeHelper.GetChild(root, i));
    }
}
