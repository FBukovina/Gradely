using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;
using Gradely.Core.Models;

namespace Gradely.Core.Support;

public enum AbsenceRiskLevel
{
    Unavailable = 0,
    Safe = 1,
    Watch = 2,
    High = 3,
    OverLimit = 4
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AbsenceCategory
{
    Unsolved,
    Ok,
    Missed,
    Late,
    Soon,
    School,
    DistanceTeaching
}

public static class AbsenceCategoryExtensions
{
    public static bool ContributesToBase(this AbsenceCategory category) =>
        category is AbsenceCategory.Unsolved or AbsenceCategory.Ok or AbsenceCategory.Missed;

    public static string ShortSymbol(this AbsenceCategory category) => category switch
    {
        AbsenceCategory.Unsolved => "?",
        AbsenceCategory.Ok => "✓",
        AbsenceCategory.Missed => "N",
        AbsenceCategory.Late => "P",
        AbsenceCategory.Soon => "O",
        AbsenceCategory.School => "–",
        AbsenceCategory.DistanceTeaching => "D",
        _ => "?"
    };
}

public sealed record AbsenceSubjectSummary(
    string StableId,
    string SubjectName,
    int LessonsCount,
    int BaseCount,
    int Late,
    int Soon,
    int School,
    int DistanceTeaching,
    double AbsencePercentage,
    double? NormalizedThreshold,
    AbsenceRiskLevel RiskLevel,
    int? MissesUntilLimit,
    SemesterAllowance? SemesterAllowance = null
)
{
    public bool ExceedsThreshold => NormalizedThreshold is > 0 && AbsencePercentage >= NormalizedThreshold.Value;
}

public enum SemesterAllowanceKind
{
    CanMiss,
    NoMoreMisses,
    OverEvenWithFullAttendance
}

public sealed record SemesterAllowance(
    SemesterAllowanceKind Kind,
    int AllowedMisses,
    int RemainingLessons,
    DateOnly TermEnd
);

public sealed record AbsenceLessonCandidate(
    string Id,
    string DateKey,
    int HourId,
    string HourCaption,
    string SubjectKey,
    string SubjectName,
    string TimeRange
);

public sealed record AbsenceSubjectPrediction(
    string SubjectName,
    int CurrentBase,
    int CurrentLessonsCount,
    double CurrentPercentage,
    int ProjectedBase,
    int ProjectedLessonsCount,
    double ProjectedPercentage,
    int AddedHours,
    bool CurrentlyExceedsThreshold,
    bool ProjectedExceedsThreshold
)
{
    public bool CrossesThreshold => !CurrentlyExceedsThreshold && ProjectedExceedsThreshold;
}

public sealed record AbsencePredictionSummary(
    int CurrentTotalHours,
    int ProjectedTotalHours,
    int AddedHours,
    IReadOnlyList<AbsenceSubjectPrediction> Subjects
);

public sealed record AbsenceOverrideAllocation(
    string Id,
    string? LessonId,
    string SubjectName,
    AbsenceCategory Category
);

public sealed class AbsenceDayOverride
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Scope { get; set; } = string.Empty;
    public string DateKey { get; set; } = string.Empty;
    public AbsenceDay BaselineDay { get; set; } = new();
    public List<AbsenceOverrideAllocation> Allocations { get; set; } = [];
    public HashSet<string> HiddenAllocationIds { get; set; } = [];
    public string? PauseReason { get; set; }
    public DateTimeOffset SavedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonIgnore]
    public bool HidesEntireDay => Allocations.Count > 0 && Allocations.All(a => HiddenAllocationIds.Contains(a.Id));
}

public sealed record ProjectedAbsenceResult(
    AbsenceResponse EffectiveResponse,
    IReadOnlyList<AbsenceDayOverride> ActiveOverrides,
    IReadOnlyList<AbsenceDayOverride> ReviewOverrides
)
{
    public bool HasLocalAdjustments => ActiveOverrides.Count > 0;
    public bool NeedsReview => ReviewOverrides.Count > 0;
}

public static class AbsenceAnalytics
{
    public static double? NormalizeThreshold(double? raw)
    {
        if (raw is null || !double.IsFinite(raw.Value) || raw.Value <= 0) return null;
        return raw.Value <= 1.0 ? raw.Value * 100.0 : raw.Value;
    }

