using System.Collections.ObjectModel;
using System.IO;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Stores;
using Gradely.Core.Support;
using Microsoft.Win32;

namespace Gradely.Windows.ViewModels;

public sealed class KomensViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private readonly Action<int> _onUnreadChanged;
    private KomensSnapshot _snapshot = new();

    private KomensBox _selectedBox = KomensBox.Received;
    private KomensMessage? _selectedMessage;
    private bool _isLoading;
    private string? _statusMessage;

    public KomensViewModel(SchoolRepository repository, Action<int> onUnreadChanged)
    {
        _repository = repository;
        _onUnreadChanged = onUnreadChanged;
        Messages = [];

        RefreshCommand = new AsyncRelayCommand(RefreshAsync);
        DownloadAttachmentCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is SchoolAttachment att) await DownloadAttachmentAsync(att);
        });
    }

    public LocalizationService L10n => LocalizationService.Instance;
    public ObservableCollection<KomensMessage> Messages { get; }

    public KomensBox SelectedBox
    {
        get => _selectedBox;
        set
        {
            if (SetProperty(ref _selectedBox, value))
            {
                OnPropertyChanged(nameof(IsReceived));
                OnPropertyChanged(nameof(IsNoticeboard));
                RebuildMessages();
            }
        }
    }

    public bool IsReceived { get => SelectedBox == KomensBox.Received; set { if (value) SelectedBox = KomensBox.Received; } }
    public bool IsNoticeboard { get => SelectedBox == KomensBox.Noticeboard; set { if (value) SelectedBox = KomensBox.Noticeboard; } }

    public KomensMessage? SelectedMessage
    {
        get => _selectedMessage;
        set
        {
            if (SetProperty(ref _selectedMessage, value))
            {
                OnPropertyChanged(nameof(HasSelectedMessage));
                OnPropertyChanged(nameof(SelectedMessageMeta));
                if (value is { IsRead: false })
                    _ = MarkSelectedAsReadAsync(value);
            }
        }
    }

    public bool HasSelectedMessage => SelectedMessage is not null;
    public string SelectedMessageMeta
    {
        get
        {
            if (SelectedMessage is null) return string.Empty;
            var parts = new List<string>();
            if (!string.IsNullOrWhiteSpace(SelectedMessage.SenderName)) parts.Add(SelectedMessage.SenderName);
            if (SelectedMessage.SentAt is DateTimeOffset dt)
                parts.Add(dt.LocalDateTime.ToString("ddd d. M. yyyy HH:mm", L10n.ActiveCulture));
            return string.Join(" · ", parts);
        }
    }

    public bool IsLoading { get => _isLoading; set => SetProperty(ref _isLoading, value); }
    public string? StatusMessage { get => _statusMessage; set => SetProperty(ref _statusMessage, value); }

    public AsyncRelayCommand RefreshCommand { get; }
    public AsyncRelayCommand DownloadAttachmentCommand { get; }

    public void LoadSnapshot(KomensSnapshot snapshot)
    {
        _snapshot = snapshot;
        RebuildMessages();
        NotifyUnread();
    }

    public async Task RefreshAsync()
    {
        IsLoading = true;
        StatusMessage = null;
        try
        {
            _snapshot = await _repository.GetKomensAsync();
            RebuildMessages();
            NotifyUnread();
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void RebuildMessages()
    {
        var prevId = SelectedMessage?.Id;
        Messages.Clear();
        var raw = SelectedBox == KomensBox.Received ? _snapshot.Received : _snapshot.Noticeboard;
        var mapped = KomensMessage.SortNewestFirst(raw.Select(dto => KomensMessage.FromDto(dto, SelectedBox)));
        foreach (var m in mapped) Messages.Add(m);

        SelectedMessage = (prevId is not null ? Messages.FirstOrDefault(m => m.Id == prevId) : null)
                          ?? Messages.FirstOrDefault();
    }

    private async Task MarkSelectedAsReadAsync(KomensMessage message)
    {
        message.IsRead = true;
        _snapshot.MarkRead(message.MessageId);
        NotifyUnread();
        try
        {
            await _repository.MarkKomensReadAsync(message.MessageId);
        }
        catch { }
    }

    private async Task DownloadAttachmentAsync(SchoolAttachment attachment)
    {
        var dialog = new SaveFileDialog { FileName = attachment.Name };
        if (dialog.ShowDialog() != true) return;

        StatusMessage = L10n["common.loading"];
        try
        {
            var bytes = await _repository.DownloadAttachmentAsync(attachment.Id, attachment.Name);
            await File.WriteAllBytesAsync(dialog.FileName, bytes);
            StatusMessage = L10n.Format("komens.savedAttachment", Path.GetFileName(dialog.FileName));
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
    }

    private void NotifyUnread()
    {
        int unread = _snapshot.Received.Count(m => !m.Read);
        _onUnreadChanged(unread);
    }
}

public sealed class UnifiedPlannerEntry : ObservableObject
{
    public bool IsSchoolHomework { get; init; }
    public HomeworkItem? Homework { get; init; }
    public PlannerItem? PersonalItem { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Subtitle { get; init; } = string.Empty;
    public string? Notes { get; init; }
    public string DateGroupLabel { get; init; } = string.Empty;
    public bool IsCompleted { get; set; }
    public bool IsAssessment { get; init; }
    public IReadOnlyList<SchoolAttachment> Attachments { get; init; } = [];
}

public sealed class PlannerViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private readonly Action _onChanged;
    private List<HomeworkItem> _homeworks = [];
    private List<PlannerItem> _personalItems = [];
    private List<SubjectMarks> _subjects = [];

    private bool _showCompleted;
    private bool _isEditorOpen;
    private Guid? _editingId;
    private string _editorTitle = string.Empty;
    private string _editorNotes = string.Empty;
    private PlannerItemType _editorType = PlannerItemType.Homework;
    private string? _editorSubjectId;
    private DateTime? _editorDueDate = DateTime.Today.AddDays(1);
    private PlannerLessonReference? _editorLessonRef;

    public PlannerViewModel(SchoolRepository repository, Action onChanged)
    {
        _repository = repository;
        _onChanged = onChanged;
        Entries = [];
        AvailableSubjects = [];

        ToggleDoneCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is UnifiedPlannerEntry entry) await ToggleEntryDoneAsync(entry);
        });
        NewItemCommand = new RelayCommand(() => OpenEditor(null));
        EditItemCommand = new RelayCommand(obj =>
        {
            if (obj is UnifiedPlannerEntry { PersonalItem: not null } e) OpenEditor(e.PersonalItem);
        });
        DeleteItemCommand = new RelayCommand(obj =>
        {
            if (obj is UnifiedPlannerEntry { PersonalItem: not null } e) DeletePersonalItem(e.PersonalItem.Id);
        });
        SaveEditorCommand = new RelayCommand(SaveEditor, () => !string.IsNullOrWhiteSpace(EditorTitle));
        CancelEditorCommand = new RelayCommand(() => IsEditorOpen = false);
        DownloadAttachmentCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is SchoolAttachment att) await DownloadAttachmentAsync(att);
        });
    }

    public LocalizationService L10n => LocalizationService.Instance;
    public ObservableCollection<UnifiedPlannerEntry> Entries { get; }
    public ObservableCollection<SubjectMarks> AvailableSubjects { get; }
    public Array PlannerTypes => Enum.GetValues(typeof(PlannerItemType));

    public bool ShowCompleted
    {
        get => _showCompleted;
        set
        {
            if (SetProperty(ref _showCompleted, value))
            {
                OnPropertyChanged(nameof(IsUpcomingTab));
                OnPropertyChanged(nameof(IsCompletedTab));
                RebuildEntries();
            }
        }
    }

    public bool IsUpcomingTab { get => !ShowCompleted; set { if (value) ShowCompleted = false; } }
    public bool IsCompletedTab { get => ShowCompleted; set { if (value) ShowCompleted = true; } }

    public bool IsEditorOpen { get => _isEditorOpen; set => SetProperty(ref _isEditorOpen, value); }
    public string EditorHeader => _editingId.HasValue ? L10n["planner.editItem"] : L10n["planner.newItem"];

    public string EditorTitle
    {
        get => _editorTitle;
        set { if (SetProperty(ref _editorTitle, value)) SaveEditorCommand.RaiseCanExecuteChanged(); }
    }
    public string EditorNotes { get => _editorNotes; set => SetProperty(ref _editorNotes, value); }
    public PlannerItemType EditorType { get => _editorType; set => SetProperty(ref _editorType, value); }
    public string? EditorSubjectId { get => _editorSubjectId; set => SetProperty(ref _editorSubjectId, value); }
    public DateTime? EditorDueDate { get => _editorDueDate; set => SetProperty(ref _editorDueDate, value); }

    public AsyncRelayCommand ToggleDoneCommand { get; }
    public RelayCommand NewItemCommand { get; }
    public RelayCommand EditItemCommand { get; }
    public RelayCommand DeleteItemCommand { get; }
    public RelayCommand SaveEditorCommand { get; }
    public RelayCommand CancelEditorCommand { get; }
    public AsyncRelayCommand DownloadAttachmentCommand { get; }

    public void UpdateData(List<HomeworkItem> homeworks, List<PlannerItem> personalItems, List<SubjectMarks> subjects)
    {
        _homeworks = homeworks;
        _personalItems = personalItems;
        _subjects = subjects;
        AvailableSubjects.Clear();
        foreach (var s in subjects) AvailableSubjects.Add(s);
        RebuildEntries();
    }

    public void OpenEditorForLesson(TimetableLesson lesson, TimetableDay day)
    {
        var scope = _repository.CurrentSession?.ScopeKey ?? string.Empty;
        _editingId = null;
        _editorLessonRef = new PlannerLessonReference(
            scope,
            lesson.Id,
            day.Date?.ToString("yyyy-MM-dd") ?? day.Id,
            lesson.Hour.Id,
            lesson.SubjectId,
            lesson.GroupIds,
            null, null,
            lesson.Hour.Caption,
            lesson.TeacherName,
            lesson.RoomName);
        EditorTitle = string.Empty;
        EditorNotes = string.Empty;
        EditorType = PlannerItemType.Homework;
        EditorSubjectId = lesson.SubjectId;
        EditorDueDate = day.Date?.ToDateTime(TimeOnly.MinValue) ?? DateTime.Today.AddDays(1);
        OnPropertyChanged(nameof(EditorHeader));
        IsEditorOpen = true;
    }

    public void OpenEditor(PlannerItem? existing)
    {
        _editingId = existing?.Id;
        _editorLessonRef = existing?.Lesson;
        EditorTitle = existing?.Title ?? string.Empty;
        EditorNotes = existing?.Notes ?? string.Empty;
        EditorType = existing?.Type ?? PlannerItemType.Homework;
        EditorSubjectId = existing?.Subject?.Id;
        EditorDueDate = existing?.DueDate ?? DateTime.Today.AddDays(1);
        OnPropertyChanged(nameof(EditorHeader));
        IsEditorOpen = true;
    }

    private void SaveEditor()
    {
        if (_repository.CurrentSession is null || string.IsNullOrWhiteSpace(EditorTitle)) return;
        var scope = _repository.CurrentSession.ScopeKey;
        var subj = _subjects.FirstOrDefault(s => s.Id == EditorSubjectId);

        var item = new PlannerItem
        {
            Id = _editingId ?? Guid.NewGuid(),
            Scope = scope,
            Title = EditorTitle.Trim(),
            Notes = string.IsNullOrWhiteSpace(EditorNotes) ? null : EditorNotes.Trim(),
            Type = EditorType,
            Subject = subj is not null ? new PlannerSubjectReference(scope, subj.Id, subj.TrimmedName, subj.TrimmedAbbrev) : null,
            Lesson = _editorLessonRef,
            DueDate = EditorDueDate,
            IsCompleted = false
        };

        _repository.Planner.Upsert(scope, item);
        _personalItems = _repository.Planner.Load(scope);
        IsEditorOpen = false;
        RebuildEntries();
        _onChanged();
    }

    private void DeletePersonalItem(Guid id)
    {
        if (_repository.CurrentSession is null) return;
        var scope = _repository.CurrentSession.ScopeKey;
        _repository.Planner.Delete(scope, id);
        _personalItems = _repository.Planner.Load(scope);
        RebuildEntries();
        _onChanged();
    }

    private async Task ToggleEntryDoneAsync(UnifiedPlannerEntry entry)
    {
        if (entry.IsSchoolHomework && entry.Homework is not null)
        {
            bool target = !entry.Homework.IsDone;
            entry.Homework.IsDone = target;
            RebuildEntries();
            try
            {
                await _repository.SetHomeworkDoneAsync(entry.Homework.Id, target);
                _onChanged();
            }
            catch
            {
                entry.Homework.IsDone = !target;
                RebuildEntries();
            }
        }
        else if (entry.PersonalItem is not null && _repository.CurrentSession is not null)
        {
            entry.PersonalItem.IsCompleted = !entry.PersonalItem.IsCompleted;
            _repository.Planner.Upsert(_repository.CurrentSession.ScopeKey, entry.PersonalItem);
            _personalItems = _repository.Planner.Load(_repository.CurrentSession.ScopeKey);
            RebuildEntries();
            _onChanged();
        }
    }

    private async Task DownloadAttachmentAsync(SchoolAttachment att)
    {
        var dlg = new SaveFileDialog { FileName = att.Name };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var bytes = await _repository.DownloadAttachmentAsync(att.Id, att.Name);
            await File.WriteAllBytesAsync(dlg.FileName, bytes);
        }
        catch { }
    }

    private void RebuildEntries()
    {
        Entries.Clear();
        var merged = new List<(DateTime SortDate, UnifiedPlannerEntry Entry)>();

        foreach (var hw in _homeworks.Where(h => ShowCompleted ? !h.IsOpen : h.IsOpen))
        {
            var dt = hw.DueOn?.LocalDateTime ?? DateTime.MaxValue;
            var meta = new List<string> { L10n["planner.schoolHomework"] };
            if (!string.IsNullOrWhiteSpace(hw.SubjectName)) meta.Add(hw.SubjectName);
            if (hw.DueOn.HasValue) meta.Add(hw.DueOn.Value.LocalDateTime.ToString("ddd d. M.", L10n.ActiveCulture));

            merged.Add((dt, new UnifiedPlannerEntry
            {
                IsSchoolHomework = true,
                Homework = hw,
                Title = hw.Title,
                Subtitle = string.Join(" · ", meta),
                Notes = hw.Notice ?? (hw.Content != hw.Title ? hw.Content : null),
                DateGroupLabel = FormatDateGroup(hw.DueOn?.LocalDateTime),
                IsCompleted = !hw.IsOpen,
                Attachments = hw.Attachments
            }));
        }

        foreach (var pi in _personalItems.Where(p => p.IsCompleted == ShowCompleted))
        {
            var dt = pi.OrderingDate ?? DateTime.MaxValue;
            var meta = new List<string> { L10n[$"planner.type.{pi.Type}"] };
            if (pi.Subject is not null) meta.Add(pi.Subject.Name);
            if (pi.DueDate.HasValue) meta.Add(pi.DueDate.Value.ToString("ddd d. M.", L10n.ActiveCulture));

            merged.Add((dt, new UnifiedPlannerEntry
            {
                IsSchoolHomework = false,
                PersonalItem = pi,
                Title = pi.Title,
                Subtitle = string.Join(" · ", meta),
                Notes = pi.Notes,
                DateGroupLabel = FormatDateGroup(pi.OrderingDate),
                IsCompleted = pi.IsCompleted,
                IsAssessment = pi.IsAssessment
            }));
        }

        foreach (var item in merged.OrderBy(x => x.SortDate))
            Entries.Add(item.Entry);
    }

    private string FormatDateGroup(DateTime? dt)
    {
        if (dt is null) return L10n["common.undated"];
        var today = DateTime.Today;
        if (dt.Value.Date == today) return L10n["common.today"];
        if (dt.Value.Date == today.AddDays(1)) return L10n["common.tomorrow"];
        return dt.Value.ToString("dddd d. M.", L10n.ActiveCulture);
    }
}

