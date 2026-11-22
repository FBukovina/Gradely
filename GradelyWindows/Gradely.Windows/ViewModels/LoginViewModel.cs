using System.Collections.ObjectModel;
using System.Diagnostics;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public sealed class LoginViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private readonly Action<StoredSession> _onSignedIn;
    private List<SchoolDirectorySchool> _allSchools = [];

    private SchoolProvider _provider = SchoolProvider.Bakalari;
    private int _step = 1;
    private string _searchQuery = string.Empty;
    private string _schoolUrl = string.Empty;
    private string _selectedSchoolName = string.Empty;
    private string _username = string.Empty;
    private string _password = string.Empty;
    private bool _showPassword;
    private bool _isLoadingDirectory;
    private bool _isSubmitting;
    private string? _errorMessage;
    private string? _statusMessage;

    private EduPageTwoFactorChallenge? _twoFactorChallenge;
    private string _twoFactorCode = string.Empty;
    private EduPagePendingParentSession? _pendingParentSession;

    public LoginViewModel(SchoolRepository repository, Action<StoredSession> onSignedIn)
    {
        _repository = repository;
        _onSignedIn = onSignedIn;

        SearchResults = [];
        AvailableStudents = [];

        ContinueCommand = new RelayCommand(AdvanceToStep2, CanContinueToStep2);
        BackToStep1Command = new RelayCommand(() => { Step = 1; ErrorMessage = null; });
        SelectSchoolCommand = new RelayCommand(obj =>
        {
            if (obj is SchoolDirectorySchool s) SelectDirectorySchool(s);
        });
        SignInCommand = new AsyncRelayCommand(SignInAsync, CanSignIn);
        UseDemoCommand = new RelayCommand(FillDemoCredentials);
        SubmitTwoFactorCommand = new AsyncRelayCommand(SubmitTwoFactorAsync, () => !string.IsNullOrWhiteSpace(TwoFactorCode));
        PollTwoFactorCommand = new AsyncRelayCommand(PollTwoFactorAsync);
        ResendTwoFactorCommand = new AsyncRelayCommand(ResendTwoFactorAsync);
        CancelOverlayCommand = new RelayCommand(() =>
        {
            TwoFactorChallenge = null;
            PendingParentSession = null;
            ErrorMessage = null;
            StatusMessage = null;
        });
        SelectStudentCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is SchoolStudentProfile student) await SelectStudentAsync(student);
        });
        OpenGitHubCommand = new RelayCommand(() =>
        {
            try { Process.Start(new ProcessStartInfo("https://github.com/FBukovina/Gradely") { UseShellExecute = true }); } catch { }
        });
        LoadDirectoryCommand = new AsyncRelayCommand(() => LoadDirectoryAsync(forceRefresh: false));

        LocalizationService.Instance.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(StepLabel));
            OnPropertyChanged(nameof(HeroTitle));
            OnPropertyChanged(nameof(HeroSubtitle));
            OnPropertyChanged(nameof(UrlPlaceholder));
            OnPropertyChanged(nameof(ProviderDisplayName));
        };
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public ObservableCollection<SchoolDirectorySchool> SearchResults { get; }
    public ObservableCollection<SchoolStudentProfile> AvailableStudents { get; }

    public SchoolProvider Provider
    {
        get => _provider;
        set
        {
            if (SetProperty(ref _provider, value))
            {
                OnPropertyChanged(nameof(IsBakalari));
                OnPropertyChanged(nameof(IsEduPage));
                OnPropertyChanged(nameof(UrlPlaceholder));
                OnPropertyChanged(nameof(ProviderDisplayName));
                ErrorMessage = null;
            }
        }
    }

    public bool IsBakalari
    {
        get => Provider == SchoolProvider.Bakalari;
        set { if (value) Provider = SchoolProvider.Bakalari; }
    }

    public bool IsEduPage
    {
        get => Provider == SchoolProvider.EduPage;
        set { if (value) Provider = SchoolProvider.EduPage; }
    }

    public string ProviderDisplayName => Provider.DisplayName();

    public int Step
    {
        get => _step;
        set
        {
            if (SetProperty(ref _step, value))
            {
                OnPropertyChanged(nameof(IsStep1));
                OnPropertyChanged(nameof(IsStep2));
                OnPropertyChanged(nameof(StepProgress));
                OnPropertyChanged(nameof(StepLabel));
                OnPropertyChanged(nameof(HeroTitle));
                OnPropertyChanged(nameof(HeroSubtitle));
            }
        }
    }

    public bool IsStep1 => Step == 1;
    public bool IsStep2 => Step == 2;
    public double StepProgress => Step == 1 ? 0.5 : 1.0;
    public string StepLabel => Step == 1 ? L10n["login.step1.label"] : L10n["login.step2.label"];
    public string HeroTitle => Step == 1 ? L10n["login.step1.title"] : L10n["login.step2.title"];
    public string HeroSubtitle => Step == 1 ? L10n["login.step1.subtitle"] : L10n["login.step2.subtitle"];
    public string UrlPlaceholder => IsBakalari ? L10n["login.urlPlaceholder"] : L10n["login.edupagePlaceholder"];

    public string SearchQuery
    {
        get => _searchQuery;
        set
        {
            if (SetProperty(ref _searchQuery, value))
                UpdateSearchResults();
        }
    }

    public string SchoolUrl
    {
        get => _schoolUrl;
        set
        {
            if (SetProperty(ref _schoolUrl, value))
            {
                ContinueCommand.RaiseCanExecuteChanged();
                ErrorMessage = null;
            }
        }
    }

    public string SelectedSchoolName
    {
        get => _selectedSchoolName;
        set => SetProperty(ref _selectedSchoolName, value);
    }

    public string Username
    {
        get => _username;
        set
        {
            if (SetProperty(ref _username, value))
            {
                SignInCommand.RaiseCanExecuteChanged();
                ErrorMessage = null;
            }
        }
    }

    public string Password
    {
        get => _password;
        set
        {
            if (SetProperty(ref _password, value))
            {
                SignInCommand.RaiseCanExecuteChanged();
                ErrorMessage = null;
            }
        }
    }

    public bool ShowPassword
    {
        get => _showPassword;
        set => SetProperty(ref _showPassword, value);
    }

    public bool IsLoadingDirectory
    {
        get => _isLoadingDirectory;
        set => SetProperty(ref _isLoadingDirectory, value);
    }

    public bool IsSubmitting
    {
        get => _isSubmitting;
        set
        {
            if (SetProperty(ref _isSubmitting, value))
                SignInCommand.RaiseCanExecuteChanged();
        }
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        set => SetProperty(ref _errorMessage, value);
    }

    public string? StatusMessage
    {
        get => _statusMessage;
        set => SetProperty(ref _statusMessage, value);
    }

    public EduPageTwoFactorChallenge? TwoFactorChallenge
    {
        get => _twoFactorChallenge;
        set
        {
            if (SetProperty(ref _twoFactorChallenge, value))
                OnPropertyChanged(nameof(IsShowingTwoFactor));
        }
    }

    public bool IsShowingTwoFactor => TwoFactorChallenge is not null;

    public string TwoFactorCode
    {
        get => _twoFactorCode;
        set
        {
            if (SetProperty(ref _twoFactorCode, value))
                SubmitTwoFactorCommand.RaiseCanExecuteChanged();
        }
    }

    public EduPagePendingParentSession? PendingParentSession
    {
        get => _pendingParentSession;
        set
        {
            if (SetProperty(ref _pendingParentSession, value))
            {
                OnPropertyChanged(nameof(IsShowingStudentPicker));
                AvailableStudents.Clear();
                if (value is not null)
                {
                    foreach (var s in value.Students) AvailableStudents.Add(s);
                }
            }
        }
    }

    public bool IsShowingStudentPicker => PendingParentSession is not null;

    public bool HasSearchQuery => !string.IsNullOrWhiteSpace(SearchQuery);
    public bool ShowNoSearchResults => HasSearchQuery && !IsLoadingDirectory && SearchResults.Count == 0;

    public RelayCommand ContinueCommand { get; }
    public RelayCommand BackToStep1Command { get; }
    public RelayCommand SelectSchoolCommand { get; }
    public AsyncRelayCommand SignInCommand { get; }
    public RelayCommand UseDemoCommand { get; }
    public AsyncRelayCommand SubmitTwoFactorCommand { get; }
    public AsyncRelayCommand PollTwoFactorCommand { get; }
    public AsyncRelayCommand ResendTwoFactorCommand { get; }
    public RelayCommand CancelOverlayCommand { get; }
    public AsyncRelayCommand SelectStudentCommand { get; }
    public RelayCommand OpenGitHubCommand { get; }
    public AsyncRelayCommand LoadDirectoryCommand { get; }

    public async Task LoadDirectoryAsync(bool forceRefresh)
    {
        if (IsLoadingDirectory) return;
        IsLoadingDirectory = true;
        try
        {
            var cached = _repository.DirectoryProvider.LoadCached();
            if (cached is { Schools.Count: > 0 })
            {
                _allSchools = cached.Schools;
                UpdateSearchResults();
            }
            var fresh = await _repository.DirectoryProvider.GetSchoolsAsync(forceRefresh);
            if (fresh.Count > 0)
            {
                _allSchools = fresh;
                UpdateSearchResults();
            }
        }
        catch
        {
            // Manual URL entry remains available even offline
        }
        finally
        {
            IsLoadingDirectory = false;
            OnPropertyChanged(nameof(ShowNoSearchResults));
        }
    }

    private void UpdateSearchResults()
    {
        SearchResults.Clear();
        if (!string.IsNullOrWhiteSpace(SearchQuery))
        {
            foreach (var match in SchoolDirectorySearch.Search(_allSchools, SearchQuery, limit: 8))
                SearchResults.Add(match);
        }
        OnPropertyChanged(nameof(HasSearchQuery));
        OnPropertyChanged(nameof(ShowNoSearchResults));
    }

    private void SelectDirectorySchool(SchoolDirectorySchool school)
    {
        SchoolUrl = school.SchoolUrl;
        SelectedSchoolName = school.Name;
        ErrorMessage = null;
        Step = 2;
    }

    private bool CanContinueToStep2() => !string.IsNullOrWhiteSpace(SchoolUrl);

    private void AdvanceToStep2()
    {
        ErrorMessage = null;
        try
        {
            var normalized = IsBakalari
                ? SchoolUrlNormalizer.NormalizeBakalariBaseUrl(SchoolUrl)
                : SchoolUrlNormalizer.NormalizeEduPageBaseUrl(SchoolUrl);

            SchoolUrl = SchoolUrlNormalizer.DisplayString(normalized);
            if (string.IsNullOrWhiteSpace(SelectedSchoolName))
                SelectedSchoolName = normalized.Host;
            Step = 2;
        }
        catch (UrlNormalizationException ex)
        {
            ErrorMessage = ex.Message;
        }
    }

    private void FillDemoCredentials()
    {
        Provider = SchoolProvider.Bakalari;
        SchoolUrl = DemoAccount.BaseUrl.TrimEnd('/');
        SelectedSchoolName = "Demo škola";
        Username = DemoAccount.Username;
        Password = DemoAccount.Password;
        ErrorMessage = null;
        Step = 2;
    }

    private bool CanSignIn() => !IsSubmitting && !string.IsNullOrWhiteSpace(Username) && !string.IsNullOrWhiteSpace(Password);

    private async Task SignInAsync()
    {
        ErrorMessage = null;
        StatusMessage = null;
        IsSubmitting = true;
        try
        {
            if (IsBakalari)
            {
                var session = await _repository.SignInBakalariAsync(SchoolUrl, Username, Password, SelectedSchoolName);
                _onSignedIn(session);
            }
            else
            {
                var outcome = await _repository.BeginEduPageLoginAsync(SchoolUrl, Username, Password);
                if (outcome.Session is not null)
                    _onSignedIn(outcome.Session);
                else if (outcome.TwoFactorChallenge is not null)
                {
                    TwoFactorCode = string.Empty;
                    TwoFactorChallenge = outcome.TwoFactorChallenge;
                }
                else if (outcome.PendingParentSession is not null)
                    PendingParentSession = outcome.PendingParentSession;
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsSubmitting = false;
        }
    }

    private async Task SubmitTwoFactorAsync()
    {
        if (TwoFactorChallenge is null) return;
        ErrorMessage = null;
        IsSubmitting = true;
        try
        {
            var outcome = await _repository.SubmitEduPageTwoFactorAsync(TwoFactorChallenge, TwoFactorCode);
            TwoFactorChallenge = null;
            if (outcome.Session is not null)
                _onSignedIn(outcome.Session);
            else if (outcome.PendingParentSession is not null)
                PendingParentSession = outcome.PendingParentSession;
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsSubmitting = false;
        }
    }

    private async Task PollTwoFactorAsync()
    {
        if (TwoFactorChallenge is null) return;
        ErrorMessage = null;
        StatusMessage = null;
        IsSubmitting = true;
        try
        {
            var approvedCode = await _repository.PollEduPageTwoFactorAsync(TwoFactorChallenge);
            if (!string.IsNullOrWhiteSpace(approvedCode))
            {
                TwoFactorCode = approvedCode;
                await SubmitTwoFactorAsync();
            }
            else
            {
                StatusMessage = L10n.IsCzech ? "Zatím nepotvrzeno v mobilní aplikaci." : "Not approved yet in your EduPage app.";
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsSubmitting = false;
        }
    }

    private async Task ResendTwoFactorAsync()
    {
        if (TwoFactorChallenge is null) return;
        ErrorMessage = null;
        try
        {
            var ok = await _repository.ResendEduPageTwoFactorAsync(TwoFactorChallenge);
            StatusMessage = ok
                ? (L10n.IsCzech ? "Oznámení bylo znovu odesláno." : "Notification resent.")
                : (L10n.IsCzech ? "Nepodařilo se znovu odeslat oznámení." : "Could not resend notification.");
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }

    private async Task SelectStudentAsync(SchoolStudentProfile student)
    {
        if (PendingParentSession is null) return;
        ErrorMessage = null;
        IsSubmitting = true;
        try
        {
            var session = await _repository.CompleteEduPageParentSelectionAsync(PendingParentSession, student);
            PendingParentSession = null;
            _onSignedIn(session);
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsSubmitting = false;
        }
    }
}
