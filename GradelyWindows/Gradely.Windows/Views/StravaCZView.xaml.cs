using System.Windows;
using System.Windows.Controls;
using Gradely.Windows.ViewModels;

namespace Gradely.Windows.Views;

public partial class StravaCZView : UserControl
{
    public StravaCZView() => InitializeComponent();

    private void StravaPasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel main)
            main.Strava.Password = StravaPasswordBox.Password;
    }
}
