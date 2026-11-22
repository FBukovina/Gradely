using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Gradely.Windows.ViewModels;

namespace Gradely.Windows.Views;

public partial class LoginView : UserControl
{
    private bool _syncingPassword;

    public LoginView()
    {
        InitializeComponent();
        DataContextChanged += (_, _) =>
        {
            if (DataContext is LoginViewModel vm)
            {
                vm.PropertyChanged += (_, e) =>
                {
                    if (e.PropertyName == nameof(LoginViewModel.Password) && !_syncingPassword)
                    {
                        if (PasswordBoxControl.Password != vm.Password)
                            PasswordBoxControl.Password = vm.Password;
                    }
                };
            }
        };
    }

    private void PasswordBoxControl_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is not LoginViewModel vm) return;
        _syncingPassword = true;
        vm.Password = PasswordBoxControl.Password;
        _syncingPassword = false;
    }

    private void SchoolUrlBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && DataContext is LoginViewModel vm && vm.ContinueCommand.CanExecute(null))
            vm.ContinueCommand.Execute(null);
    }

    private void UsernameBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
            PasswordBoxControl.Focus();
    }

    private void PasswordBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && DataContext is LoginViewModel vm && vm.SignInCommand.CanExecute(null))
            vm.SignInCommand.Execute(null);
    }
}
