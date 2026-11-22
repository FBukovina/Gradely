using System.Text.Json.Serialization;
using Gradely.Core.Support;

namespace Gradely.Core.Models;

public sealed class FinalMarksResponse
{
    [JsonPropertyName("CertificateTerms")]
    public List<CertificateTermDto> Terms { get; set; } = [];
}

public sealed class CertificateTermDto
{
    [JsonPropertyName("FinalMarks")]
    public List<FinalMarkDto> FinalMarks { get; set; } = [];

    [JsonPropertyName("Subjects")]
    public List<FinalMarkSubjectDto> Subjects { get; set; } = [];

    [JsonPropertyName("SchoolYear")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? SchoolYear { get; set; }

    [JsonPropertyName("Semester")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Semester { get; set; }

    [JsonPropertyName("Closed")]
    public bool Closed { get; set; } = true;

    [JsonPropertyName("AchievementText")]
    public string? AchievementText { get; set; }

    [JsonPropertyName("MarksAverage")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? MarksAverage { get; set; }

    [JsonPropertyName("AbsentHours")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? AbsentHours { get; set; }

    [JsonPropertyName("NotExcusedHours")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? NotExcusedHours { get; set; }

    [JsonPropertyName("CertificateDate")]
    public string? CertificateDate { get; set; }
}

public sealed class FinalMarkDto
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Id { get; set; }

    [JsonPropertyName("SubjectId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string SubjectId { get; set; } = string.Empty;

    [JsonPropertyName("MarkText")]
    public string MarkText { get; set; } = string.Empty;
}

public sealed class FinalMarkSubjectDto
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("Abbrev")]
    public string? Abbrev { get; set; }

    [JsonPropertyName("Name")]
    public string? Name { get; set; }
}

public readonly record struct ReportCardPeriod(int StartYear, int Semester)
{
    public static ReportCardPeriod Containing(DateTime date)
    {
        var semester = date.Month >= 9 || date.Month == 1 ? 1 : 2;
        var startYear = date.Month >= 9 ? date.Year : date.Year - 1;
        return new ReportCardPeriod(startYear, semester);
    }

    public string SchoolYear => $"{StartYear}/{(StartYear + 1) % 100:00}";
}

public sealed record ReportCardMark(
    string SubjectId,
    string SubjectName,
    string? SubjectAbbrev,
    string MarkText
);

public sealed class ReportCardTerm
{
    public string SchoolYear { get; init; } = string.Empty;
    public string Semester { get; init; } = string.Empty;
    public bool IsClosed { get; init; }
    public string? AchievementText { get; init; }
    public double? Average { get; init; }
    public double? AbsentHours { get; init; }
    public double? UnexcusedHours { get; init; }
    public DateTimeOffset? IssuedOn { get; init; }
    public IReadOnlyList<ReportCardMark> Marks { get; init; } = [];

    public string Id => $"{SchoolYear}-{Semester}";

    public bool Matches(ReportCardPeriod period) =>
        string.Equals(SchoolYear, period.SchoolYear, StringComparison.Ordinal) &&
        string.Equals(Semester, period.Semester.ToString(), StringComparison.Ordinal);

    public ReportCardMark? MarkFor(SubjectMarks subject)
    {
        var byId = Marks.FirstOrDefault(m => string.Equals(m.SubjectId, subject.Id, StringComparison.Ordinal));
        if (byId is not null) return byId;

        if (!string.IsNullOrEmpty(subject.TrimmedAbbrev))
        {
            var byAbbrev = Marks.FirstOrDefault(m =>
                !string.IsNullOrEmpty(m.SubjectAbbrev) &&
                string.Equals(m.SubjectAbbrev, subject.TrimmedAbbrev, StringComparison.OrdinalIgnoreCase));
            if (byAbbrev is not null) return byAbbrev;
        }

        return Marks.FirstOrDefault(m => string.Equals(m.SubjectName, subject.TrimmedName, StringComparison.OrdinalIgnoreCase));
    }

    public static ReportCardTerm FromDto(CertificateTermDto dto)
    {
        var marksBySubject = new Dictionary<string, FinalMarkDto>(StringComparer.Ordinal);
        foreach (var fm in dto.FinalMarks)
            marksBySubject.TryAdd(fm.SubjectId, fm);

        var list = new List<ReportCardMark>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (var subj in dto.Subjects)
        {
            if (!marksBySubject.TryGetValue(subj.Id, out var fm)) continue;
            var text = fm.MarkText.Trim();
            if (text.Length == 0) continue;
            seen.Add(subj.Id);
            list.Add(new ReportCardMark(
                subj.Id,
                string.IsNullOrWhiteSpace(subj.Name) ? subj.Id : subj.Name.Trim(),
                string.IsNullOrWhiteSpace(subj.Abbrev) ? null : subj.Abbrev.Trim(),
                text));
        }

        foreach (var fm in dto.FinalMarks)
        {
            if (seen.Contains(fm.SubjectId)) continue;
            var text = fm.MarkText.Trim();
            if (text.Length == 0) continue;
            list.Add(new ReportCardMark(fm.SubjectId, fm.SubjectId, null, text));
        }

        return new ReportCardTerm
        {
            SchoolYear = dto.SchoolYear?.Trim() ?? string.Empty,
            Semester = dto.Semester?.Trim(' ', '.') ?? string.Empty,
            IsClosed = dto.Closed,
            AchievementText = string.IsNullOrWhiteSpace(dto.AchievementText) ? null : dto.AchievementText.Trim(),
            Average = dto.MarksAverage is > 0 ? dto.MarksAverage : null,
            AbsentHours = dto.AbsentHours,
            UnexcusedHours = dto.NotExcusedHours,
            IssuedOn = Mark.ParseSchoolDate(dto.CertificateDate),
            Marks = list
        };
    }

    public static List<ReportCardTerm> SortNewestFirst(IEnumerable<ReportCardTerm> terms) =>
        terms.OrderByDescending(t => t.SchoolYear, StringComparer.Ordinal)
             .ThenByDescending(t => t.Semester, StringComparer.Ordinal)
             .ToList();
}

public sealed record ReportCardBorderline(int NeighborMark, double Distance);

public sealed record ReportCardEstimate(
    string SubjectId,
    string SubjectName,
    double? Average,
    string? WrittenMarkText,
    int? EstimatedMark,
    ReportCardBorderline? Borderline
)
{
    public const double BorderlineMargin = 0.1;

    public double? MarkValue => WrittenMarkText is not null
        ? GradeMath.ParseMarkValue(WrittenMarkText)
        : EstimatedMark;

    public string DisplayMarkText => WrittenMarkText ?? EstimatedMark?.ToString() ?? "–";

    public static int MarkForAverage(double average) =>
        Math.Clamp((int)Math.Ceiling(average - 0.5), 1, 5);

    public static ReportCardBorderline? FindBorderline(double average, int mark)
    {
        var candidates = new List<ReportCardBorderline>();
        if (mark < 5) candidates.Add(new ReportCardBorderline(mark + 1, mark + 0.5 - average));
        if (mark > 1) candidates.Add(new ReportCardBorderline(mark - 1, average - (mark - 0.5)));

        return candidates
            .Where(c => c.Distance >= 0 && c.Distance <= BorderlineMargin + 0.0001)
            .OrderBy(c => c.Distance)
            .FirstOrDefault();
    }

    public static List<ReportCardEstimate> BuildEstimates(
        IReadOnlyList<SubjectMarks> subjects,
        IReadOnlyDictionary<string, PreparedGradeCalculation> prepared,
        ReportCardTerm? writtenTerm)
    {
        var result = new List<ReportCardEstimate>(subjects.Count);
        foreach (var subject in subjects)
        {
            var avg = prepared.TryGetValue(subject.Id, out var calc) ? calc.DisplayAverage : GradeMath.Prepare(subject).DisplayAverage;
            var written = writtenTerm?.MarkFor(subject)?.MarkText;
            var est = avg.HasValue ? MarkForAverage(avg.Value) : (int?)null;
            ReportCardBorderline? borderline = null;
            if (written is null && avg.HasValue && est.HasValue)
                borderline = FindBorderline(avg.Value, est.Value);

            result.Add(new ReportCardEstimate(subject.Id, subject.TrimmedName, avg, written, est, borderline));
        }
        return result;
    }

    public static double? OverallAverage(IEnumerable<ReportCardEstimate> estimates)
    {
        var vals = estimates.Select(e => e.MarkValue).Where(v => v.HasValue).Select(v => v!.Value).ToList();
        return vals.Count > 0 ? vals.Average() : null;
    }
}