public sealed record ReportCardEstimateRow(
    string SubjectName,
    string Subtitle,
    string? BorderlineWarning,
    string DisplayMark,
    GradeBand Band
);

public sealed class ReportCardViewModel : ObservableObject
{
    private string _currentTermTitle = string.Empty;
    private string _estimatedAverageText = "–";
    private GradeBand _estimatedAverageBand = GradeBand.Neutral;
    private ReportCardTerm? _selectedPastTerm;

    public ReportCardViewModel()
    {
        CurrentEstimates = [];
        PastTerms = [];
    }

    public LocalizationService L10n => LocalizationService.Instance;
    public ObservableCollection<ReportCardEstimateRow> CurrentEstimates { get; }
    public ObservableCollection<ReportCardTerm> PastTerms { get; }

    public string CurrentTermTitle { get => _currentTermTitle; set => SetProperty(ref _currentTermTitle, value); }
    public string EstimatedAverageText { get => _estimatedAverageText; set => SetProperty(ref _estimatedAverageText, value); }
    public GradeBand EstimatedAverageBand { get => _estimatedAverageBand; set => SetProperty(ref _estimatedAverageBand, value); }

    public ReportCardTerm? SelectedPastTerm
    {
        get => _selectedPastTerm;
        set
        {
            if (SetProperty(ref _selectedPastTerm, value))
            {
                OnPropertyChanged(nameof(HasSelectedPastTerm));
                OnPropertyChanged(nameof(SelectedPastTermFooter));
            }
        }
    }

