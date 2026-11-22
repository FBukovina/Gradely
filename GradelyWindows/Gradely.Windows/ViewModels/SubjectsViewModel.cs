using System.Collections.ObjectModel;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public enum SubjectsSortMode
{
    Focus,
    Average
}

public sealed class SubjectListItemViewModel : ObservableObject
{
    public SubjectMarks Subject { get; }
    public PreparedGradeCalculation Prepared { get; }
    public string Id => Subject.Id;
    public string Name => Subject.TrimmedName;
    public string Abbrev => Subject.TrimmedAbbrev;
    public string AverageText => GradeMath.FormatAverage(Prepared.DisplayAverage, LocalizationService.Instance.ActiveCulture);
    public GradeBand Band => GradeMath.BandForAverage(Prepared.DisplayAverage);
    public int MarksCount => Subject.Marks.Count;
    public string MarksCountLabel => LocalizationService.Instance.Format("marks.marksCount", MarksCount);
    public string? LatestMarkText { get; }
    public GradeBand LatestMarkBand { get; }
    public string? AbsencePercentageLabel { get; }
    public double FocusScore { get; }

    public SubjectListItemViewModel(SubjectMarks subject, PreparedGradeCalculation prepared, AbsenceSubjectSummary? absence)
    {
        Subject = subject;
        Prepared = prepared;
        FocusScore = GradeMath.PriorityFocusScore(prepared);

        var latest = subject.Marks
            .OrderByDescending(m => m.ParsedDate ?? DateTimeOffset.MinValue)
            .FirstOrDefault();
        LatestMarkText = latest?.DisplayText;
        LatestMarkBand = latest is not null ? GradeMath.BandForMark(latest) : GradeBand.Neutral;

        if (absence is not null && absence.LessonsCount > 0)
            AbsencePercentageLabel = LocalizationService.Instance.Format("marks.absencePct", absence.AbsencePercentage);
    }
}

public sealed record MarkRowViewModel(
    string Id,
    string Caption,
    string? Theme,
    string MarkDisplay,
    GradeBand Band,
    string MetadataLine,
    string? WeightBadge,
    bool IsPoints,
    bool IsNew
);

