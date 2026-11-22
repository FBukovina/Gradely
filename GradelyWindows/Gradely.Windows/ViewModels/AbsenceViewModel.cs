using System.Collections.ObjectModel;
using System.Globalization;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Support;
using Gradely.Windows.Controls;

namespace Gradely.Windows.ViewModels;

public sealed record AbsenceSubjectRowViewModel(
    AbsenceSubjectSummary Summary,
    string PercentageText,
    double ProgressRatio,
    string StatusLine,
    string? SemesterLine
);

public sealed record AbsenceDayRowViewModel(
    AbsenceDay RawDay,
    string DateLabel,
    string BreakdownText,
    int TotalHours,
    bool HasLocalOverride
);

public sealed class SelectableLessonForPrediction : ObservableObject
{
    private bool _isSelected;
    public AbsenceLessonCandidate Candidate { get; }
    public string PeriodCaption => Candidate.HourCaption;
    public string SubjectName => Candidate.SubjectName;
    public string TimeRange => Candidate.TimeRange;

    public bool IsSelected
    {
        get => _isSelected;
        set => SetProperty(ref _isSelected, value);
    }

    public SelectableLessonForPrediction(AbsenceLessonCandidate candidate, bool isSelected = false)
    {
        Candidate = candidate;
        _isSelected = isSelected;
    }
}