    public bool HasSelectedPastTerm => SelectedPastTerm is not null;
    public string SelectedPastTermFooter => SelectedPastTerm is null
        ? string.Empty
        : L10n.Format("reportCard.absentFooter", SelectedPastTerm.AbsentHours ?? 0, SelectedPastTerm.UnexcusedHours ?? 0);

    public void UpdateData(MarksResponse? marks, List<ReportCardTerm> terms)
    {
        CurrentEstimates.Clear();
        PastTerms.Clear();

        var period = ReportCardPeriod.Containing(DateTime.Today);
        CurrentTermTitle = L10n.Format("reportCard.termTitle", period.Semester, period.SchoolYear);

        var writtenCurrent = terms.FirstOrDefault(t => t.Matches(period));
        if (marks is not null)
        {
            var prepared = marks.Subjects.ToDictionary(s => s.Id, GradeMath.Prepare, StringComparer.Ordinal);
            var estimates = ReportCardEstimate.BuildEstimates(marks.Subjects, prepared, writtenCurrent);
            var overall = ReportCardEstimate.OverallAverage(estimates);
            EstimatedAverageText = GradeMath.FormatAverage(overall, L10n.ActiveCulture);
            EstimatedAverageBand = GradeMath.BandForAverage(overall);

            foreach (var e in estimates)
            {
                var avgStr = GradeMath.FormatAverage(e.Average, L10n.ActiveCulture);
                var sub = e.WrittenMarkText is not null
                    ? L10n.Format("reportCard.written", avgStr)
                    : L10n.Format("reportCard.estimated", avgStr);
                string? borderline = e.Borderline is not null
                    ? L10n.Format("reportCard.borderline", e.Borderline.Distance, e.Borderline.NeighborMark)
                    : null;

                CurrentEstimates.Add(new ReportCardEstimateRow(
                    e.SubjectName,
                    sub,
                    borderline,
                    e.DisplayMarkText,
                    GradeMath.BandForMarkText(e.DisplayMarkText)));
            }
        }

        foreach (var term in terms)
            PastTerms.Add(term);

        SelectedPastTerm = PastTerms.FirstOrDefault();
    }
}

