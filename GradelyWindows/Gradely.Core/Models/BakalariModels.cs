using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

public sealed class LoginResponse
{
    [JsonPropertyName("access_token")]
    public string AccessToken { get; set; } = string.Empty;

    [JsonPropertyName("refresh_token")]
    public string? RefreshToken { get; set; }

    [JsonPropertyName("token_type")]
    public string TokenType { get; set; } = "Bearer";

    [JsonPropertyName("expires_in")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int ExpiresIn { get; set; } = 3600;

    [JsonPropertyName("bak:ApiVersion")]
    public string? ApiVersion { get; set; }

    [JsonPropertyName("bak:AppVersion")]
    public string? AppVersion { get; set; }

    [JsonPropertyName("bak:UserId")]
    public string? UserId { get; set; }
}

public sealed class ClassInfo
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Id { get; set; }

    [JsonPropertyName("Abbrev")]
    public string? Abbrev { get; set; }

    [JsonPropertyName("Name")]
    public string? Name { get; set; }
}

public sealed class UserResponse
{
    [JsonPropertyName("UserUID")]
    public string UserUid { get; set; } = string.Empty;

    [JsonPropertyName("FullName")]
    public string FullName { get; set; } = string.Empty;

    [JsonPropertyName("Class")]
    public ClassInfo? Class { get; set; }

    [JsonPropertyName("SchoolOrganizationName")]
    public string? SchoolOrganizationName { get; set; }

    [JsonPropertyName("SchoolName")]
    public string? SchoolName { get; set; }

    [JsonPropertyName("UserType")]
    public string UserType { get; set; } = "student";

    [JsonPropertyName("UserTypeText")]
    public string UserTypeText { get; set; } = string.Empty;

    [JsonPropertyName("StudyYear")]
    [JsonConverter(typeof(FlexibleNullableIntConverter))]
    public int? StudyYear { get; set; }

    [JsonIgnore]
    public string? ResolvedSchoolName
    {
        get
        {
            foreach (var candidate in new[] { SchoolOrganizationName, SchoolName })
            {
                if (string.IsNullOrWhiteSpace(candidate)) continue;
                var trimmed = candidate.Trim();
                var folded = RemoveDiacritics(trimmed).ToLowerInvariant();
                if (folded is "nazev skoly" or "school name") continue;
                return trimmed;
            }
            return null;
        }
    }

    [JsonIgnore]
    public string NameWithoutClass
    {
        get
        {
            var full = FullName.Trim();
            if (string.IsNullOrEmpty(full)) return full;
            var commaIdx = full.LastIndexOf(',');
            if (commaIdx <= 0) return full;

            var suffix = full[(commaIdx + 1)..].Trim();
            var classAbbrev = Class?.Abbrev?.Trim();
            if (!string.IsNullOrEmpty(classAbbrev) && string.Equals(suffix, classAbbrev, StringComparison.OrdinalIgnoreCase))
                return full[..commaIdx].Trim();

            if (!suffix.Contains(' ') && suffix.Length <= 6 && suffix.Any(char.IsDigit))
                return full[..commaIdx].Trim();

            return full;
        }
    }

    private static string RemoveDiacritics(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(normalized.Length);
        foreach (var c in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        }
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }
}

public sealed class MarksResponse
{
    [JsonPropertyName("Subjects")]
    public List<SubjectMarks> Subjects { get; set; } = [];
}

public sealed class SubjectInfo
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Id { get; set; }

    [JsonPropertyName("Abbrev")]
    public string? Abbrev { get; set; }

    [JsonPropertyName("Name")]
    public string? Name { get; set; }
}

public sealed class SubjectMarks
{
    [JsonPropertyName("Marks")]
    public List<Mark> Marks { get; set; } = [];

    [JsonPropertyName("Subject")]
    public SubjectInfo Subject { get; set; } = new();

    [JsonPropertyName("AverageText")]
    public string? AverageText { get; set; }

    [JsonPropertyName("TemporaryMark")]
    public string? TemporaryMark { get; set; }

    [JsonPropertyName("SubjectNote")]
    public string? SubjectNote { get; set; }

    [JsonPropertyName("TemporaryMarkNote")]
    public string? TemporaryMarkNote { get; set; }

