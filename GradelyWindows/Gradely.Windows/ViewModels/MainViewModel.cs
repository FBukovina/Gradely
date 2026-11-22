using System.Windows.Threading;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Stores;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public enum AppTab
{
    Today = 0,
    Marks = 1,
    Absence = 2,
    Timetable = 3,
    Meals = 4
}

public sealed class MainViewModel : ObservableObject
{
    private readonly DispatcherTimer _clockTimer;
    private readonly Action<AppThemePreference> _applyTheme;

    private AppTab _activeTab = AppTab.Today;
    private bool _isSignedIn;
    private bool _isRefreshing;
    private int _unreadKomensCount;
    private string? _globalError;
    private bool _showMealsTab = true;

    private UserResponse? _user;
    private MarksResponse? _marks;
    private AbsenceResponse? _absence;
    private TimetableWeek? _currentWeek;
    private List<HomeworkItem> _homeworks = [];
    private List<PlannerItem> _plannerItems = [];
    private List<ReportCardTerm> _reportCards = [];

    public SchoolRepository Repository { get; }
    public AppSettings Settings { get; }

    public LoginViewModel Login { get; }
    public TodayViewModel Today { get; }
    public SubjectsViewModel Subjects { get; }
    public TimetableViewModel Timetable { get; }
    public AbsenceViewModel Absence { get; }
    public StravaCZViewModel Strava { get; }
    public KomensViewModel Komens { get; }
    public PlannerViewModel Planner { get; }
    public ReportCardViewModel ReportCard { get; }

    public event Action? RequestOpenKomens;
    public event Action? RequestOpenPlanner;
    public event Action? RequestOpenReportCard;
    public event Action? RequestOpenSettings;