    public static AbsenceRiskLevel ComputeRiskLevel(double percentage, double? normalizedThreshold)
    {
        if (normalizedThreshold is null or <= 0) return AbsenceRiskLevel.Unavailable;
        var ratio = percentage / normalizedThreshold.Value;
        if (ratio >= 1.0) return AbsenceRiskLevel.OverLimit;
        if (ratio >= 0.9) return AbsenceRiskLevel.High;
        if (ratio >= 0.7) return AbsenceRiskLevel.Watch;
        return AbsenceRiskLevel.Safe;
    }

    public static int? MissesUntilLimit(int missed, int totalLessons, double? normalizedThreshold)
    {
        if (normalizedThreshold is null or <= 0 or >= 100 || totalLessons <= 0) return null;
        var limit = normalizedThreshold.Value / 100.0;
        if ((double)missed / totalLessons >= limit) return 0;

        for (int k = 1; k < 10_000; k++)
        {
            if ((double)(missed + k) / (totalLessons + k) >= limit)
                return k;
        }
        return null;
    }

    public static (DateOnly Start, DateOnly End) CzechTermBounds(DateOnly referenceDate)
    {
        return referenceDate.Month switch
        {
            >= 9 => (new DateOnly(referenceDate.Year, 9, 1), new DateOnly(referenceDate.Year + 1, 1, 31)),
            1 => (new DateOnly(referenceDate.Year - 1, 9, 1), new DateOnly(referenceDate.Year, 1, 31)),
            _ => (new DateOnly(referenceDate.Year, 2, 1), new DateOnly(referenceDate.Year, 6, 30))
        };
    }

    public static SemesterAllowance? ComputeSemesterAllowance(
        int taughtLessons,
        int missedLessons,
        int remainingLessons,
        double? normalizedThreshold,
        DateOnly termEnd)
    {
        if (normalizedThreshold is null or <= 0 or >= 100) return null;
        var total = taughtLessons + remainingLessons;
        if (total <= 0) return null;

        var limit = (normalizedThreshold.Value / 100.0) * total;
        var maxMissed = (int)Math.Ceiling(limit - 1e-9) - 1;
        if (maxMissed < missedLessons)
            return new SemesterAllowance(SemesterAllowanceKind.OverEvenWithFullAttendance, 0, remainingLessons, termEnd);

        var allowed = Math.Min(maxMissed - missedLessons, remainingLessons);
        return allowed > 0
            ? new SemesterAllowance(SemesterAllowanceKind.CanMiss, allowed, remainingLessons, termEnd)
            : new SemesterAllowance(SemesterAllowanceKind.NoMoreMisses, 0, remainingLessons, termEnd);
    }