    [JsonPropertyName("PointsOnly")]
    public bool PointsOnly { get; set; }

    [JsonPropertyName("MarkPredictionEnabled")]
    public bool MarkPredictionEnabled { get; set; }

    [JsonIgnore]
    public string Id => Subject.Id?.Trim() ?? string.Empty;

    [JsonIgnore]
    public string TrimmedName => string.IsNullOrWhiteSpace(Subject.Name) ? Id : Subject.Name.Trim();

    [JsonIgnore]
    public string TrimmedAbbrev
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Subject.Abbrev)) return Subject.Abbrev.Trim();
            return TrimmedName.Length <= 3 ? TrimmedName.ToUpperInvariant() : TrimmedName[..Math.Min(3, TrimmedName.Length)].ToUpperInvariant();
        }
    }
}

public sealed class Mark
{
    [JsonPropertyName("MarkDate")]
    public string MarkDate { get; set; } = string.Empty;

    [JsonPropertyName("EditDate")]
    public string? EditDate { get; set; }

    [JsonPropertyName("Caption")]
    public string? Caption { get; set; }

    [JsonPropertyName("Theme")]
    public string? Theme { get; set; }

    [JsonPropertyName("MarkText")]
    public string MarkText { get; set; } = string.Empty;

    [JsonPropertyName("TeacherId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? TeacherId { get; set; }

    [JsonPropertyName("Type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("TypeNote")]
    public string? TypeNote { get; set; }

    [JsonPropertyName("Weight")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? Weight { get; set; }

    [JsonPropertyName("SubjectId")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? SubjectId { get; set; }

    [JsonPropertyName("IsNew")]
    public bool IsNew { get; set; }

    [JsonPropertyName("IsPoints")]
    public bool IsPoints { get; set; }

    [JsonPropertyName("CalculatedMarkText")]
    public string? CalculatedMarkText { get; set; }

    [JsonPropertyName("ClassRankText")]
    public string? ClassRankText { get; set; }

    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Id { get; set; }

    [JsonPropertyName("PointsText")]
    public string? PointsText { get; set; }

    [JsonPropertyName("MaxPoints")]
    [JsonConverter(typeof(FlexibleNullableIntConverter))]
    public int? MaxPoints { get; set; }

    [JsonPropertyName("ConfirmedWhen")]
    public string? ConfirmedWhen { get; set; }

    [JsonPropertyName("ConfirmedBy")]
    public string? ConfirmedBy { get; set; }

    [JsonPropertyName("MarkConfirmationState")]
    public string? MarkConfirmationState { get; set; }

    [JsonIgnore]
    public string EffectiveId => string.IsNullOrWhiteSpace(Id) ? ComputeSyntheticId() : Id.Trim();

    [JsonIgnore]
    public bool HasStableProviderId => !string.IsNullOrWhiteSpace(Id) && !Id.Trim().StartsWith("local-mark-", StringComparison.Ordinal);

    [JsonIgnore]
    public string DisplayText
    {
        get
        {
            if (IsPoints && !string.IsNullOrWhiteSpace(PointsText) && MaxPoints.HasValue)
                return $"{MarkText}/{MaxPoints.Value}";
            if (IsPoints && MaxPoints.HasValue && !MarkText.Contains('/'))
                return $"{MarkText}/{MaxPoints.Value}";
            return MarkText;
        }
    }

    [JsonIgnore]
    public string DisplayCaption
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Caption)) return Caption.Trim();
            if (!string.IsNullOrWhiteSpace(Theme)) return Theme.Trim();
            return string.Empty;
        }
    }

    [JsonIgnore]
    public bool ShouldShowTheme =>
        !string.IsNullOrWhiteSpace(Caption) &&
        !string.IsNullOrWhiteSpace(Theme) &&
        !string.Equals(Caption.Trim(), Theme.Trim(), StringComparison.OrdinalIgnoreCase);

    [JsonIgnore]
    public DateTimeOffset? ParsedDate => ParseSchoolDate(MarkDate);

    public string CanonicalHash()
    {
        var sb = new StringBuilder();
        AppendField(sb, SubjectId ?? "");
        AppendField(sb, MarkDate);
        AppendField(sb, MarkText);
        AppendField(sb, Type);
        AppendField(sb, TypeNote ?? "");
        AppendField(sb, Caption ?? "");
        AppendField(sb, Theme ?? "");
        AppendField(sb, Weight?.ToString("R", CultureInfo.InvariantCulture) ?? "");
        AppendField(sb, IsPoints ? "points" : "grade");
        AppendField(sb, PointsText ?? "");
        AppendField(sb, MaxPoints?.ToString(CultureInfo.InvariantCulture) ?? "");
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString()));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private string ComputeSyntheticId() => "local-mark-" + CanonicalHash()[..24];

    private static void AppendField(StringBuilder sb, string value)
    {
        sb.Append(value.Length).Append(':').Append(value).Append('|');
    }

    public static DateTimeOffset? ParseSchoolDate(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = raw.Trim();
        if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var dto))
            return dto;
        if (s.Length >= 10 && DateOnly.TryParseExact(s[..10], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
            return new DateTimeOffset(d.ToDateTime(TimeOnly.MinValue), TimeZoneInfo.Local.GetUtcOffset(d.ToDateTime(TimeOnly.MinValue)));
        return null;
    }
}

public sealed class WhatIfMarkRequest
{
    [JsonPropertyName("Id")]
    public string? Id { get; set; }

