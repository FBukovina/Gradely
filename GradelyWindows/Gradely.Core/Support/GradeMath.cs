using System.Globalization;
using System.Text;
using Gradely.Core.Models;

namespace Gradely.Core.Support;

public static class GradeMath
{
    public const int MaximumHypotheticalGrades = 10;
    private const int MaximumAverageInferenceGroups = 4;

    private static readonly Dictionary<string, double> ModifierMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["1+"] = 1.3, ["1-"] = 1.7,
        ["2+"] = 2.3, ["2-"] = 2.7,
        ["3+"] = 3.3, ["3-"] = 3.7,
        ["4+"] = 4.3, ["4-"] = 4.7,
        ["5+"] = 5.3, ["5-"] = 5.7
    };

    public static double? ParseMarkValue(string? markText)
    {
        if (string.IsNullOrWhiteSpace(markText)) return null;
        var trimmed = markText.Trim();
        if (ModifierMap.TryGetValue(trimmed, out var mapped))
            return mapped;

        var normalized = trimmed.Replace(',', '.');
        if (double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture, out var val) && double.IsFinite(val))
            return val;

        return null;
    }

    public static double? ParseAverageText(string? averageText)
    {
        if (string.IsNullOrWhiteSpace(averageText)) return null;
        var normalized = averageText.Trim().Replace(',', '.');
        return double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture, out var val) && double.IsFinite(val)
            ? val
            : null;
    }

    public static string FormatAverage(double? value, CultureInfo? culture = null)
    {
        if (value is null || !double.IsFinite(value.Value)) return "–";
        return value.Value.ToString("F2", culture ?? CultureInfo.CurrentCulture);
    }

    public static string FormatWeight(double weight)
    {
        var rounded = Math.Round(weight);
        if (Math.Abs(weight - rounded) < 1e-6)
            return ((int)rounded).ToString(CultureInfo.InvariantCulture);
        return weight.ToString("G", CultureInfo.InvariantCulture);
    }

    public static GradeBand BandForAverage(double? average)
    {
        if (average is null || !double.IsFinite(average.Value)) return GradeBand.Neutral;
        if (average.Value <= 1.5) return GradeBand.Excellent;
        if (average.Value <= 2.5) return GradeBand.Good;
        if (average.Value <= 3.5) return GradeBand.Average;
        return GradeBand.Poor;
    }

    public static GradeBand BandForMark(Mark mark)
    {
        if (mark.IsPoints) return GradeBand.Excellent;
        return BandForMarkText(mark.MarkText);
    }

    public static GradeBand BandForMarkText(string? markText)
    {
        var t = markText?.Trim().ToUpperInvariant() ?? string.Empty;
        return t switch
        {
            "1" or "1+" or "1-" => GradeBand.Excellent,
            "2" or "2+" or "2-" => GradeBand.Good,
            "3" or "3+" or "3-" => GradeBand.Average,
            "4" or "4+" or "4-" or "5" or "5+" or "5-" => GradeBand.Poor,
            _ => ParseMarkValue(t) is double v and >= 1.0 and <= 5.7 ? BandForAverage(v) : GradeBand.Neutral
        };
    }

    public static PreparedGradeCalculation Prepare(SubjectMarks subject)
    {
        var issues = GradeCalculationIssues.None;
        var officialAvg = ParseAverageText(subject.AverageText);

        if (subject.PointsOnly)
        {
            return new PreparedGradeCalculation
            {
                SubjectId = subject.Id,
                Marks = [],
                WeightedSum = 0,
                TotalWeight = 0,
                OfficialAverage = officialAvg,
                Issues = subject.Marks.Count > 0 ? GradeCalculationIssues.ExcludedMarks : GradeCalculationIssues.None
            };
        }

        // Step 1: Deduplicate by EffectiveId
        var deduped = new List<(string Id, Mark Mark)>();
        var groupedById = subject.Marks.GroupBy(m => m.EffectiveId, StringComparer.Ordinal);
        foreach (var group in groupedById)
        {
            var items = group.ToList();
            if (items.Count == 1)
            {
                deduped.Add((group.Key, items[0]));
            }
            else
            {
                issues |= GradeCalculationIssues.DuplicateMarks;
                var hashes = items.Select(m => m.CanonicalHash()).Distinct(StringComparer.Ordinal).ToList();
                if (hashes.Count > 1)
                {
                    issues |= GradeCalculationIssues.ConflictingDuplicateIds;
                    // Exclude all conflicting marks
                }
                else
                {
                    deduped.Add((group.Key, items[0]));
                }
            }
        }

        // Step 2: Filter valid numeric grades
        var candidates = new List<(string Id, Mark Mark, double Value, string? Label)>();
        foreach (var (id, mark) in deduped)
        {
            if (!mark.HasStableProviderId)
                issues |= GradeCalculationIssues.MissingMarkIdentifiers;

            if (mark.IsPoints || string.Equals(mark.Type, "unsupported", StringComparison.OrdinalIgnoreCase))
            {
                issues |= GradeCalculationIssues.ExcludedMarks;
                continue;
            }

            var val = ParseMarkValue(mark.MarkText);
            if (val is null || val.Value < 1.0 || val.Value > 5.7)
            {
                issues |= GradeCalculationIssues.ExcludedMarks;
                continue;
            }

            if (mark.Weight.HasValue && (!double.IsFinite(mark.Weight.Value) || mark.Weight.Value <= 0))
            {
                issues |= GradeCalculationIssues.InvalidWeights;
                continue;
            }

            candidates.Add((id, mark, val.Value, PrimaryLabel(mark)));
        }

        if (candidates.Count == 0)
        {
            return new PreparedGradeCalculation
            {
                SubjectId = subject.Id,
                Marks = [],
                WeightedSum = 0,
                TotalWeight = 0,
                OfficialAverage = officialAvg,
                Issues = issues
            };
        }

        // Step 3: 3-Tier weight resolution
        var resolvedWeights = new Dictionary<string, ResolvedWeight>(StringComparer.Ordinal);

        // Tier 1: Explicit weights
        var labelExplicitWeights = new Dictionary<string, HashSet<double>>(StringComparer.Ordinal);
        foreach (var c in candidates)
        {
            if (c.Mark.Weight is double w and > 0)
            {
                resolvedWeights[c.Id] = new ResolvedWeight(w, WeightSource.Explicit);
                if (c.Label is not null)
                {
                    if (!labelExplicitWeights.TryGetValue(c.Label, out var set))
                    {
                        set = [];
                        labelExplicitWeights[c.Label] = set;
                    }
                    set.Add(w);
                }
            }
        }

        // Tier 2: Infer from same primary label when unique explicit weight exists
        foreach (var c in candidates)
        {
            if (resolvedWeights.ContainsKey(c.Id)) continue;
            if (c.Label is not null &&
                labelExplicitWeights.TryGetValue(c.Label, out var explicitSet) &&
                explicitSet.Count == 1)
            {
                resolvedWeights[c.Id] = new ResolvedWeight(explicitSet.First(), WeightSource.Inferred);
            }
        }

        // Tier 3: Backtracking integer weight solver (1..10) against official average
        var unresolved = candidates.Where(c => !resolvedWeights.ContainsKey(c.Id)).ToList();
        if (unresolved.Count > 0 && officialAvg.HasValue)
        {
            var groups = unresolved
                .GroupBy(c => c.Label ?? $"__id_{c.Id}", StringComparer.Ordinal)
                .Select(g => new UnresolvedGroup(g.Key, g.Select(x => (x.Id, x.Value)).ToList()))
                .ToList();

            if (groups.Count is >= 1 and <= MaximumAverageInferenceGroups)
            {
                double knownWeightedSum = 0;
                double knownWeight = 0;
                foreach (var c in candidates)
                {
                    if (resolvedWeights.TryGetValue(c.Id, out var rw))
                    {
                        knownWeightedSum += c.Value * rw.Value;
                        knownWeight += rw.Value;
                    }
                }

                var solution = SolveUniqueIntegerWeights(groups, knownWeightedSum, knownWeight, officialAvg.Value);
                if (solution is not null)
                {
                    for (int i = 0; i < groups.Count; i++)
                    {
                        var w = solution[i];
                        foreach (var (markId, _) in groups[i].Items)
                            resolvedWeights[markId] = new ResolvedWeight(w, WeightSource.Inferred);
                    }
                }
            }
        }

        // Tier 4: Fallback weight = 1.0
        var preparedMarks = new List<PreparedMark>(candidates.Count);
        double totalWeightedSum = 0;
        double totalWeight = 0;

        foreach (var c in candidates)
        {
            if (!resolvedWeights.TryGetValue(c.Id, out var rw))
            {
                rw = new ResolvedWeight(1.0, WeightSource.Fallback);
                issues |= GradeCalculationIssues.MissingWeights;
            }
            totalWeightedSum += c.Value * rw.Value;
            totalWeight += rw.Value;
            preparedMarks.Add(new PreparedMark(c.Id, c.Mark, c.Value, rw, c.Mark.ParsedDate));
        }

        var calcAvg = totalWeight > 0 ? totalWeightedSum / totalWeight : (double?)null;
        if (calcAvg.HasValue && officialAvg.HasValue)
        {
            if (Math.Round(calcAvg.Value * 100.0) != Math.Round(officialAvg.Value * 100.0))
                issues |= GradeCalculationIssues.InconsistentOfficialAverage;
        }

        return new PreparedGradeCalculation
        {
            SubjectId = subject.Id,
            Marks = preparedMarks,
            WeightedSum = totalWeightedSum,
            TotalWeight = totalWeight,
            OfficialAverage = officialAvg,
            Issues = issues
        };
    }

    public static GradeSimulationResult? Simulate(PreparedGradeCalculation prepared, IReadOnlyList<HypotheticalGrade> hypotheticals)
    {
        if (hypotheticals.Count == 0) return null;
        var slice = hypotheticals.Take(MaximumHypotheticalGrades).ToList();
        double sum = prepared.WeightedSum;
        double weight = prepared.TotalWeight;
        foreach (var h in slice)
        {
            if (h.Value < 1.0 || h.Value > 5.7 || h.Weight < 1 || h.Weight > 10) continue;
            sum += h.Value * h.Weight;
            weight += h.Weight;
        }
        if (weight <= 0) return null;
        var estimated = sum / weight;
        var baseline = prepared.CalculatedAverage;
        var diff = baseline.HasValue ? estimated - baseline.Value : (double?)null;
        return new GradeSimulationResult(baseline, estimated, diff, false);
    }

    public static double? OverallAverage(IEnumerable<PreparedGradeCalculation> subjects)
    {
        var avgs = subjects.Select(s => s.DisplayAverage).Where(a => a.HasValue).Select(a => a!.Value).ToList();
        return avgs.Count > 0 ? avgs.Average() : null;
    }

    public static List<AverageTimelineEntry> BuildTimeline(PreparedGradeCalculation prepared)
    {
        var dated = prepared.Marks
            .Where(m => m.Date.HasValue)
            .OrderBy(m => m.Date!.Value)
            .ThenBy(m => m.MarkId, StringComparer.Ordinal)
            .ToList();

        var result = new List<AverageTimelineEntry>(dated.Count);
        double wSum = 0;
        double totalW = 0;

        foreach (var m in dated)
        {
            totalW += m.Weight.Value;
            wSum += m.Value * m.Weight.Value;
            result.Add(new AverageTimelineEntry(
                m.MarkId,
                m.Date!.Value,
                m.Value,
                m.Weight.Value,
                wSum / totalW,
                BandForAverage(m.Value)));
        }

        return result;
    }

    public static double PriorityFocusScore(PreparedGradeCalculation prepared, bool hasUpcomingEvents = false)
    {
        var avg = prepared.DisplayAverage ?? 0.0;
        var timeline = BuildTimeline(prepared);
        double trendPenalty = 0;
        if (timeline.Count >= 3)
        {
            var span = timeline[^1].Date - timeline[0].Date;
            var delta = timeline[^1].RunningAverage - timeline[0].RunningAverage;
            if (span.TotalDays >= 7 && delta > 0.15)
                trendPenalty = delta * 2.0;
        }
        return avg + trendPenalty + (hasUpcomingEvents ? 2.0 : 0.0);
    }

    private sealed record UnresolvedGroup(string Key, List<(string Id, double Value)> Items)
    {
        public double SumOfValues { get; } = Items.Sum(x => x.Value);
        public int Count => Items.Count;
    }

    private static int[]? SolveUniqueIntegerWeights(
        List<UnresolvedGroup> groups,
        double knownWeightedSum,
        double knownWeight,
        double targetAverage)
    {
        var targetCents = Math.Round(targetAverage * 100.0);
        int[] current = new int[groups.Count];
        int[]? uniqueMatch = null;
        int matchCount = 0;

        void Dfs(int idx, double sum, double weight)
        {
            if (matchCount > 1) return;
            if (idx == groups.Count)
            {
                if (weight <= 0) return;
                if (Math.Round((sum / weight) * 100.0) == targetCents)
                {
                    matchCount++;
                    if (matchCount == 1)
                        uniqueMatch = (int[])current.Clone();
                }
                return;
            }

            var g = groups[idx];
            for (int w = 1; w <= 10; w++)
            {
                current[idx] = w;
                Dfs(idx + 1, sum + g.SumOfValues * w, weight + g.Count * w);
                if (matchCount > 1) return;
            }
        }

        Dfs(0, knownWeightedSum, knownWeight);
        return matchCount == 1 ? uniqueMatch : null;
    }

    private static string? PrimaryLabel(Mark mark)
    {
        foreach (var raw in new[] { mark.TypeNote, mark.Type, mark.Caption })
        {
            if (string.IsNullOrWhiteSpace(raw)) continue;
            var folded = NormalizeLabel(raw);
            if (!string.IsNullOrEmpty(folded)) return folded;
        }
        return null;
    }

    private static string NormalizeLabel(string raw)
    {
        var norm = raw.Trim().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(norm.Length);
        bool prevSpace = false;
        foreach (var c in norm)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsWhiteSpace(c))
            {
                if (!prevSpace)
                {
                    sb.Append(' ');
                    prevSpace = true;
                }
            }
            else
            {
                sb.Append(char.ToLowerInvariant(c));
                prevSpace = false;
            }
        }
        return sb.ToString().Trim();
    }
}