public sealed class SubjectsViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private MarksResponse? _marksResponse;
    private List<AbsenceSubjectSummary> _absenceSummaries = [];
    private List<ReportCardTerm> _reportCards = [];

    private SubjectsSortMode _sortMode = SubjectsSortMode.Focus;
    private SubjectListItemViewModel? _selectedSubject;
    private string _overallAverageText = "–";
    private GradeBand _overallAverageBand = GradeBand.Neutral;
    private string _summaryLine = string.Empty;
    private bool _showReportCardBanner;
    private string _reportCardSubtitle = string.Empty;

    // Selected Subject Detail
    private string _detailAverageCaption = string.Empty;
    private string _detailAverageText = "–";
    private GradeBand _detailAverageBand = GradeBand.Neutral;
    private string _detailSubtitle = string.Empty;
    private bool _detailIsPointsOnly;
    private IReadOnlyList<AverageTimelineEntry> _timelineEntries = [];

    // What-If Simulator
    private string _whatIfMarkText = string.Empty;
    private int _whatIfWeight = 3;
    private string? _whatIfResultAverage;
    private string? _whatIfDeltaText;
    private bool _whatIfDeltaIsBetter;
    private bool _whatIfDeltaIsWorse;
    private string? _whatIfSourceNote;

    public SubjectsViewModel(SchoolRepository repository)
    {
        _repository = repository;
        Subjects = [];
        DetailMarks = [];

        IncrementWeightCommand = new RelayCommand(() => { if (WhatIfWeight < 10) WhatIfWeight++; });
        DecrementWeightCommand = new RelayCommand(() => { if (WhatIfWeight > 1) WhatIfWeight--; });
        ClearWhatIfCommand = new RelayCommand(() => { WhatIfMarkText = string.Empty; });

        LocalizationService.Instance.PropertyChanged += (_, _) => RebuildList(preserveSelection: true);
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public ObservableCollection<SubjectListItemViewModel> Subjects { get; }
    public ObservableCollection<MarkRowViewModel> DetailMarks { get; }

    public SubjectsSortMode SortMode
    {
        get => _sortMode;
        set
        {
            if (SetProperty(ref _sortMode, value))
            {
                OnPropertyChanged(nameof(IsSortFocus));
                OnPropertyChanged(nameof(IsSortAverage));
                RebuildList(preserveSelection: true);
            }
        }
    }

    public bool IsSortFocus
    {
        get => SortMode == SubjectsSortMode.Focus;
        set { if (value) SortMode = SubjectsSortMode.Focus; }
    }

    public bool IsSortAverage
    {
        get => SortMode == SubjectsSortMode.Average;
        set { if (value) SortMode = SubjectsSortMode.Average; }
    }

    public SubjectListItemViewModel? SelectedSubject
    {
        get => _selectedSubject;
        set
        {
            if (SetProperty(ref _selectedSubject, value))
                RebuildDetail();
        }
    }

    public string OverallAverageText { get => _overallAverageText; set => SetProperty(ref _overallAverageText, value); }
    public GradeBand OverallAverageBand { get => _overallAverageBand; set => SetProperty(ref _overallAverageBand, value); }
    public string SummaryLine { get => _summaryLine; set => SetProperty(ref _summaryLine, value); }
    public bool ShowReportCardBanner { get => _showReportCardBanner; set => SetProperty(ref _showReportCardBanner, value); }
    public string ReportCardSubtitle { get => _reportCardSubtitle; set => SetProperty(ref _reportCardSubtitle, value); }

    public string DetailAverageCaption { get => _detailAverageCaption; set => SetProperty(ref _detailAverageCaption, value); }
    public string DetailAverageText { get => _detailAverageText; set => SetProperty(ref _detailAverageText, value); }
    public GradeBand DetailAverageBand { get => _detailAverageBand; set => SetProperty(ref _detailAverageBand, value); }
    public string DetailSubtitle { get => _detailSubtitle; set => SetProperty(ref _detailSubtitle, value); }
    public bool DetailIsPointsOnly { get => _detailIsPointsOnly; set => SetProperty(ref _detailIsPointsOnly, value); }

    public IReadOnlyList<AverageTimelineEntry> TimelineEntries
    {
        get => _timelineEntries;
        set => SetProperty(ref _timelineEntries, value);
    }

    public string WhatIfMarkText
    {
        get => _whatIfMarkText;
        set
        {
            if (SetProperty(ref _whatIfMarkText, value))
                _ = RecalculateWhatIfAsync();
        }
    }

    public int WhatIfWeight
    {
        get => _whatIfWeight;
        set
        {
            var clamped = Math.Clamp(value, 1, 10);
            if (SetProperty(ref _whatIfWeight, clamped))
                _ = RecalculateWhatIfAsync();
        }
    }

    public string? WhatIfResultAverage { get => _whatIfResultAverage; set => SetProperty(ref _whatIfResultAverage, value); }
    public string? WhatIfDeltaText { get => _whatIfDeltaText; set => SetProperty(ref _whatIfDeltaText, value); }
    public bool WhatIfDeltaIsBetter { get => _whatIfDeltaIsBetter; set => SetProperty(ref _whatIfDeltaIsBetter, value); }
    public bool WhatIfDeltaIsWorse { get => _whatIfDeltaIsWorse; set => SetProperty(ref _whatIfDeltaIsWorse, value); }
    public string? WhatIfSourceNote { get => _whatIfSourceNote; set => SetProperty(ref _whatIfSourceNote, value); }

    public RelayCommand IncrementWeightCommand { get; }
    public RelayCommand DecrementWeightCommand { get; }
    public RelayCommand ClearWhatIfCommand { get; }

    public void UpdateData(MarksResponse? marks, List<AbsenceSubjectSummary> absenceSummaries, List<ReportCardTerm> reportCards)
    {
        _marksResponse = marks;
        _absenceSummaries = absenceSummaries;
        _reportCards = reportCards;
        RebuildList(preserveSelection: true);
    }

    public void SelectSubjectById(string subjectId)
    {
        var match = Subjects.FirstOrDefault(s => string.Equals(s.Id, subjectId, StringComparison.Ordinal));
        if (match is not null) SelectedSubject = match;
    }

    private void RebuildList(bool preserveSelection)
    {
        var previousId = preserveSelection ? SelectedSubject?.Id : null;
        Subjects.Clear();

        if (_marksResponse is null)
        {
            OverallAverageText = "–";
            OverallAverageBand = GradeBand.Neutral;
            SummaryLine = string.Empty;
            ShowReportCardBanner = false;
            SelectedSubject = null;
            return;
        }

        var items = new List<SubjectListItemViewModel>();
        var preparedMap = new Dictionary<string, PreparedGradeCalculation>(StringComparer.Ordinal);

        foreach (var subj in _marksResponse.Subjects)
        {
            var prep = GradeMath.Prepare(subj);
            preparedMap[subj.Id] = prep;
            var abs = _absenceSummaries.FirstOrDefault(a =>
                string.Equals(AbsenceAnalytics.NormalizeKey(a.SubjectName), AbsenceAnalytics.NormalizeKey(subj.TrimmedName), StringComparison.Ordinal));
            items.Add(new SubjectListItemViewModel(subj, prep, abs));
        }

        var sorted = SortMode == SubjectsSortMode.Focus
            ? items.OrderByDescending(i => i.FocusScore).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList()
            : items.OrderBy(i => i.Prepared.DisplayAverage ?? double.MaxValue).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

        foreach (var item in sorted)
            Subjects.Add(item);

        var overall = GradeMath.OverallAverage(preparedMap.Values);
        OverallAverageText = GradeMath.FormatAverage(overall, L10n.ActiveCulture);
        OverallAverageBand = GradeMath.BandForAverage(overall);
        int totalMarks = _marksResponse.Subjects.Sum(s => s.Marks.Count);
        SummaryLine = L10n.Format("marks.summary", _marksResponse.Subjects.Count, totalMarks);

        // Report Card preview
        ShowReportCardBanner = _repository.CurrentSession?.Provider.SupportsReportCard() == true && _marksResponse.Subjects.Count > 0;
        if (ShowReportCardBanner)
        {
            var currentPeriod = ReportCardPeriod.Containing(DateTime.Today);
            var writtenTerm = _reportCards.FirstOrDefault(t => t.Matches(currentPeriod));
            var estimates = ReportCardEstimate.BuildEstimates(_marksResponse.Subjects, preparedMap, writtenTerm);
            var estAvg = ReportCardEstimate.OverallAverage(estimates);
            int borderlineCount = estimates.Count(e => e.Borderline is not null);
            var avgStr = GradeMath.FormatAverage(estAvg, L10n.ActiveCulture);
            ReportCardSubtitle = borderlineCount > 0
                ? L10n.Format("marks.reportCard.subtitle", avgStr, borderlineCount)
                : L10n.Format("marks.reportCard.subtitleClean", avgStr);
        }

        SelectedSubject = (previousId is not null ? Subjects.FirstOrDefault(s => s.Id == previousId) : null)
                          ?? Subjects.FirstOrDefault();
    }

    private void RebuildDetail()
    {
        DetailMarks.Clear();
        WhatIfMarkText = string.Empty;
        ClearWhatIfResults();

        if (SelectedSubject is null)
        {
            TimelineEntries = [];
            return;
        }

        var subj = SelectedSubject.Subject;
        var prep = SelectedSubject.Prepared;

        DetailAverageCaption = prep.OfficialAverage.HasValue ? L10n["marks.schoolAverage"] : L10n["marks.calculatedAverage"];
        DetailAverageText = SelectedSubject.AverageText;
        DetailAverageBand = SelectedSubject.Band;
        DetailIsPointsOnly = subj.PointsOnly;

        var subtitleParts = new List<string> { L10n.Format("marks.marksCount", subj.Marks.Count) };
        if (!string.IsNullOrEmpty(SelectedSubject.AbsencePercentageLabel))
            subtitleParts.Add(SelectedSubject.AbsencePercentageLabel);
        DetailSubtitle = string.Join(" · ", subtitleParts);

        TimelineEntries = GradeMath.BuildTimeline(prep);

        foreach (var mark in subj.Marks.OrderByDescending(m => m.ParsedDate ?? DateTimeOffset.MinValue))
        {
            var caption = string.IsNullOrEmpty(mark.DisplayCaption) ? L10n["marks.untitled"] : mark.DisplayCaption;
            var metaParts = new List<string>();
            if (mark.ParsedDate is DateTimeOffset dt)
                metaParts.Add(dt.LocalDateTime.ToString("d. M. yyyy", L10n.ActiveCulture));
            if (!string.IsNullOrWhiteSpace(mark.TypeNote))
                metaParts.Add(mark.TypeNote.Trim());
            else if (!string.IsNullOrWhiteSpace(mark.Type) && mark.Type != "grade")
                metaParts.Add(mark.Type.Trim());

            string? weightBadge = null;
            if (!mark.IsPoints)
            {
                var rw = prep.ResolvedWeightFor(mark.EffectiveId);
                if (rw is not null && Math.Abs(rw.Value - 1.0) > 1e-6)
                {
                    var formatted = GradeMath.FormatWeight(rw.Value);
                    weightBadge = rw.Source == WeightSource.Inferred
                        ? L10n.Format("marks.inferredWeight", formatted)
                        : L10n.Format("marks.weight", formatted);
                }
            }

            DetailMarks.Add(new MarkRowViewModel(
                mark.EffectiveId,
                caption,
                mark.ShouldShowTheme ? mark.Theme?.Trim() : null,
                mark.DisplayText,
                GradeMath.BandForMark(mark),
                string.Join(" · ", metaParts),
                weightBadge,
                mark.IsPoints,
                mark.IsNew));
        }
    }

    private async Task RecalculateWhatIfAsync()
    {
        if (SelectedSubject is null || DetailIsPointsOnly || string.IsNullOrWhiteSpace(WhatIfMarkText))
        {
            ClearWhatIfResults();
            return;
        }

        var subjectSnapshot = SelectedSubject;
        var inputText = WhatIfMarkText.Trim();
        var weight = WhatIfWeight;

        var result = await _repository.PredictWhatIfAsync(subjectSnapshot.Subject, subjectSnapshot.Prepared, inputText, weight);
        // Ensure user hasn't switched subject/input while remote prediction was in flight
        if (SelectedSubject != subjectSnapshot || !string.Equals(WhatIfMarkText.Trim(), inputText, StringComparison.Ordinal))
            return;

        if (result is null)
        {
            ClearWhatIfResults();
            return;
        }

        WhatIfResultAverage = "→ " + GradeMath.FormatAverage(result.EstimatedAverage, L10n.ActiveCulture);
        WhatIfSourceNote = result.IsRemotePrediction ? L10n["marks.whatIf.remote"] : L10n["marks.whatIf.local"];

        if (result.Difference is double diff)
        {
            if (Math.Abs(diff) < 0.005)
            {
                WhatIfDeltaText = L10n["marks.whatIf.unchanged"];
                WhatIfDeltaIsBetter = false;
                WhatIfDeltaIsWorse = false;
            }
            else if (diff < 0)
            {
                WhatIfDeltaText = L10n.Format("marks.whatIf.better", Math.Abs(diff));
                WhatIfDeltaIsBetter = true;
                WhatIfDeltaIsWorse = false;
            }
            else
            {
                WhatIfDeltaText = L10n.Format("marks.whatIf.worse", diff);
                WhatIfDeltaIsBetter = false;
                WhatIfDeltaIsWorse = true;
            }
        }
        else
        {
            WhatIfDeltaText = null;
            WhatIfDeltaIsBetter = false;
            WhatIfDeltaIsWorse = false;
        }
    }

    private void ClearWhatIfResults()
    {
        WhatIfResultAverage = null;
        WhatIfDeltaText = null;
        WhatIfDeltaIsBetter = false;
        WhatIfDeltaIsWorse = false;
        WhatIfSourceNote = null;
    }
}
