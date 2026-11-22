using System.Collections.ObjectModel;
using System.Windows;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public sealed class StravaMealRowViewModel : ObservableObject
{
    private bool _isSubmitting;
    public StravaCZMeal Meal { get; }
    public string TypeBadge => Meal.TypeDescription.ToUpperInvariant();
    public string DisplayName => Meal.DisplayName;
    public string PriceText => Meal.Price > 0 ? $"{Meal.Price:0.##} Kč" : string.Empty;
    public string AllergensText => Meal.Allergens.Count > 0
        ? string.Join(", ", Meal.Allergens.Select(a => $"{a.Code}"))
        : string.Empty;
    public bool IsOrdered => Meal.IsOrdered;
    public bool CanModify => Meal.CanModify;
    public bool IsMain => Meal.Type == StravaCZMealType.Main;
    public bool IsLocked => Meal.Type == StravaCZMealType.Main && !Meal.CanModify;

    public bool IsSubmitting
    {
        get => _isSubmitting;
        set => SetProperty(ref _isSubmitting, value);
    }

    public StravaMealRowViewModel(StravaCZMeal meal) => Meal = meal;
}

public sealed record StravaDaySectionViewModel(
    string DateKey,
    string WeekdayTitle,
    string ShortDate,
    List<StravaMealRowViewModel> Meals
);

public sealed class StravaCZViewModel : ObservableObject
{
    private readonly StravaCZClient _client;
    private readonly Action _onMealsChanged;

    private StravaCZSession? _session;
    private string _canteenNumber = string.Empty;
    private string _username = string.Empty;
    private string _password = string.Empty;
    private bool _isBusy;
    private string? _errorMessage;
    private List<StravaCZDayMenu> _rawMenus = [];