public sealed class SettingsViewModel : ObservableObject
{
    private readonly SchoolRepository _repository;
    private readonly AppSettings _settings;
    private readonly Action<AppSettings> _onSettingsApplied;
    private readonly Action _onSignOut;
    private readonly Func<SchoolStudentProfile, Task> _onSwitchStudent;

    private int _selectedCategory; // 0=Account, 1=Preferences, 2=About

    public SettingsViewModel(
        SchoolRepository repository,
        AppSettings settings,
        Action<AppSettings> onSettingsApplied,
        Action onSignOut,
        Func<SchoolStudentProfile, Task> onSwitchStudent)
    {
        _repository = repository;
        _settings = settings;
        _onSettingsApplied = onSettingsApplied;
        _onSignOut = onSignOut;
        _onSwitchStudent = onSwitchStudent;

        SignOutCommand = new RelayCommand(_onSignOut);
        SwitchStudentCommand = new AsyncRelayCommand(async obj =>
        {
            if (obj is SchoolStudentProfile student) await _onSwitchStudent(student);
        });
    }

    public LocalizationService L10n => LocalizationService.Instance;

    public int SelectedCategory
    {
        get => _selectedCategory;
        set
        {
            if (SetProperty(ref _selectedCategory, value))
            {
                OnPropertyChanged(nameof(IsAccountSection));
                OnPropertyChanged(nameof(IsPreferencesSection));
                OnPropertyChanged(nameof(IsAboutSection));
            }
        }
    }

