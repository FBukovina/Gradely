using System.Windows;
using System.Windows.Input;
using Gradely.Windows.ViewModels;

namespace Gradely.Windows.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    public MainWindow(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;

        _vm.RequestOpenKomens += OpenKomens;
        _vm.RequestOpenPlanner += OpenPlanner;
        _vm.RequestOpenReportCard += OpenReportCard;
        _vm.RequestOpenSettings += OpenSettings;

        PreviewKeyDown += OnPreviewKeyDown;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_vm.IsSignedIn) return;
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control;
        if (!ctrl) return;

        switch (e.Key)
        {
            case Key.D1:
                _vm.ActiveTab = AppTab.Today;
                e.Handled = true;
                break;
            case Key.D2:
                _vm.ActiveTab = AppTab.Marks;
                e.Handled = true;
                break;
            case Key.D3:
                _vm.ActiveTab = AppTab.Absence;
                e.Handled = true;
                break;
            case Key.D4:
                _vm.ActiveTab = AppTab.Timetable;
                e.Handled = true;
                break;
            case Key.D5 when _vm.ShowMealsTab:
                _vm.ActiveTab = AppTab.Meals;
                e.Handled = true;
                break;
            case Key.R:
                if (_vm.RefreshCommand.CanExecute(null)) _vm.RefreshCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.N:
                _vm.Planner.OpenEditor(null);
                OpenPlanner();
                e.Handled = true;
                break;
            case Key.OemComma:
                OpenSettings();
                e.Handled = true;
                break;
            case Key.Left when _vm.IsTimetableTab:
                if (_vm.Timetable.PreviousWeekCommand.CanExecute(null)) _vm.Timetable.PreviousWeekCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Right when _vm.IsTimetableTab:
                if (_vm.Timetable.NextWeekCommand.CanExecute(null)) _vm.Timetable.NextWeekCommand.Execute(null);
                e.Handled = true;
                break;
        }
    }

    private void OpenKomens()
    {
        var win = new KomensWindow(_vm.Komens) { Owner = this };
        win.ShowDialog();
    }

    private void OpenPlanner()
    {
        var win = new PlannerWindow(_vm.Planner) { Owner = this };
        win.ShowDialog();
    }

    private void OpenReportCard()
    {
        var win = new ReportCardWindow(_vm.ReportCard) { Owner = this };
        win.ShowDialog();
    }

    private void OpenSettings()
    {
        SettingsWindow? win = null;
        var settingsVm = _vm.CreateSettingsViewModel(() => win?.Close());
        win = new SettingsWindow(settingsVm) { Owner = this };
        win.ShowDialog();
    }
}