    [JsonPropertyName("MarkText")]
    public string MarkText { get; set; } = string.Empty;

    [JsonPropertyName("Weight")]
    public int? Weight { get; set; }

    [JsonPropertyName("MaxPoints")]
    public int MaxPoints { get; set; }

    [JsonPropertyName("SubjectId")]
    public string SubjectId { get; set; } = string.Empty;
}

public sealed class AbsenceResponse
{
    [JsonPropertyName("PercentageThreshold")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? PercentageThreshold { get; set; }

    [JsonPropertyName("Absences")]
    public List<AbsenceDay> Absences { get; set; } = [];

    [JsonPropertyName("AbsencesPerSubject")]
    public List<AbsencePerSubject> AbsencesPerSubject { get; set; } = [];
}

public sealed class AbsenceDay
{
    [JsonPropertyName("Date")]
    public string Date { get; set; } = string.Empty;

    [JsonPropertyName("Unsolved")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Unsolved { get; set; }

    [JsonPropertyName("Ok")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Ok { get; set; }

    [JsonPropertyName("Missed")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Missed { get; set; }

    [JsonPropertyName("Late")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Late { get; set; }

    [JsonPropertyName("Soon")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Soon { get; set; }

    [JsonPropertyName("School")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int School { get; set; }

    [JsonPropertyName("DistanceTeaching")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int DistanceTeaching { get; set; }

    [JsonIgnore]
    public string DateKey => Date.Length >= 10 ? Date[..10] : Date;

    [JsonIgnore]
    public int Total => Unsolved + Ok + Missed + Late + Soon + School + DistanceTeaching;

    [JsonIgnore]
    public int BaseCount => Unsolved + Ok + Missed;

    public AbsenceDay Clone() => new()
    {
        Date = Date,
        Unsolved = Unsolved,
        Ok = Ok,
        Missed = Missed,
        Late = Late,
        Soon = Soon,
        School = School,
        DistanceTeaching = DistanceTeaching
    };
}

public sealed class AbsencePerSubject
{
    [JsonPropertyName("SubjectName")]
    public string SubjectName { get; set; } = string.Empty;

    [JsonPropertyName("LessonsCount")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int LessonsCount { get; set; }

    [JsonPropertyName("Base")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Base { get; set; }

    [JsonPropertyName("Late")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Late { get; set; }

    [JsonPropertyName("Soon")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Soon { get; set; }

    [JsonPropertyName("School")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int School { get; set; }

    [JsonPropertyName("DistanceTeaching")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int DistanceTeaching { get; set; }

    [JsonIgnore]
    public double AbsencePercentage => LessonsCount > 0 ? (double)Base / LessonsCount * 100.0 : 0.0;

    public AbsencePerSubject Clone() => new()
    {
        SubjectName = SubjectName,
        LessonsCount = LessonsCount,
        Base = Base,
        Late = Late,
        Soon = Soon,
        School = School,
        DistanceTeaching = DistanceTeaching
    };
}
