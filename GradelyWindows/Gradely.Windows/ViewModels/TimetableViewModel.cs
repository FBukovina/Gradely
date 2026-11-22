using System.Collections.ObjectModel;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public sealed record TimetableDayHeader(
    int DayOfWeek,
    string WeekdayShort,
    string DayNumber,
    bool IsToday,
    string? HolidayDescription
);

public sealed record TimetableGridCellItem(
    TimetableLesson Lesson,
    TimetableDay Day,
    bool IsCurrentNow,
    string Subtitle,
    string? ChangeLabel,
    bool HasPlannerItem
);

public sealed class TimetableGridRow
{
    public TimetableHour Hour { get; init; } = new();
    public bool IsCurrentHour { get; init; }
    public List<TimetableGridCellItem> Monday { get; init; } = [];
    public List<TimetableGridCellItem> Tuesday { get; init; } = [];
    public List<TimetableGridCellItem> Wednesday { get; init; } = [];
    public List<TimetableGridCellItem> Thursday { get; init; } = [];
    public List<TimetableGridCellItem> Friday { get; init; } = [];
}

public sealed class TimetableViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private readonly Action<TimetableLesson, TimetableDay> _onAddToPlanner;

    private DateOnly _currentMonday = TimetableMapper.MondayOfWeek(DateOnly.FromDateTime(DateTime.Today));
    private TimetableKind _kind = TimetableKind.Actual;
    private TimetableWeek? _loadedWeek;
    private IReadOnlyList<PlannerItem> _plannerItems = [];
    private IReadOnlyList<HomeworkItem> _homeworks = [];

    private bool _isLoading;
    private string? _errorMessage;
    private TimetableGridCellItem? _selectedLesson;

    public TimetableViewModel(SchoolRepository repository, Action<TimetableLesson, TimetableDay> onAddToPlanner)
    {
        _repository = repository;
        _onAddToPlanner = onAddToPlanner;

        DayHeaders = [];
        GridRows = [];
        SelectedLessonHomeworks = [];
        SelectedLessonPlannerItems = [];

        PreviousWeekCommand = new AsyncRelayCommand(() => ShiftWeekAsync(-7));
        NextWeekCommand = new AsyncRelayCommand(() => ShiftWeekAsync(7));
        TodayWeekCommand = new AsyncRelayCommand(GoToCurrentWeekAsync);
        ToggleKindCommand = new AsyncRelayCommand(ToggleKindAsync);
        SelectLessonCommand = new RelayCommand(obj =>
        {
            if (obj is TimetableGridCellItem cell) SelectedLesson = cell;
        });
        CloseDetailCommand = new RelayCommand(() => SelectedLesson = null);
        AddSelectedLessonToPlannerCommand = new RelayCommand(() =>
        {
            if (SelectedLesson is not null)
                _onAddToPlanner(SelectedLesson.Lesson, SelectedLesson.Day);
        });

        LocalizationService.Instance.PropertyChanged += (_, _) => RebuildGrid();
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public ObservableCollection<TimetableDayHeader> DayHeaders { get; }
    public ObservableCollection<TimetableGridRow> GridRows { get; }
    public ObservableCollection<HomeworkItem> SelectedLessonHomeworks { get; }
    public ObservableCollection<PlannerItem> SelectedLessonPlannerItems { get; }

    public TimetableWeek? LoadedWeek => _loadedWeek;
    public DateOnly CurrentMonday => _currentMonday;

    public TimetableKind Kind
    {
        get => _kind;
        set
        {
            if (SetProperty(ref _kind, value))
            {
                OnPropertyChanged(nameof(IsActual));
                OnPropertyChanged(nameof(IsPermanent));
                OnPropertyChanged(nameof(WeekTitle));
            }
        }
    }

    public bool IsActual
    {
        get => Kind == TimetableKind.Actual;
        set { if (value && Kind != TimetableKind.Actual) _ = SetKindAsync(TimetableKind.Actual); }
    }

    public bool IsPermanent
    {
        get => Kind == TimetableKind.Permanent;
        set { if (value && Kind != TimetableKind.Permanent) _ = SetKindAsync(TimetableKind.Permanent); }
    }

    public bool SupportsPermanent => _repository.CurrentSession?.Provider.SupportsPermanentTimetable() == true;

    public bool IsCurrentWeek => _currentMonday == TimetableMapper.MondayOfWeek(DateOnly.FromDateTime(DateTime.Today));

    public string WeekTitle
    {
        get
        {
            if (Kind == TimetableKind.Permanent)
                return L10n["timetable.permanent"];
            var friday = _currentMonday.AddDays(4);
            var culture = L10n.ActiveCulture;
            return $"{_currentMonday.ToString("d. M.", culture)} – {friday.ToString("d. M. yyyy", culture)}";
        }
    }

    public bool IsLoading { get => _isLoading; set => SetProperty(ref _isLoading, value); }
    public string? ErrorMessage { get => _errorMessage; set => SetProperty(ref _errorMessage, value); }

    public TimetableGridCellItem? SelectedLesson
    {
        get => _selectedLesson;
        set
        {
            if (SetProperty(ref _selectedLesson, value))
            {
                OnPropertyChanged(nameof(HasSelectedLesson));
                OnPropertyChanged(nameof(SelectedLessonGroupsText));
                OnPropertyChanged(nameof(SelectedLessonCyclesText));
                OnPropertyChanged(nameof(SelectedLessonTimeText));
                RebuildSelectedLessonLinkedItems();
            }
        }
    }

    public bool HasSelectedLesson => SelectedLesson is not null;
    public string SelectedLessonTimeText => SelectedLesson is null
        ? string.Empty
        : $"{SelectedLesson.Lesson.Hour.Caption}. ({SelectedLesson.Lesson.Hour.BeginTime}–{SelectedLesson.Lesson.Hour.EndTime})";
    public string SelectedLessonGroupsText => SelectedLesson is null ? string.Empty : string.Join(", ", SelectedLesson.Lesson.GroupNames);
    public string SelectedLessonCyclesText => SelectedLesson is null ? string.Empty : string.Join(", ", SelectedLesson.Lesson.Cycles);

    public AsyncRelayCommand PreviousWeekCommand { get; }
    public AsyncRelayCommand NextWeekCommand { get; }
    public AsyncRelayCommand TodayWeekCommand { get; }
    public AsyncRelayCommand ToggleKindCommand { get; }
    public RelayCommand SelectLessonCommand { get; }
    public RelayCommand CloseDetailCommand { get; }
    public RelayCommand AddSelectedLessonToPlannerCommand { get; }

    public void UpdateExternalContext(IReadOnlyList<HomeworkItem> homeworks, IReadOnlyList<PlannerItem> plannerItems)
    {
        _homeworks = homeworks;
        _plannerItems = plannerItems;
        RebuildGrid();
        RebuildSelectedLessonLinkedItems();
    }

    public async Task LoadAsync(bool forceNetwork = false)
    {
        if (!_repository.IsSignedIn) return;
        ErrorMessage = null;
        OnPropertyChanged(nameof(SupportsPermanent));
        OnPropertyChanged(nameof(WeekTitle));
        OnPropertyChanged(nameof(IsCurrentWeek));

        if (!forceNetwork)
        {
            var cached = _repository.LoadCachedTimetable(Kind, _currentMonday);
            if (cached is not null)
            {
                _loadedWeek = TimetableMapper.Map(cached, Kind, _currentMonday);
                RebuildGrid();
            }
        }

        IsLoading = true;
        try
        {
            _loadedWeek = await _repository.GetTimetableAsync(Kind, _currentMonday);
            RebuildGrid();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task SetKindAsync(TimetableKind target)
    {
        Kind = target;
        SelectedLesson = null;
        await LoadAsync();
    }

    private Task ToggleKindAsync() =>
        SetKindAsync(Kind == TimetableKind.Actual ? TimetableKind.Permanent : TimetableKind.Actual);

    private async Task ShiftWeekAsync(int days)
    {
        if (Kind == TimetableKind.Permanent) return;
        _currentMonday = _currentMonday.AddDays(days);
        SelectedLesson = null;
        OnPropertyChanged(nameof(WeekTitle));
        OnPropertyChanged(nameof(IsCurrentWeek));
        await LoadAsync();
    }

    private async Task GoToCurrentWeekAsync()
    {
        _currentMonday = TimetableMapper.MondayOfWeek(DateOnly.FromDateTime(DateTime.Today));
        Kind = TimetableKind.Actual;
        SelectedLesson = null;
        OnPropertyChanged(nameof(WeekTitle));
        OnPropertyChanged(nameof(IsCurrentWeek));
        await LoadAsync();
    }

    private void RebuildGrid()
    {
        DayHeaders.Clear();
        GridRows.Clear();

        var culture = L10n.ActiveCulture;
        var today = DateOnly.FromDateTime(DateTime.Today);
        var nowTime = TimeOnly.FromDateTime(DateTime.Now);
        var scope = _repository.CurrentSession?.ScopeKey ?? string.Empty;

        var daysByDow = (_loadedWeek?.Days ?? []).ToDictionary(d => d.DayOfWeek, d => d);

        for (int dow = 1; dow <= 5; dow++)
        {
            daysByDow.TryGetValue(dow, out var day);
            var date = day?.Date ?? _currentMonday.AddDays(dow - 1);
            var weekdayShort = date.ToString("ddd", culture).ToUpper(culture);
            var dayNum = Kind == TimetableKind.Permanent ? string.Empty : date.Day.ToString();
            bool isToday = Kind == TimetableKind.Actual && date == today;
            string? holiday = day is { DayType: TimetableDayType.Holiday or TimetableDayType.DirectorDay or TimetableDayType.Celebration }
                ? (string.IsNullOrWhiteSpace(day.DayDescription) ? L10n["timetable.noLessonsDay"] : day.DayDescription)
                : null;

            DayHeaders.Add(new TimetableDayHeader(dow, weekdayShort, dayNum, isToday, holiday));
        }

        if (_loadedWeek is null) return;

        foreach (var hour in _loadedWeek.Hours)
        {
            bool isCurrentHour = false;
            if (Kind == TimetableKind.Actual &&
                TimetableMapper.TryParseTime(hour.BeginTime, out var bt) &&
                TimetableMapper.TryParseTime(hour.EndTime, out var et))
            {
                isCurrentHour = nowTime >= bt && nowTime < et;
            }

            List<TimetableGridCellItem> CellsForDay(int dow)
            {
                if (!daysByDow.TryGetValue(dow, out var day)) return [];
                bool isDayToday = Kind == TimetableKind.Actual && day.Date == today;
                return day.Lessons
                    .Where(l => l.Hour.Id == hour.Id)
                    .Select(l =>
                    {
                        var subParts = new List<string>();
                        if (!string.IsNullOrWhiteSpace(l.RoomName)) subParts.Add(l.RoomName);
                        if (!string.IsNullOrWhiteSpace(l.TeacherAbbrev)) subParts.Add(l.TeacherAbbrev);
                        else if (!string.IsNullOrWhiteSpace(l.TeacherName)) subParts.Add(l.TeacherName);

                        string? changeLbl = l.ChangeKind switch
                        {
                            LessonChangeKind.Canceled => L10n["timetable.change.canceled"],
                            LessonChangeKind.RoomChanged => L10n["timetable.change.roomChanged"],
                            LessonChangeKind.Added => L10n["timetable.change.added"],
                            LessonChangeKind.Substitution => L10n["timetable.change.substitution"],
                            _ => null
                        };

                        bool hasPlanner = _plannerItems.Any(p => !p.IsCompleted && p.Lesson is not null && p.Lesson.Matches(l, day, scope));

                        return new TimetableGridCellItem(
                            l,
                            day,
                            isDayToday && isCurrentHour && !l.IsCanceled,
                            l.IsCanceled ? string.Empty : string.Join(" · ", subParts),
                            changeLbl,
                            hasPlanner);
                    })
                    .ToList();
            }

            GridRows.Add(new TimetableGridRow
            {
                Hour = hour,
                IsCurrentHour = isCurrentHour,
                Monday = CellsForDay(1),
                Tuesday = CellsForDay(2),
                Wednesday = CellsForDay(3),
                Thursday = CellsForDay(4),
                Friday = CellsForDay(5)
            });
        }
    }

    private void RebuildSelectedLessonLinkedItems()
    {
        SelectedLessonHomeworks.Clear();
        SelectedLessonPlannerItems.Clear();
        if (SelectedLesson is null) return;

        var lesson = SelectedLesson.Lesson;
        var day = SelectedLesson.Day;
        var scope = _repository.CurrentSession?.ScopeKey ?? string.Empty;

        var addedHw = new HashSet<string>(StringComparer.Ordinal);
        foreach (var hwId in lesson.HomeworkIds)
        {
            var hw = _homeworks.FirstOrDefault(h => h.Id == hwId);
            if (hw is not null && addedHw.Add(hw.Id))
                SelectedLessonHomeworks.Add(hw);
        }

        if (day.Date.HasValue && !string.IsNullOrEmpty(lesson.SubjectId))
        {
            foreach (var hw in _homeworks.Where(h =>
                !addedHw.Contains(h.Id) &&
                string.Equals(h.SubjectId, lesson.SubjectId, StringComparison.Ordinal) &&
                h.DueOn.HasValue &&
                DateOnly.FromDateTime(h.DueOn.Value.LocalDateTime) == day.Date.Value))
            {
                SelectedLessonHomeworks.Add(hw);
            }
        }

        foreach (var pi in _plannerItems.Where(p => p.Lesson is not null && p.Lesson.Matches(lesson, day, scope)))
            SelectedLessonPlannerItems.Add(pi);
    }
}
