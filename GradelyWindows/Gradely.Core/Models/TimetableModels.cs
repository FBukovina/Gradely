using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

public enum TimetableKind
{
    Actual,
    Permanent
}

public enum TimetableDayType
{
    WorkDay,
    Weekend,
    Celebration,
    Holiday,
    DirectorDay,
    Undefined
}

public enum LessonChangeKind
{
    None,
    Canceled,
    RoomChanged,
    Added,
    Substitution
}

public sealed class TimetableResponse
{
    [JsonPropertyName("Hours")]
    public List<TimetableHour> Hours { get; set; } = [];

    [JsonPropertyName("Days")]
    public List<TimetableDayDto> Days { get; set; } = [];

    [JsonPropertyName("Classes")]
    public List<TimetableEntity> Classes { get; set; } = [];

    [JsonPropertyName("Groups")]
    public List<TimetableGroup> Groups { get; set; } = [];

    [JsonPropertyName("Subjects")]
    public List<TimetableEntity> Subjects { get; set; } = [];

    [JsonPropertyName("Teachers")]
    public List<TimetableEntity> Teachers { get; set; } = [];

    [JsonPropertyName("Rooms")]
    public List<TimetableEntity> Rooms { get; set; } = [];

    [JsonPropertyName("Cycles")]
    public List<TimetableEntity> Cycles { get; set; } = [];
}

public sealed class TimetableHour
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Id { get; set; }

    [JsonPropertyName("Caption")]
    public string Caption { get; set; } = string.Empty;

    [JsonPropertyName("BeginTime")]
    public string BeginTime { get; set; } = string.Empty;

    [JsonPropertyName("EndTime")]
    public string EndTime { get; set; } = string.Empty;
}

public sealed class TimetableDayDto
{
    [JsonPropertyName("Atoms")]
    public List<TimetableAtom> Atoms { get; set; } = [];

    [JsonPropertyName("DayOfWeek")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int DayOfWeek { get; set; }

    [JsonPropertyName("Date")]
    public string Date { get; set; } = string.Empty;

    [JsonPropertyName("DayDescription")]
    public string DayDescription { get; set; } = string.Empty;

    [JsonPropertyName("DayType")]
    public string DayType { get; set; } = "WorkDay";
}

public sealed class TimetableAtom
{
    [JsonPropertyName("HourId")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int HourId { get; set; }

    [JsonPropertyName("GroupIds")]
    public List<string> GroupIds { get; set; } = [];

    [JsonPropertyName("SubjectId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? SubjectId { get; set; }

    [JsonPropertyName("TeacherId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? TeacherId { get; set; }

    [JsonPropertyName("RoomId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? RoomId { get; set; }

    [JsonPropertyName("CycleIds")]
    public List<string> CycleIds { get; set; } = [];

    [JsonPropertyName("Change")]
    public TimetableChange? Change { get; set; }

    [JsonPropertyName("HomeworkIds")]
    public List<string> HomeworkIds { get; set; } = [];

    [JsonPropertyName("Theme")]
    public string? Theme { get; set; }
}

public sealed class TimetableChange
{
    [JsonPropertyName("ChangeSubject")]
    public string? ChangeSubject { get; set; }

    [JsonPropertyName("Day")]
    public string? Day { get; set; }

    [JsonPropertyName("Hours")]
    public string? Hours { get; set; }

    [JsonPropertyName("ChangeType")]
    public string? ChangeType { get; set; }

    [JsonPropertyName("Description")]
    public string? Description { get; set; }

    [JsonPropertyName("Time")]
    public string? Time { get; set; }

    [JsonPropertyName("TypeAbbrev")]
    public string? TypeAbbrev { get; set; }

    [JsonPropertyName("TypeName")]
    public string? TypeName { get; set; }
}

public sealed class TimetableEntity
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("Abbrev")]
    public string Abbrev { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;
}

public sealed class TimetableGroup
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("Abbrev")]
    public string Abbrev { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("ClassId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? ClassId { get; set; }
}

public sealed record TimetableLesson(
    string Id,
    TimetableHour Hour,
    string? SubjectId,
    string SubjectName,
    string SubjectAbbrev,
    string? TeacherName,
    string? TeacherAbbrev,
    string? RoomName,
    IReadOnlyList<string> GroupIds,
    IReadOnlyList<string> GroupNames,
    IReadOnlyList<string> Cycles,
    string? Theme,
    TimetableChange? Change,
    LessonChangeKind ChangeKind,
    IReadOnlyList<string> HomeworkIds
)
{
    public bool IsCanceled => ChangeKind == LessonChangeKind.Canceled;
    public bool HasChange => ChangeKind != LessonChangeKind.None;
    public bool HasHomework => HomeworkIds.Count > 0;
}

public sealed record TimetableDay(
    string Id,
    int DayOfWeek,
    DateOnly? Date,
    string DayDescription,
    TimetableDayType DayType,
    IReadOnlyList<TimetableLesson> Lessons
);

public sealed record TimetableWeek(
    TimetableKind Kind,
    DateOnly? WeekStart,
    IReadOnlyList<TimetableHour> Hours,
    IReadOnlyList<TimetableDay> Days
);

public enum TodayLessonState
{
    Empty,
    BeforeSchool,
    Current,
    BetweenLessons,
    AfterSchool
}

public sealed record TimedLesson(
    TimetableLesson Lesson,
    DateTime Start,
    DateTime End
);

public sealed record TimetableTodaySummary(
    TodayLessonState State,
    TimedLesson? CurrentLesson,
    TimedLesson? NextLesson,
    int? MinutesRemainingInCurrent,
    int? MinutesUntilNext,
    double CurrentLessonProgress,
    IReadOnlyList<TimedLesson> AllTimedLessons,
    IReadOnlyList<TimedLesson> ChangedLessons
);
