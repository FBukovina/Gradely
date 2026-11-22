using System.Collections.ObjectModel;
using Gradely.Core.Models;
using Gradely.Core.Support;

namespace Gradely.Windows.ViewModels;

public sealed record LessonChipItem(
    string PeriodCaption,
    string SubjectAbbrev,
    string SubjectName,
    bool IsCurrent,
    bool IsPast,
    bool IsCanceled,
    bool HasNonCancelChange,
    LessonChangeKind ChangeKind
);

public sealed record RecentMarkItem(
    string SubjectId,
    string SubjectName,
    string MarkDisplay,
    GradeBand Band,
    string Caption,
    string DateLabel,
    bool IsNew
);

public sealed record TodayPlannerPreviewItem(
    string DayNumber,
    string MonthShort,
    string Title,
    string Subtitle,
    bool IsAssessment,
    bool IsHomework
);

public sealed record TodayChangeItem(
    string PeriodAndTime,
    string SubjectName,
    string ChangeLabel,
    string? Description,
    LessonChangeKind ChangeKind
);

public sealed class TodayViewModel : ObservableObject
{
    private UserResponse? _user;
    private TimetableWeek? _week;
    private string _greeting = string.Empty;
    private string _overallAverageText = "–";
    private GradeBand _overallAverageBand = GradeBand.Neutral;
    private int _lessonsTodayCount;
    private int _newMarksCount;

    private bool _hasCurrentLesson;
    private string _currentPeriod = string.Empty;
    private string _currentStatusLabel = string.Empty;
    private string _currentSubject = string.Empty;
    private string _currentMeta = string.Empty;
    private double _currentProgress;

    private bool _hasNextLesson;
    private string _nextPeriod = string.Empty;
    private string _nextStatusLabel = string.Empty;
    private string _nextSubject = string.Empty;
    private string _nextMeta = string.Empty;

    private string? _scheduleEmptyMessage;
    private string? _todayLunchTitle;
    private string? _todayLunchPrice;
    private bool _showLunchSection;