    public StravaCZViewModel(StravaCZClient client, Action onMealsChanged)
    {
        _client = client;
        _onMealsChanged = onMealsChanged;
        Days = [];

        ConnectCommand = new AsyncRelayCommand(ConnectAsync, CanConnect);
        ConnectDemoCommand = new AsyncRelayCommand(ConnectDemoAsync);
        RefreshCommand = new AsyncRelayCommand(RefreshAsync);
        DisconnectCommand = new AsyncRelayCommand(DisconnectAsync);
        ToggleMealCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is StravaMealRowViewModel row) await ToggleMealAsync(row);
        });

        _session = _client.LoadSession();
        if (_session is not null)
        {
            _rawMenus = _client.LoadCachedMenu();
            RebuildDays();
        }

        LocalizationService.Instance.PropertyChanged += (_, _) => RebuildDays();
    }

    public LocalizationService L10n => LocalizationService.Instance;
    public ObservableCollection<StravaDaySectionViewModel> Days { get; }
    public IReadOnlyList<StravaCZDayMenu> RawMenus => _rawMenus;

    public StravaCZSession? Session
    {
        get => _session;
        private set
        {
            if (SetProperty(ref _session, value))
            {
                OnPropertyChanged(nameof(IsConnected));
                OnPropertyChanged(nameof(BalanceText));
                OnPropertyChanged(nameof(CanteenLabel));
                OnPropertyChanged(nameof(OrderedCount));
            }
        }
    }

    public bool IsConnected => Session is not null;
    public string BalanceText => Session is null ? "–" : $"{Session.Balance:0.00} {Session.Currency}";
    public string CanteenLabel => Session is null ? string.Empty : (string.IsNullOrWhiteSpace(Session.CanteenName) ? Session.CanteenNumber : Session.CanteenName);
    public int OrderedCount => _rawMenus.SelectMany(d => d.Meals).Count(m => m.Type == StravaCZMealType.Main && m.IsOrdered);

    public string CanteenNumber
    {
        get => _canteenNumber;
        set { if (SetProperty(ref _canteenNumber, value)) ConnectCommand.RaiseCanExecuteChanged(); }
    }

    public string Username
    {
        get => _username;
        set { if (SetProperty(ref _username, value)) ConnectCommand.RaiseCanExecuteChanged(); }
    }

    public string Password
    {
        get => _password;
        set { if (SetProperty(ref _password, value)) ConnectCommand.RaiseCanExecuteChanged(); }
    }

    public bool IsBusy { get => _isBusy; set => SetProperty(ref _isBusy, value); }
    public string? ErrorMessage { get => _errorMessage; set => SetProperty(ref _errorMessage, value); }

    public AsyncRelayCommand ConnectCommand { get; }
    public AsyncRelayCommand ConnectDemoCommand { get; }
    public AsyncRelayCommand RefreshCommand { get; }
    public AsyncRelayCommand DisconnectCommand { get; }
    public AsyncRelayCommand ToggleMealCommand { get; }

    private bool CanConnect() => !string.IsNullOrWhiteSpace(CanteenNumber) && !string.IsNullOrWhiteSpace(Username) && !string.IsNullOrWhiteSpace(Password);

    private async Task ConnectAsync()
    {
        ErrorMessage = null;
        IsBusy = true;
        try
        {
            Session = await _client.LoginAsync(CanteenNumber, Username, Password);
            Password = string.Empty;
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task ConnectDemoAsync()
    {
        ErrorMessage = null;
        IsBusy = true;
        try
        {
            Session = _client.ConnectDemo();
            await RefreshAsync();
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task RefreshAsync()
    {
        if (Session is null) return;
        ErrorMessage = null;
        IsBusy = true;
        try
        {
            _rawMenus = await _client.GetMenuAsync(Session);
            RebuildDays();
            _onMealsChanged();
        }
        catch (StravaCZException ex) when (ex.IsAuthenticationError)
        {
            Session = null;
            _rawMenus = [];
            Days.Clear();
            ErrorMessage = ex.Message;
            _onMealsChanged();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task ToggleMealAsync(StravaMealRowViewModel row)
    {
        if (Session is null || !row.CanModify || row.IsSubmitting) return;
        bool wantOrdered = !row.IsOrdered;

        if (wantOrdered)
        {
            var existing = _rawMenus
                .FirstOrDefault(d => d.DateKey == row.Meal.DateKey)?
                .Meals.FirstOrDefault(m => m.Type == StravaCZMealType.Main && m.IsOrdered && m.Id != row.Meal.Id);

            if (existing is not null)
            {
                var confirm = MessageBox.Show(
                    L10n.Format("meals.replaceBody", existing.DisplayName, row.DisplayName),
                    L10n["meals.replaceTitle"],
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                if (confirm != MessageBoxResult.Yes) return;
            }
        }

        row.IsSubmitting = true;
        ErrorMessage = null;
        try
        {
            var (updatedSession, updatedMenu) = await _client.SetMealOrderAsync(Session, row.Meal, wantOrdered);
            Session = updatedSession;
            _rawMenus = updatedMenu;
            RebuildDays();
            _onMealsChanged();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            row.IsSubmitting = false;
        }
    }

    public async Task DisconnectAsync()
    {
        IsBusy = true;
        try
        {
            await _client.LogoutAsync(Session);
            Session = null;
            _rawMenus = [];
            Days.Clear();
            _onMealsChanged();
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void RebuildDays()
    {
        Days.Clear();
        var culture = L10n.ActiveCulture;
        foreach (var day in _rawMenus)
        {
            var weekday = culture.TextInfo.ToTitleCase(day.Date.ToString("dddd", culture));
            var shortDate = day.Date.ToString("d. M. yyyy", culture);
            Days.Add(new StravaDaySectionViewModel(
                day.DateKey,
                weekday,
                shortDate,
                day.Meals.Select(m => new StravaMealRowViewModel(m)).ToList()));
        }
        OnPropertyChanged(nameof(OrderedCount));
        OnPropertyChanged(nameof(BalanceText));
    }
}