public sealed class AbsenceViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private AbsenceResponse? _rawResponse;
    private TimetableWeek? _referenceTimetable;
    private bool _showSemesterAllowance = true;

    private int _selectedSubTab; // 0 = Subjects, 1 = Days, 2 = Months
    private int _totalHours;
    private string _breakdownSummary = string.Empty;
    private string? _localAdjustmentBanner;
    private string? _reviewOverridesBanner;
    private bool _hasActiveOverrides;

    // Predictor
    private bool _isPredictorExpanded;
    private DateTime _predictorDate = DateTime.Today.AddDays(1);
    private AbsencePredictionSummary? _predictionSummary;
    private readonly Dictionary<string, AbsenceLessonCandidate> _selectedPredictionLessons = new(StringComparer.Ordinal);

    public AbsenceViewModel(SchoolRepository repository)
    {
        _repository = repository;
        Subjects = [];
        Days = [];
        Months = [];
        PredictorDayLessons = [];
        PredictionSubjectRows = [];

        TogglePredictorCommand = new RelayCommand(() =>
        {
            IsPredictorExpanded = !IsPredictorExpanded;
            if (IsPredictorExpanded) _ = LoadPredictorDayLessonsAsync();
        });
        ClearPredictionCommand = new RelayCommand(() =>
        {
            _selectedPredictionLessons.Clear();
            foreach (var l in PredictorDayLessons) l.IsSelected = false;
            RecomputePrediction();
        });
        HideDayLocallyCommand = new RelayCommand(obj =>
        {
            if (obj is AbsenceDayRowViewModel row) ToggleHideDayLocally(row);
        });
        RestoreAllOverridesCommand = new RelayCommand(() =>
        {
            if (_repository.CurrentSession is null) return;
            _repository.AbsenceOverrides.ClearAll(_repository.CurrentSession.ScopeKey);
            RebuildFromRaw();
        });

        LocalizationService.Instance.PropertyChanged += (_, _) => RebuildFromRaw();
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public ObservableCollection<AbsenceSubjectRowViewModel> Subjects { get; }
    public ObservableCollection<AbsenceDayRowViewModel> Days { get; }
    public ObservableCollection<MonthlyAbsenceBarItem> Months { get; }
    public ObservableCollection<SelectableLessonForPrediction> PredictorDayLessons { get; }
    public ObservableCollection<AbsenceSubjectPrediction> PredictionSubjectRows { get; }

    public List<AbsenceSubjectSummary> LatestSubjectSummaries { get; private set; } = [];

    public int SelectedSubTab
    {
        get => _selectedSubTab;
        set
        {
            if (SetProperty(ref _selectedSubTab, value))
            {
                OnPropertyChanged(nameof(IsSubjectsTab));
                OnPropertyChanged(nameof(IsDaysTab));
                OnPropertyChanged(nameof(IsMonthsTab));
            }
        }
    }

    public bool IsSubjectsTab { get => SelectedSubTab == 0; set { if (value) SelectedSubTab = 0; } }
    public bool IsDaysTab { get => SelectedSubTab == 1; set { if (value) SelectedSubTab = 1; } }
    public bool IsMonthsTab { get => SelectedSubTab == 2; set { if (value) SelectedSubTab = 2; } }

    public int TotalHours { get => _totalHours; set => SetProperty(ref _totalHours, value); }
    public string BreakdownSummary { get => _breakdownSummary; set => SetProperty(ref _breakdownSummary, value); }
    public string? LocalAdjustmentBanner { get => _localAdjustmentBanner; set => SetProperty(ref _localAdjustmentBanner, value); }
    public string? ReviewOverridesBanner { get => _reviewOverridesBanner; set => SetProperty(ref _reviewOverridesBanner, value); }
    public bool HasActiveOverrides { get => _hasActiveOverrides; set => SetProperty(ref _hasActiveOverrides, value); }

    public bool IsPredictorExpanded
    {
        get => _isPredictorExpanded;
        set => SetProperty(ref _isPredictorExpanded, value);
    }

    public DateTime PredictorDate
    {
        get => _predictorDate;
        set
        {
            if (SetProperty(ref _predictorDate, value))
                _ = LoadPredictorDayLessonsAsync();
        }
    }

    public AbsencePredictionSummary? PredictionSummary
    {
        get => _predictionSummary;
        set
        {
            if (SetProperty(ref _predictionSummary, value))
            {
                OnPropertyChanged(nameof(HasActivePrediction));
                OnPropertyChanged(nameof(PredictionHeadline));
            }
        }
    }

    public bool HasActivePrediction => PredictionSummary is { AddedHours: > 0 };
    public string PredictionHeadline => PredictionSummary is null
        ? string.Empty
        : $"{PredictionSummary.CurrentTotalHours} → {PredictionSummary.ProjectedTotalHours} {L10n["absence.hours"]} (+{PredictionSummary.AddedHours})";

    public RelayCommand TogglePredictorCommand { get; }
    public RelayCommand ClearPredictionCommand { get; }
    public RelayCommand HideDayLocallyCommand { get; }
    public RelayCommand RestoreAllOverridesCommand { get; }

    public void UpdateData(AbsenceResponse? response, TimetableWeek? currentWeek, bool showSemesterAllowance)
    {
        _rawResponse = response;
        _referenceTimetable = currentWeek;
        _showSemesterAllowance = showSemesterAllowance;
        RebuildFromRaw();
    }

    public void RebuildFromRaw()
    {
        Subjects.Clear();
        Days.Clear();
        Months.Clear();

        if (_rawResponse is null)
        {
            TotalHours = 0;
            BreakdownSummary = string.Empty;
            LatestSubjectSummaries = [];
            return;
        }

        var scope = _repository.CurrentSession?.ScopeKey ?? string.Empty;
        var savedOverrides = string.IsNullOrEmpty(scope) ? [] : _repository.AbsenceOverrides.Load(scope);
        var projected = AbsenceAnalytics.ProjectOverrides(_rawResponse, savedOverrides);

        HasActiveOverrides = projected.HasLocalAdjustments;
        LocalAdjustmentBanner = projected.HasLocalAdjustments
            ? L10n.Format("absence.localAdjusted", projected.ActiveOverrides.Count)
            : null;
        ReviewOverridesBanner = projected.NeedsReview
            ? L10n.Format("absence.needsReview", projected.ReviewOverrides.Count)
            : null;

        var effective = projected.EffectiveResponse;
        TotalHours = effective.Absences.Sum(d => d.Total);

        // Breakdown summary
        var parts = new List<string>();
        int unsolved = effective.Absences.Sum(d => d.Unsolved);
        int ok = effective.Absences.Sum(d => d.Ok);
        int missed = effective.Absences.Sum(d => d.Missed);
        int late = effective.Absences.Sum(d => d.Late);
        int soon = effective.Absences.Sum(d => d.Soon);
        if (unsolved > 0) parts.Add($"{L10n["absence.unsolved"]} {unsolved}");
        if (ok > 0) parts.Add($"{L10n["absence.ok"]} {ok}");
        if (missed > 0) parts.Add($"{L10n["absence.missed"]} {missed}");
        if (late > 0) parts.Add($"{L10n["absence.late"]} {late}");
        if (soon > 0) parts.Add($"{L10n["absence.soon"]} {soon}");
        var normThreshold = AbsenceAnalytics.NormalizeThreshold(effective.PercentageThreshold);
        if (normThreshold.HasValue) parts.Add(L10n.Format("absence.limit", normThreshold.Value));
        BreakdownSummary = string.Join(" · ", parts);

        // Estimate remaining lessons per subject through end of Czech term based on weekly schedule
        Dictionary<string, int>? remainingMap = null;
        DateOnly? termEnd = null;
        if (_showSemesterAllowance && _referenceTimetable is not null)
        {
            var today = DateOnly.FromDateTime(DateTime.Today);
            var (_, end) = AbsenceAnalytics.CzechTermBounds(today);
            termEnd = end;
            int remainingDays = Math.Max(0, end.DayNumber - today.DayNumber);
            int remainingWeeks = remainingDays / 7;
            if (remainingWeeks > 0)
            {
                remainingMap = new Dictionary<string, int>(StringComparer.Ordinal);
                foreach (var day in _referenceTimetable.Days)
                {
                    foreach (var l in day.Lessons.Where(l => !l.IsCanceled && !string.IsNullOrWhiteSpace(l.SubjectName)))
                    {
                        var key = AbsenceAnalytics.NormalizeKey(l.SubjectName);
                        remainingMap[key] = remainingMap.GetValueOrDefault(key) + remainingWeeks;
                    }
                }
            }
        }

        LatestSubjectSummaries = AbsenceAnalytics.SummarizeSubjects(effective, remainingMap, termEnd);
        foreach (var s in LatestSubjectSummaries)
        {
            double ratio = s.NormalizedThreshold is > 0 ? Math.Clamp(s.AbsencePercentage / s.NormalizedThreshold.Value, 0, 1.0) : 0;
            var statusParts = new List<string> { L10n.Format("absence.missedOfTotal", s.BaseCount, s.LessonsCount) };
            if (s.ExceedsThreshold)
                statusParts.Add(L10n["absence.overLimit"]);
            else if (s.MissesUntilLimit is int left)
                statusParts.Add(L10n.Format("absence.untilLimit", left));

            string? semLine = s.SemesterAllowance is SemesterAllowance sa
                ? sa.Kind switch
                {
                    SemesterAllowanceKind.CanMiss => L10n.Format("absence.semester.canMiss", sa.AllowedMisses),
                    SemesterAllowanceKind.NoMoreMisses => L10n["absence.semester.noMore"],
                    _ => L10n["absence.semester.over"]
                }
                : null;

            Subjects.Add(new AbsenceSubjectRowViewModel(
                s,
                s.AbsencePercentage.ToString("F1", L10n.ActiveCulture) + " %",
                ratio,
                string.Join(" · ", statusParts),
                semLine));
        }

        // Days list (show raw days with local override indicator so user can hide or restore directly)
        var activeOverrideDates = projected.ActiveOverrides.Select(o => o.DateKey).ToHashSet(StringComparer.Ordinal);
        foreach (var day in _rawResponse.Absences.OrderByDescending(d => d.DateKey, StringComparer.Ordinal))
        {
            var label = DateOnly.TryParseExact(day.DateKey, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
                ? d.ToString("ddd d. M. yyyy", L10n.ActiveCulture)
                : day.DateKey;
            var chips = new List<string>();
            if (day.Unsolved > 0) chips.Add($"? {day.Unsolved}");
            if (day.Ok > 0) chips.Add($"✓ {day.Ok}");
            if (day.Missed > 0) chips.Add($"N {day.Missed}");
            if (day.Late > 0) chips.Add($"P {day.Late}");
            if (day.Soon > 0) chips.Add($"O {day.Soon}");
            if (day.School > 0) chips.Add($"– {day.School}");
            if (day.DistanceTeaching > 0) chips.Add($"D {day.DistanceTeaching}");

            Days.Add(new AbsenceDayRowViewModel(day, label, string.Join("  ", chips), day.Total, activeOverrideDates.Contains(day.DateKey)));
        }

        // Months chart
        var monthly = effective.Absences
            .Where(d => d.DateKey.Length >= 7)
            .GroupBy(d => d.DateKey[..7], StringComparer.Ordinal)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g =>
            {
                var monthLbl = DateOnly.TryParseExact(g.Key + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var md)
                    ? md.ToString("MMM", L10n.ActiveCulture)
                    : g.Key;
                return new MonthlyAbsenceBarItem(
                    monthLbl,
                    g.Sum(x => x.Unsolved),
                    g.Sum(x => x.Ok),
                    g.Sum(x => x.Missed),
                    g.Sum(x => x.Late),
                    g.Sum(x => x.Soon),
                    g.Sum(x => x.School),
                    g.Sum(x => x.DistanceTeaching));
            });

        foreach (var m in monthly)
            Months.Add(m);

        RecomputePrediction();
    }

    private void ToggleHideDayLocally(AbsenceDayRowViewModel row)
    {
        if (_repository.CurrentSession is null) return;
        var scope = _repository.CurrentSession.ScopeKey;

        if (row.HasLocalOverride)
        {
            _repository.AbsenceOverrides.RemoveDate(scope, row.RawDay.DateKey);
            RebuildFromRaw();
            return;
        }

        // Build full-day local hide override matching the raw day counts
        var allocs = new List<AbsenceOverrideAllocation>();
        int idx = 0;
        void AddAlloc(AbsenceCategory cat, int count)
        {
            for (int i = 0; i < count; i++)
                allocs.Add(new AbsenceOverrideAllocation($"local-{row.RawDay.DateKey}-{idx++}", null, string.Empty, cat));
        }
        AddAlloc(AbsenceCategory.Unsolved, row.RawDay.Unsolved);
        AddAlloc(AbsenceCategory.Ok, row.RawDay.Ok);
        AddAlloc(AbsenceCategory.Missed, row.RawDay.Missed);
        AddAlloc(AbsenceCategory.Late, row.RawDay.Late);
        AddAlloc(AbsenceCategory.Soon, row.RawDay.Soon);
        AddAlloc(AbsenceCategory.School, row.RawDay.School);
        AddAlloc(AbsenceCategory.DistanceTeaching, row.RawDay.DistanceTeaching);

        // Assign allocations to subjects that have available counts so subject stats stay consistent
        if (_rawResponse is { AbsencesPerSubject.Count: > 0 })
        {
            var available = _rawResponse.AbsencesPerSubject.Select(s => s.Clone()).ToList();
            for (int i = 0; i < allocs.Count; i++)
            {
                var a = allocs[i];
                var match = available.FirstOrDefault(s => a.Category.ContributesToBase() ? s.Base > 0 : s.Late + s.Soon + s.School + s.DistanceTeaching > 0);
                if (match is not null)
                {
                    if (a.Category.ContributesToBase()) match.Base--;
                    allocs[i] = a with { SubjectName = match.SubjectName };
                }
            }
        }

        var ov = new AbsenceDayOverride
        {
            Scope = scope,
            DateKey = row.RawDay.DateKey,
            BaselineDay = row.RawDay.Clone(),
            Allocations = allocs,
            HiddenAllocationIds = allocs.Select(a => a.Id).ToHashSet(StringComparer.Ordinal)
        };
        _repository.AbsenceOverrides.Upsert(scope, ov);
        RebuildFromRaw();
    }

    private async Task LoadPredictorDayLessonsAsync()
    {
        PredictorDayLessons.Clear();
        if (!_repository.IsSignedIn) return;
        try
        {
            var targetDate = DateOnly.FromDateTime(PredictorDate);
            var week = await _repository.GetTimetableAsync(TimetableKind.Actual, targetDate);
            var day = week.Days.FirstOrDefault(d => d.Date == targetDate);
            if (day is null) return;

            foreach (var lesson in day.Lessons.Where(l => !l.IsCanceled && !string.IsNullOrWhiteSpace(l.SubjectName)))
            {
                var candId = $"{targetDate:yyyy-MM-dd}-{lesson.Hour.Id}-{lesson.SubjectName}";
                var cand = new AbsenceLessonCandidate(
                    candId,
                    targetDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    lesson.Hour.Id,
                    lesson.Hour.Caption,
                    AbsenceAnalytics.NormalizeKey(lesson.SubjectName),
                    lesson.SubjectName,
                    $"{lesson.Hour.BeginTime}–{lesson.Hour.EndTime}");

                var item = new SelectableLessonForPrediction(cand, _selectedPredictionLessons.ContainsKey(candId));
                item.PropertyChanged += (_, e) =>
                {
                    if (e.PropertyName == nameof(SelectableLessonForPrediction.IsSelected))
                    {
                        if (item.IsSelected) _selectedPredictionLessons[candId] = cand;
                        else _selectedPredictionLessons.Remove(candId);
                        RecomputePrediction();
                    }
                };
                PredictorDayLessons.Add(item);
            }
        }
        catch { }
    }

    private void RecomputePrediction()
    {
        PredictionSubjectRows.Clear();
        if (_rawResponse is null || _selectedPredictionLessons.Count == 0)
        {
            PredictionSummary = null;
            return;
        }

        var summary = AbsenceAnalytics.Predict(_rawResponse, LatestSubjectSummaries, _selectedPredictionLessons.Values.ToList());
        PredictionSummary = summary;
        foreach (var s in summary.Subjects)
            PredictionSubjectRows.Add(s);
    }
}