    public MainViewModel(SchoolRepository repository, Action<AppThemePreference> applyTheme)
    {
        Repository = repository;
        _applyTheme = applyTheme;

        Settings = Repository.SettingsStore.Load();
        ApplySettings(Settings);

        Login = new LoginViewModel(Repository, OnSignedIn);
        Today = new TodayViewModel();
        Subjects = new SubjectsViewModel(Repository);
        Timetable = new TimetableViewModel(Repository, OnAddLessonToPlanner);
        Absence = new AbsenceViewModel(Repository);
        Strava = new StravaCZViewModel(Repository.StravaClient, RefreshTodayProjection);
        Komens = new KomensViewModel(Repository, count => UnreadKomensCount = count);
        Planner = new PlannerViewModel(Repository, OnPlannerChanged);
        ReportCard = new ReportCardViewModel();

        SelectTabCommand = new RelayCommand(obj =>
        {
            if (obj is AppTab tab) ActiveTab = tab;
            else if (obj is string s && Enum.TryParse<AppTab>(s, out var parsed)) ActiveTab = parsed;
        });
        RefreshCommand = new AsyncRelayCommand(RefreshAllAsync);
        OpenKomensCommand = new RelayCommand(() => RequestOpenKomens?.Invoke());
        OpenPlannerCommand = new RelayCommand(() => RequestOpenPlanner?.Invoke());
        OpenReportCardCommand = new RelayCommand(() => RequestOpenReportCard?.Invoke());
        OpenSettingsCommand = new RelayCommand(() => RequestOpenSettings?.Invoke());
        OpenSubjectFromTodayCommand = new RelayCommand(obj =>
        {
            if (obj is string subjectId)
            {
                ActiveTab = AppTab.Marks;
                Subjects.SelectSubjectById(subjectId);
            }
        });

        _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _clockTimer.Tick += (_, _) => Today.RebuildClockDrivenText();
        _clockTimer.Start();

        IsSignedIn = Repository.IsSignedIn;
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public AppTab ActiveTab
    {
        get => _activeTab;
        set
        {
            if (SetProperty(ref _activeTab, value))
            {
                OnPropertyChanged(nameof(IsTodayTab));
                OnPropertyChanged(nameof(IsMarksTab));
                OnPropertyChanged(nameof(IsAbsenceTab));
                OnPropertyChanged(nameof(IsTimetableTab));
                OnPropertyChanged(nameof(IsMealsTab));
            }
        }
    }

    public bool IsTodayTab { get => ActiveTab == AppTab.Today; set { if (value) ActiveTab = AppTab.Today; } }
    public bool IsMarksTab { get => ActiveTab == AppTab.Marks; set { if (value) ActiveTab = AppTab.Marks; } }
    public bool IsAbsenceTab { get => ActiveTab == AppTab.Absence; set { if (value) ActiveTab = AppTab.Absence; } }
    public bool IsTimetableTab { get => ActiveTab == AppTab.Timetable; set { if (value) ActiveTab = AppTab.Timetable; } }
    public bool IsMealsTab { get => ActiveTab == AppTab.Meals; set { if (value) ActiveTab = AppTab.Meals; } }

    public bool IsSignedIn
    {
        get => _isSignedIn;
        private set
        {
            if (SetProperty(ref _isSignedIn, value))
            {
                OnPropertyChanged(nameof(SupportsKomens));
                OnPropertyChanged(nameof(SupportsReportCard));
                OnPropertyChanged(nameof(AccountDisplayName));
                OnPropertyChanged(nameof(SchoolDisplayName));
            }
        }
    }

    public bool IsRefreshing { get => _isRefreshing; set => SetProperty(ref _isRefreshing, value); }
    public int UnreadKomensCount { get => _unreadKomensCount; set => SetProperty(ref _unreadKomensCount, value); }
    public string? GlobalError { get => _globalError; set => SetProperty(ref _globalError, value); }
    public bool ShowMealsTab { get => _showMealsTab; set => SetProperty(ref _showMealsTab, value); }

    public bool SupportsKomens => Repository.CurrentSession?.Provider.SupportsKomens() == true;
    public bool SupportsReportCard => Repository.CurrentSession?.Provider.SupportsReportCard() == true;
    public string AccountDisplayName => _user?.NameWithoutClass ?? Repository.CurrentSession?.ActiveStudent?.FullName ?? Repository.CurrentSession?.Username ?? string.Empty;
    public string SchoolDisplayName => _user?.ResolvedSchoolName ?? Repository.CurrentSession?.SchoolName ?? string.Empty;

    public RelayCommand SelectTabCommand { get; }
    public AsyncRelayCommand RefreshCommand { get; }
    public RelayCommand OpenKomensCommand { get; }
    public RelayCommand OpenPlannerCommand { get; }
    public RelayCommand OpenReportCardCommand { get; }
    public RelayCommand OpenSettingsCommand { get; }
    public RelayCommand OpenSubjectFromTodayCommand { get; }

    public async Task InitializeAsync()
    {
        if (IsSignedIn)
        {
            LoadFromCache();
            await RefreshAllAsync();
        }
        else
        {
            _ = Login.LoadDirectoryAsync(forceRefresh: false);
        }
    }

    public SettingsViewModel CreateSettingsViewModel(Action closeWindow) =>
        new(Repository, Settings, ApplySettings, () =>
        {
            closeWindow();
            SignOut();
        }, async student =>
        {
            await Repository.SwitchEduPageStudentAsync(student);
            await RefreshAllAsync();
        });

    private void OnSignedIn(StoredSession session)
    {
        IsSignedIn = true;
        ActiveTab = AppTab.Today;
        LoadFromCache();
        _ = RefreshAllAsync();
    }

    public void SignOut()
    {
        Repository.SignOut();
        _user = null;
        _marks = null;
        _absence = null;
        _currentWeek = null;
        _homeworks = [];
        _plannerItems = [];
        _reportCards = [];
        UnreadKomensCount = 0;
        GlobalError = null;
        IsSignedIn = false;
        _ = Login.LoadDirectoryAsync(forceRefresh: false);
    }

    private void LoadFromCache()
    {
        if (Repository.CurrentSession is null) return;
        _user = Repository.LoadCachedUser();
        _marks = Repository.LoadCachedMarks();
        _absence = Repository.LoadCachedAbsence();
        var monday = TimetableMapper.MondayOfWeek(DateOnly.FromDateTime(DateTime.Today));
        var cachedTt = Repository.LoadCachedTimetable(TimetableKind.Actual, monday);
        _currentWeek = cachedTt is not null ? TimetableMapper.Map(cachedTt, TimetableKind.Actual, monday) : null;
        var cachedHw = Repository.LoadCachedHomework();
        _homeworks = cachedHw?.Homeworks.Select(HomeworkItem.FromDto).ToList() ?? [];
        _plannerItems = Repository.Planner.Load(Repository.CurrentSession.ScopeKey);
        var cachedRc = Repository.LoadCachedReportCards();
        _reportCards = cachedRc is not null ? ReportCardTerm.SortNewestFirst(cachedRc.Terms.Select(ReportCardTerm.FromDto)) : [];
        var cachedKomens = Repository.LoadCachedKomens();
        if (cachedKomens is not null) Komens.LoadSnapshot(cachedKomens);

        PropagateAllViews();
    }

    public async Task RefreshAllAsync()
    {
        if (!Repository.IsSignedIn || IsRefreshing) return;
        IsRefreshing = true;
        GlobalError = null;
        var scope = Repository.CurrentSession!.ScopeKey;

        try
        {
            _plannerItems = Repository.Planner.Load(scope);
            var today = DateOnly.FromDateTime(DateTime.Today);

            var userTask = SafeFetch(() => Repository.GetUserAsync());
            var marksTask = SafeFetch(() => Repository.GetMarksAsync());
            var absenceTask = SafeFetch(() => Repository.GetAbsenceAsync());
            var timetableTask = SafeFetch(() => Repository.GetTimetableAsync(TimetableKind.Actual, today));
            var homeworkTask = SafeFetch(() => Repository.GetHomeworksAsync());
            var komensTask = SafeFetch(() => Repository.GetKomensAsync());
            var reportCardTask = SafeFetch(() => Repository.GetReportCardsAsync());

            await Task.WhenAll(userTask, marksTask, absenceTask, timetableTask, homeworkTask, komensTask, reportCardTask);

            if (userTask.Result.Value is not null) _user = userTask.Result.Value;
            if (marksTask.Result.Value is not null) _marks = marksTask.Result.Value;
            if (absenceTask.Result.Value is not null) _absence = absenceTask.Result.Value;
            if (timetableTask.Result.Value is not null) _currentWeek = timetableTask.Result.Value;
            if (homeworkTask.Result.Value is not null) _homeworks = homeworkTask.Result.Value;
            if (komensTask.Result.Value is not null) Komens.LoadSnapshot(komensTask.Result.Value);
            if (reportCardTask.Result.Value is not null) _reportCards = reportCardTask.Result.Value;

            var firstErr = userTask.Result.Error ?? marksTask.Result.Error ?? absenceTask.Result.Error ?? timetableTask.Result.Error;
            if (firstErr is not null)
                GlobalError = firstErr.Message;

            PropagateAllViews();
            await Timetable.LoadAsync(forceNetwork: false);
            if (Strava.IsConnected)
                _ = Strava.RefreshAsync();
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    private void PropagateAllViews()
    {
        OnPropertyChanged(nameof(AccountDisplayName));
        OnPropertyChanged(nameof(SchoolDisplayName));
        OnPropertyChanged(nameof(SupportsKomens));
        OnPropertyChanged(nameof(SupportsReportCard));

        Absence.UpdateData(_absence, _currentWeek, Settings.ShowAbsenceSemesterAllowance);
        Subjects.UpdateData(_marks, Absence.LatestSubjectSummaries, _reportCards);
        Planner.UpdateData(_homeworks, _plannerItems, _marks?.Subjects ?? []);
        Timetable.UpdateExternalContext(_homeworks, _plannerItems);
        ReportCard.UpdateData(_marks, _reportCards);
        RefreshTodayProjection();
    }

    private void RefreshTodayProjection()
    {
        Today.UpdateSnapshot(_user, _marks, _currentWeek, _homeworks, _plannerItems, Strava.RawMenus, Settings.ShowMealsTab);
    }

    private void OnPlannerChanged()
    {
        if (Repository.CurrentSession is null) return;
        _plannerItems = Repository.Planner.Load(Repository.CurrentSession.ScopeKey);
        Timetable.UpdateExternalContext(_homeworks, _plannerItems);
        RefreshTodayProjection();
    }

    private void OnAddLessonToPlanner(TimetableLesson lesson, TimetableDay day)
    {
        Planner.OpenEditorForLesson(lesson, day);
        RequestOpenPlanner?.Invoke();
    }

    private void ApplySettings(AppSettings settings)
    {
        LocalizationService.Instance.Preference = settings.Language;
        LocalizationService.Instance.ChronicallyOnline = settings.ChronicallyOnline;
        ShowMealsTab = settings.ShowMealsTab;
        if (!ShowMealsTab && ActiveTab == AppTab.Meals)
            ActiveTab = AppTab.Today;

        _applyTheme(settings.Theme);
        Absence?.UpdateData(_absence, _currentWeek, settings.ShowAbsenceSemesterAllowance);
    }

    private static async Task<(T? Value, Exception? Error)> SafeFetch<T>(Func<Task<T>> call)
    {
        try
        {
            return (await call(), null);
        }
        catch (Exception ex)
        {
            return (default, ex);
        }
    }
}
