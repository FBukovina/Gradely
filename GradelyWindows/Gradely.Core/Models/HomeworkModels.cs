using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

public sealed class SchoolAttachmentDto
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string? Name { get; set; }

    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    [JsonPropertyName("Size")]
    [JsonConverter(typeof(FlexibleNullableIntConverter))]
    public int? Size { get; set; }
}

public sealed record SchoolAttachment(string Id, string Name, int? Size)
{
    public string FormattedSize
    {
        get
        {
            if (Size is null or <= 0) return string.Empty;
            if (Size < 1024) return $"{Size} B";
            if (Size < 1024 * 1024) return $"{Size / 1024.0:F1} KB";
            return $"{Size / (1024.0 * 1024.0):F1} MB";
        }
    }
}

public sealed class HomeworkResponse
{
    [JsonPropertyName("Homeworks")]
    public List<HomeworkDto> Homeworks { get; set; } = [];
}

public sealed class HomeworkDto
{
    [JsonPropertyName("ID")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("DateStart")]
    public string? DateStart { get; set; }

    [JsonPropertyName("DateEnd")]
    public string? DateEnd { get; set; }

    [JsonPropertyName("Content")]
    public string? Content { get; set; }

    [JsonPropertyName("Notice")]
    public string? Notice { get; set; }

    [JsonPropertyName("Done")]
    public bool Done { get; set; }

    [JsonPropertyName("Closed")]
    public bool Closed { get; set; }

    [JsonPropertyName("Electronic")]
    public bool Electronic { get; set; }

    [JsonPropertyName("Hour")]
    [JsonConverter(typeof(FlexibleNullableIntConverter))]
    public int? Hour { get; set; }

    [JsonPropertyName("Subject")]
    public SubjectInfo? Subject { get; set; }

    [JsonPropertyName("Teacher")]
    public SubjectInfo? Teacher { get; set; }

    [JsonPropertyName("Attachments")]
    public List<SchoolAttachmentDto> Attachments { get; set; } = [];
}

public sealed class HomeworkItem
{
    public string Id { get; init; } = string.Empty;
    public DateTimeOffset? AssignedOn { get; init; }
    public DateTimeOffset? DueOn { get; init; }
    public string Content { get; init; } = string.Empty;
    public string? Notice { get; init; }
    public bool IsDone { get; set; }
    public bool IsClosed { get; init; }
    public bool IsElectronic { get; init; }
    public string? SubjectId { get; init; }
    public string SubjectName { get; init; } = string.Empty;
    public string SubjectAbbrev { get; init; } = string.Empty;
    public string? TeacherName { get; init; }
    public IReadOnlyList<SchoolAttachment> Attachments { get; init; } = [];

    public bool IsOpen => !IsDone && !IsClosed;

    public string Title
    {
        get
        {
            var firstLine = Content
                .Replace("\r\n", "\n")
                .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Select(l => l.Trim())
                .FirstOrDefault(l => !string.IsNullOrEmpty(l));
            if (!string.IsNullOrEmpty(firstLine)) return firstLine;
            return !string.IsNullOrEmpty(SubjectName) ? SubjectName : "School homework";
        }
    }

    public static HomeworkItem FromDto(HomeworkDto dto) => new()
    {
        Id = dto.Id,
        AssignedOn = Mark.ParseSchoolDate(dto.DateStart),
        DueOn = Mark.ParseSchoolDate(dto.DateEnd),
        Content = (dto.Content ?? string.Empty).Trim(),
        Notice = string.IsNullOrWhiteSpace(dto.Notice) ? null : dto.Notice.Trim(),
        IsDone = dto.Done,
        IsClosed = dto.Closed,
        IsElectronic = dto.Electronic,
        SubjectId = dto.Subject?.Id?.Trim(),
        SubjectName = dto.Subject?.Name?.Trim() ?? string.Empty,
        SubjectAbbrev = dto.Subject?.Abbrev?.Trim() ?? string.Empty,
        TeacherName = string.IsNullOrWhiteSpace(dto.Teacher?.Name) ? null : dto.Teacher.Name.Trim(),
        Attachments = dto.Attachments.Select(a => new SchoolAttachment(
            a.Id,
            string.IsNullOrWhiteSpace(a.Name) ? a.Id : a.Name.Trim(),
            a.Size > 0 ? a.Size : null)).ToList()
    };
}