    public static List<AbsenceSubjectSummary> SummarizeSubjects(
        AbsenceResponse response,
        IReadOnlyDictionary<string, int>? remainingLessonsBySubject = null,
        DateOnly? termEnd = null)
    {
        var threshold = NormalizeThreshold(response.PercentageThreshold);
        var summaries = new List<AbsenceSubjectSummary>(response.AbsencesPerSubject.Count);

        foreach (var sub in response.AbsencesPerSubject)
        {
            var pct = sub.AbsencePercentage;
            var risk = ComputeRiskLevel(pct, threshold);
            var until = MissesUntilLimit(sub.Base, sub.LessonsCount, threshold);

            SemesterAllowance? allowance = null;
            if (remainingLessonsBySubject is not null && termEnd.HasValue)
            {
                var key = NormalizeKey(sub.SubjectName);
                if (remainingLessonsBySubject.TryGetValue(key, out var remaining))
                {
                    allowance = ComputeSemesterAllowance(sub.LessonsCount, sub.Base, remaining, threshold, termEnd.Value);
                }
            }

            summaries.Add(new AbsenceSubjectSummary(
                NormalizeKey(sub.SubjectName),
                sub.SubjectName.Trim(),
                sub.LessonsCount,
                sub.Base,
                sub.Late,
                sub.Soon,
                sub.School,
                sub.DistanceTeaching,
                pct,
                threshold,
                risk,
                until,
                allowance));
        }

        return summaries
            .OrderByDescending(s => s.ExceedsThreshold)
            .ThenByDescending(s => s.AbsencePercentage)
            .ThenBy(s => s.SubjectName, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public static AbsencePredictionSummary Predict(
        AbsenceResponse currentResponse,
        IReadOnlyList<AbsenceSubjectSummary> currentSubjects,
        IReadOnlyList<AbsenceLessonCandidate> selectedLessons)
    {
        var threshold = NormalizeThreshold(currentResponse.PercentageThreshold);
        var unique = selectedLessons
            .GroupBy(l => l.Id, StringComparer.Ordinal)
            .Select(g => g.First())
            .ToList();

        var currentTotal = currentResponse.Absences.Sum(d => d.Total);
        var addedBySubject = unique
            .GroupBy(l => NormalizeKey(l.SubjectName), StringComparer.Ordinal)
            .ToList();

        var predictions = new List<AbsenceSubjectPrediction>();
        foreach (var group in addedBySubject)
        {
            var added = group.Count();
            var baseline = currentSubjects.FirstOrDefault(s =>
                string.Equals(s.StableId, group.Key, StringComparison.Ordinal) ||
                string.Equals(NormalizeKey(s.SubjectName), group.Key, StringComparison.Ordinal));

            if (baseline is null) continue;

            var projBase = baseline.BaseCount + added;
            var projTotal = baseline.LessonsCount + added;
            var projPct = projTotal > 0 ? (double)projBase / projTotal * 100.0 : 0.0;
            var projExceeds = threshold is > 0 && projPct >= threshold.Value;

            predictions.Add(new AbsenceSubjectPrediction(
                baseline.SubjectName,
                baseline.BaseCount,
                baseline.LessonsCount,
                baseline.AbsencePercentage,
                projBase,
                projTotal,
                projPct,
                added,
                baseline.ExceedsThreshold,
                projExceeds));
        }

        predictions = predictions
            .OrderByDescending(p => p.ProjectedExceedsThreshold)
            .ThenByDescending(p => p.ProjectedPercentage)
            .ThenBy(p => p.SubjectName, StringComparer.CurrentCultureIgnoreCase)
            .ToList();

        return new AbsencePredictionSummary(currentTotal, currentTotal + unique.Count, unique.Count, predictions);
    }

    public static ProjectedAbsenceResult ProjectOverrides(
        AbsenceResponse rawResponse,
        IReadOnlyList<AbsenceDayOverride> savedOverrides)
    {
        var effectiveDays = rawResponse.Absences.Select(d => d.Clone()).ToList();
        var effectiveSubjects = rawResponse.AbsencesPerSubject.Select(s => s.Clone()).ToList();
        var active = new List<AbsenceDayOverride>();
        var review = new List<AbsenceDayOverride>();
        var fullyHiddenDateKeys = new HashSet<string>(StringComparer.Ordinal);

        foreach (var ov in savedOverrides.OrderBy(o => o.DateKey, StringComparer.Ordinal))
        {
            if (!string.IsNullOrWhiteSpace(ov.PauseReason))
            {
                review.Add(ov);
                continue;
            }

            var matchingDays = effectiveDays
                .Select((day, index) => (day, index))
                .Where(x => string.Equals(x.day.DateKey, ov.DateKey, StringComparison.Ordinal))
                .ToList();

            if (matchingDays.Count == 0)
            {
                ov.PauseReason = "dayMissing";
                review.Add(ov);
                continue;
            }

            if (matchingDays.Count > 1)
            {
                ov.PauseReason = "ambiguousDay";
                review.Add(ov);
                continue;
            }

            var (day, dayIdx) = matchingDays[0];
            if (!CountsEqual(day, ov.BaselineDay))
            {
                ov.PauseReason = "dayChanged";
                review.Add(ov);
                continue;
            }

            var hiddenAllocs = ov.Allocations.Where(a => ov.HiddenAllocationIds.Contains(a.Id)).ToList();
            if (hiddenAllocs.Count == 0)
            {
                ov.PauseReason = "invalidAllocation";
                review.Add(ov);
                continue;
            }

            // Validate subject subtractions before mutating
            var subjectDeltas = new List<(int SubjectIndex, AbsenceCategory Category)>();
            bool invalid = false;

            if (effectiveSubjects.Count > 0)
            {
                foreach (var alloc in hiddenAllocs)
                {
                    var key = NormalizeKey(alloc.SubjectName);
                    var subIdx = effectiveSubjects.FindIndex(s => string.Equals(NormalizeKey(s.SubjectName), key, StringComparison.Ordinal));
                    if (subIdx < 0)
                    {
                        ov.PauseReason = "subjectMappingChanged";
                        invalid = true;
                        break;
                    }
                    subjectDeltas.Add((subIdx, alloc.Category));
                }
            }

            if (invalid)
            {
                review.Add(ov);
                continue;
            }

            // Test dry-run on cloned subjects
            var testSubjects = effectiveSubjects.Select(s => s.Clone()).ToList();
            foreach (var (subIdx, cat) in subjectDeltas)
            {
                if (!TrySubtractCategory(testSubjects[subIdx], cat))
                {
                    ov.PauseReason = "insufficientSubjectCount";
                    invalid = true;
                    break;
                }
            }

            if (invalid)
            {
                review.Add(ov);
                continue;
            }

            // Commit day & subject decrements
            var clonedDay = day.Clone();
            foreach (var alloc in hiddenAllocs)
            {
                if (!TrySubtractDayCategory(clonedDay, alloc.Category))
                {
                    ov.PauseReason = "invalidAllocation";
                    invalid = true;
                    break;
                }
            }

            if (invalid)
            {
                review.Add(ov);
                continue;
            }

            effectiveDays[dayIdx] = clonedDay;
            effectiveSubjects = testSubjects;
            active.Add(ov);
            if (ov.HidesEntireDay)
                fullyHiddenDateKeys.Add(ov.DateKey);
        }

        var visibleDays = effectiveDays
            .Where(d => !fullyHiddenDateKeys.Contains(d.DateKey) && d.Total > 0)
            .ToList();

        var projected = new AbsenceResponse
        {
            PercentageThreshold = rawResponse.PercentageThreshold,
            Absences = visibleDays,
            AbsencesPerSubject = effectiveSubjects
        };

        return new ProjectedAbsenceResult(projected, active, review);
    }

    private static bool CountsEqual(AbsenceDay a, AbsenceDay b) =>
        a.Unsolved == b.Unsolved &&
        a.Ok == b.Ok &&
        a.Missed == b.Missed &&
        a.Late == b.Late &&
        a.Soon == b.Soon &&
        a.School == b.School &&
        a.DistanceTeaching == b.DistanceTeaching;

    private static bool TrySubtractDayCategory(AbsenceDay day, AbsenceCategory cat)
    {
        switch (cat)
        {
            case AbsenceCategory.Unsolved: if (day.Unsolved <= 0) return false; day.Unsolved--; return true;
            case AbsenceCategory.Ok: if (day.Ok <= 0) return false; day.Ok--; return true;
            case AbsenceCategory.Missed: if (day.Missed <= 0) return false; day.Missed--; return true;
            case AbsenceCategory.Late: if (day.Late <= 0) return false; day.Late--; return true;
            case AbsenceCategory.Soon: if (day.Soon <= 0) return false; day.Soon--; return true;
            case AbsenceCategory.School: if (day.School <= 0) return false; day.School--; return true;
            case AbsenceCategory.DistanceTeaching: if (day.DistanceTeaching <= 0) return false; day.DistanceTeaching--; return true;
            default: return false;
        }
    }

    private static bool TrySubtractCategory(AbsencePerSubject sub, AbsenceCategory cat)
    {
        if (cat.ContributesToBase())
        {
            if (sub.Base <= 0) return false;
            sub.Base--;
            return true;
        }
        switch (cat)
        {
            case AbsenceCategory.Late: if (sub.Late <= 0) return false; sub.Late--; return true;
            case AbsenceCategory.Soon: if (sub.Soon <= 0) return false; sub.Soon--; return true;
            case AbsenceCategory.School: if (sub.School <= 0) return false; sub.School--; return true;
            case AbsenceCategory.DistanceTeaching: if (sub.DistanceTeaching <= 0) return false; sub.DistanceTeaching--; return true;
            default: return false;
        }
    }

    public static string NormalizeKey(string text)
    {
        var norm = (text ?? string.Empty).Trim().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(norm.Length);
        foreach (var c in norm)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(char.ToLowerInvariant(c));
        }
        return sb.ToString();
    }
}