    public bool IsAccountSection { get => SelectedCategory == 0; set { if (value) SelectedCategory = 0; } }
    public bool IsPreferencesSection { get => SelectedCategory == 1; set { if (value) SelectedCategory = 1; } }
    public bool IsAboutSection { get => SelectedCategory == 2; set { if (value) SelectedCategory = 2; } }

    public string AccountName => _repository.CurrentSession?.ActiveStudent?.FullName ?? _repository.CurrentSession?.Username ?? "–";
    public string SchoolName => _repository.CurrentSession?.SchoolName ?? _repository.CurrentSession?.BaseUrl ?? "–";
    public string ProviderName => _repository.CurrentSession?.Provider.DisplayName() ?? "–";
    public IReadOnlyList<SchoolStudentProfile> AvailableStudents => _repository.CurrentSession?.AvailableStudents ?? [];
    public bool HasMultipleStudents => AvailableStudents.Count > 1;

    public AppThemePreference Theme
    {
        get => _settings.Theme;
        set { if (_settings.Theme != value) { _settings.Theme = value; OnPropertyChanged(); Apply(); } }
    }

    public AppLanguagePreference Language
    {
        get => _settings.Language;
        set { if (_settings.Language != value) { _settings.Language = value; OnPropertyChanged(); Apply(); } }
    }

    public bool ChronicallyOnline
    {
        get => _settings.ChronicallyOnline;
        set { if (_settings.ChronicallyOnline != value) { _settings.ChronicallyOnline = value; OnPropertyChanged(); Apply(); } }
    }

    public bool ShowMealsTab
    {
        get => _settings.ShowMealsTab;
        set { if (_settings.ShowMealsTab != value) { _settings.ShowMealsTab = value; OnPropertyChanged(); Apply(); } }
    }

    public bool ShowAbsenceSemesterAllowance
    {
        get => _settings.ShowAbsenceSemesterAllowance;
        set { if (_settings.ShowAbsenceSemesterAllowance != value) { _settings.ShowAbsenceSemesterAllowance = value; OnPropertyChanged(); Apply(); } }
    }

    public Array ThemeOptions => Enum.GetValues(typeof(AppThemePreference));
    public Array LanguageOptions => Enum.GetValues(typeof(AppLanguagePreference));

    public RelayCommand SignOutCommand { get; }
    public AsyncRelayCommand SwitchStudentCommand { get; }

    private void Apply()
    {
        _repository.SettingsStore.Save(_settings);
        _onSettingsApplied(_settings);
    }
}