    public TodayViewModel()
    {
        LessonStrip = [];
        Changes = [];
        RecentMarks = [];
        UpcomingPlanner = [];

        LocalizationService.Instance.PropertyChanged += (_, _) => RebuildClockDrivenText();
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public ObservableCollection<LessonChipItem> LessonStrip { get; }
    public ObservableCollection<TodayChangeItem> Changes { get; }
    public ObservableCollection<RecentMarkItem> RecentMarks { get; }
    public ObservableCollection<TodayPlannerPreviewItem> UpcomingPlanner { get; }

    public string Greeting { get => _greeting; set => SetProperty(ref _greeting, value); }
    public string OverallAverageText { get => _overallAverageText; set => SetProperty(ref _overallAverageText, value); }
    public GradeBand OverallAverageBand { get => _overallAverageBand; set => SetProperty(ref _overallAverageBand, value); }
    public int LessonsTodayCount { get => _lessonsTodayCount; set => SetProperty(ref _lessonsTodayCount, value); }
    public int NewMarksCount { get => _newMarksCount; set => SetProperty(ref _newMarksCount, value); }

    public bool HasCurrentLesson { get => _hasCurrentLesson; set => SetProperty(ref _hasCurrentLesson, value); }
    public string CurrentPeriod { get => _currentPeriod; set => SetProperty(ref _currentPeriod, value); }
    public string CurrentStatusLabel { get => _currentStatusLabel; set => SetProperty(ref _currentStatusLabel, value); }
    public string CurrentSubject { get => _currentSubject; set => SetProperty(ref _currentSubject, value); }
    public string CurrentMeta { get => _currentMeta; set => SetProperty(ref _currentMeta, value); }
    public double CurrentProgress { get => _currentProgress; set => SetProperty(ref _currentProgress, value); }

    public bool HasNextLesson { get => _hasNextLesson; set => SetProperty(ref _hasNextLesson, value); }
    public string NextPeriod { get => _nextPeriod; set => SetProperty(ref _nextPeriod, value); }
    public string NextStatusLabel { get => _nextStatusLabel; set => SetProperty(ref _nextStatusLabel, value); }
    public string NextSubject { get => _nextSubject; set => SetProperty(ref _nextSubject, value); }
    public string NextMeta { get => _nextMeta; set => SetProperty(ref _nextMeta, value); }

    public string? ScheduleEmptyMessage { get => _scheduleEmptyMessage; set => SetProperty(ref _scheduleEmptyMessage, value); }
    public string? TodayLunchTitle { get => _todayLunchTitle; set => SetProperty(ref _todayLunchTitle, value); }
    public string? TodayLunchPrice { get => _todayLunchPrice; set => SetProperty(ref _todayLunchPrice, value); }
    public bool ShowLunchSection { get => _showLunchSection; set => SetProperty(ref _showLunchSection, value); }

    public void UpdateSnapshot(
        UserResponse? user,
        MarksResponse? marks,
        TimetableWeek? currentWeek,
        IReadOnlyList<HomeworkItem> homeworks,
        IReadOnlyList<PlannerItem> plannerItems,
        IReadOnlyList<StravaCZDayMenu>? meals,
        bool showMealsTab)
    {
        _user = user;
        _week = currentWeek;

        // Marks & Overall Average
        RecentMarks.Clear();
        if (marks is not null)
        {
            var prepared = marks.Subjects.Select(GradeMath.Prepare).ToList();
            var overall = GradeMath.OverallAverage(prepared);
            OverallAverageText = GradeMath.FormatAverage(overall, L10n.ActiveCulture);
            OverallAverageBand = GradeMath.BandForAverage(overall);
            NewMarksCount = marks.Subjects.SelectMany(s => s.Marks).Count(m => m.IsNew);

            var recent = marks.Subjects
                .SelectMany(s => s.Marks.Select(m => (Subject: s, Mark: m)))
                .OrderByDescending(x => x.Mark.ParsedDate ?? DateTimeOffset.MinValue)
                .Take(4);

            foreach (var (subj, mark) in recent)
            {
                var dateLabel = mark.ParsedDate?.LocalDateTime.ToString("d. M.", L10n.ActiveCulture) ?? string.Empty;
                var caption = string.IsNullOrEmpty(mark.DisplayCaption) ? L10n["marks.untitled"] : mark.DisplayCaption;
                RecentMarks.Add(new RecentMarkItem(
                    subj.Id,
                    subj.TrimmedName,
                    mark.DisplayText,
                    GradeMath.BandForMark(mark),
                    caption,
                    dateLabel,
                    mark.IsNew));
            }
        }
        else
        {
            OverallAverageText = "–";
            OverallAverageBand = GradeBand.Neutral;
            NewMarksCount = 0;
        }

        // Planner + Open Homework
        UpcomingPlanner.Clear();
        var now = DateTime.Today;
        var merged = new List<(DateTime SortDate, TodayPlannerPreviewItem Item)>();

        foreach (var hw in homeworks.Where(h => h.IsOpen && (h.DueOn is null || h.DueOn.Value.LocalDateTime.Date >= now)))
        {
            var dt = hw.DueOn?.LocalDateTime ?? now;
            merged.Add((dt, new TodayPlannerPreviewItem(
                dt.Day.ToString(),
                dt.ToString("MMM", L10n.ActiveCulture).ToUpper(L10n.ActiveCulture),
                hw.Title,
                $"{L10n["planner.schoolHomework"]} · {hw.SubjectName}",
                IsAssessment: false,
                IsHomework: true)));
        }

        foreach (var pi in plannerItems.Where(p => !p.IsCompleted && (p.OrderingDate is null || p.OrderingDate.Value.Date >= now)))
        {
            var dt = pi.OrderingDate ?? now;
            var typeLbl = L10n[$"planner.type.{pi.Type}"];
            var sub = pi.Subject is not null ? $"{typeLbl} · {pi.Subject.Name}" : typeLbl;
            merged.Add((dt, new TodayPlannerPreviewItem(
                dt.Day.ToString(),
                dt.ToString("MMM", L10n.ActiveCulture).ToUpper(L10n.ActiveCulture),
                pi.Title,
                sub,
                IsAssessment: pi.IsAssessment,
                IsHomework: false)));
        }

        foreach (var entry in merged.OrderBy(x => x.SortDate).Take(4))
            UpcomingPlanner.Add(entry.Item);

        // Today's Lunch
        ShowLunchSection = showMealsTab && meals is { Count: > 0 };
        if (ShowLunchSection && meals is not null)
        {
            var todayKey = DateOnly.FromDateTime(DateTime.Today).ToString("yyyy-MM-dd");
            var todayMenu = meals.FirstOrDefault(m => m.DateKey == todayKey);
            var orderedMain = todayMenu?.Meals.FirstOrDefault(m => m.Type == StravaCZMealType.Main && m.IsOrdered);
            if (orderedMain is not null)
            {
                TodayLunchTitle = orderedMain.DisplayName;
                TodayLunchPrice = orderedMain.Price > 0 ? $"{orderedMain.Price:0.##} Kč" : null;
            }
            else
            {
                TodayLunchTitle = L10n["today.noMealOrdered"];
                TodayLunchPrice = null;
            }
        }

        RebuildClockDrivenText();
    }

    public void RebuildClockDrivenText()
    {
        var now = DateTime.Now;
        var firstName = ExtractFirstName(_user?.NameWithoutClass);
        string greetKey = now.Hour switch
        {
            < 12 => "today.greeting.morning",
            < 18 => "today.greeting.afternoon",
            _ => "today.greeting.evening"
        };
        Greeting = string.IsNullOrEmpty(firstName)
            ? L10n["nav.today"]
            : L10n.Format(greetKey, firstName);

        LessonStrip.Clear();
        Changes.Clear();
        HasCurrentLesson = false;
        HasNextLesson = false;
        ScheduleEmptyMessage = null;

        if (_week is null)
        {
            LessonsTodayCount = 0;
            ScheduleEmptyMessage = L10n["today.noLessons"];
            return;
        }

        var summary = TimetableMapper.BuildTodaySummary(_week, now);
        if (summary is null)
        {
            LessonsTodayCount = 0;
            ScheduleEmptyMessage = L10n["today.noLessons"];
            return;
        }

        LessonsTodayCount = summary.AllTimedLessons.Count(t => !t.Lesson.IsCanceled);

        foreach (var tl in summary.AllTimedLessons)
        {
            bool isCurr = summary.CurrentLesson is not null && tl.Lesson.Id == summary.CurrentLesson.Lesson.Id;
            bool isPast = tl.End <= now;
            LessonStrip.Add(new LessonChipItem(
                tl.Lesson.Hour.Caption,
                tl.Lesson.SubjectAbbrev,
                tl.Lesson.SubjectName,
                isCurr,
                isPast,
                tl.Lesson.IsCanceled,
                tl.Lesson.HasChange && !tl.Lesson.IsCanceled,
                tl.Lesson.ChangeKind));
        }

        if (summary.CurrentLesson is not null)
        {
            HasCurrentLesson = true;
            var cl = summary.CurrentLesson;
            CurrentPeriod = cl.Lesson.Hour.Caption;
            CurrentStatusLabel = L10n.Format("today.current", summary.MinutesRemainingInCurrent ?? 0);
            CurrentSubject = cl.Lesson.SubjectName;
            CurrentMeta = FormatLessonMeta(cl);
            CurrentProgress = summary.CurrentLessonProgress;
        }

        if (summary.NextLesson is not null)
        {
            HasNextLesson = true;
            var nl = summary.NextLesson;
            NextPeriod = nl.Lesson.Hour.Caption;
            int mins = summary.MinutesUntilNext ?? Math.Max(0, (int)Math.Ceiling((nl.Start - now).TotalMinutes));
            NextStatusLabel = mins <= 120
                ? L10n.Format("today.nextIn", mins)
                : L10n.Format("today.nextAt", nl.Lesson.Hour.BeginTime);
            NextSubject = nl.Lesson.SubjectName;
            NextMeta = FormatLessonMeta(nl);
        }

        if (!HasCurrentLesson && !HasNextLesson)
        {
            ScheduleEmptyMessage = summary.State == TodayLessonState.Empty
                ? L10n["today.noLessons"]
                : L10n["today.afterSchool"];
        }

        foreach (var ch in summary.ChangedLessons.Take(3))
        {
            Changes.Add(new TodayChangeItem(
                $"{ch.Lesson.Hour.Caption}. ({ch.Lesson.Hour.BeginTime}–{ch.Lesson.Hour.EndTime})",
                ch.Lesson.SubjectName,
                FormatChangeLabel(ch.Lesson.ChangeKind),
                ch.Lesson.Change?.Description,
                ch.Lesson.ChangeKind));
        }
    }

    private static string FormatLessonMeta(TimedLesson tl)
    {
        var parts = new List<string> { $"{tl.Lesson.Hour.BeginTime}–{tl.Lesson.Hour.EndTime}" };
        if (!string.IsNullOrWhiteSpace(tl.Lesson.RoomName)) parts.Add(tl.Lesson.RoomName);
        if (!string.IsNullOrWhiteSpace(tl.Lesson.TeacherName)) parts.Add(tl.Lesson.TeacherName);
        return string.Join(" · ", parts);
    }

    private string FormatChangeLabel(LessonChangeKind kind) => kind switch
    {
        LessonChangeKind.Canceled => L10n["timetable.change.canceled"],
        LessonChangeKind.RoomChanged => L10n["timetable.change.roomChanged"],
        LessonChangeKind.Added => L10n["timetable.change.added"],
        _ => L10n["timetable.change.substitution"]
    };

    private static string ExtractFirstName(string? fullName)
    {
        if (string.IsNullOrWhiteSpace(fullName)) return string.Empty;
        var parts = fullName.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length > 0 ? parts[0] : string.Empty;
    }
}
