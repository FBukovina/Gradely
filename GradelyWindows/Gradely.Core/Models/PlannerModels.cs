using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum PlannerItemType
{
    Homework,
    Test,
    Presentation,
    Note,
    Task
}

public sealed record PlannerSubjectReference(
    string Scope,
    string Id,
    string Name,
    string? Abbreviation = null
);

public sealed record PlannerLessonReference(
    string Scope,
    string LessonId,
    string DayKey,
    int HourId,
    string? SubjectId,
    IReadOnlyList<string> GroupIds,
    DateTime? Start,
    DateTime? End,
    string HourCaption,
    string? Teacher,
    string? Room
)
{
    public bool Matches(TimetableLesson lesson, TimetableDay day, string scope)
    {
        if (!string.Equals(Scope, scope, StringComparison.Ordinal)) return false;
        var dayKey = day.Date?.ToString("yyyy-MM-dd") ?? day.Id;
        if (!string.Equals(DayKey, dayKey, StringComparison.Ordinal)) return false;
        if (HourId != lesson.Hour.Id) return false;
        if (!string.Equals(SubjectId, lesson.SubjectId, StringComparison.Ordinal)) return false;
        var sortedA = GroupIds.OrderBy(x => x, StringComparer.Ordinal).ToList();
        var sortedB = lesson.GroupIds.OrderBy(x => x, StringComparer.Ordinal).ToList();
        return sortedA.SequenceEqual(sortedB, StringComparer.Ordinal);
    }
}

public sealed class PlannerItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Scope { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public PlannerItemType Type { get; set; } = PlannerItemType.Homework;
    public PlannerSubjectReference? Subject { get; set; }
    public PlannerLessonReference? Lesson { get; set; }
    public DateTime? LinkedDate { get; set; }
    public DateTime? DueDate { get; set; }
    public bool DueHasTime { get; set; }
    public bool IsCompleted { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonIgnore]
    public DateTime? OrderingDate => DueDate ?? Lesson?.Start ?? LinkedDate;

    [JsonIgnore]
    public bool IsAssessment => Type is PlannerItemType.Test or PlannerItemType.Presentation;
}
