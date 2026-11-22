namespace Gradely.Core.Models;

public enum GradeBand
{
    Excellent,
    Good,
    Average,
    Poor,
    Neutral
}

public enum WeightSource
{
    Explicit,
    Inferred,
    Fallback
}

public enum GradeCalculationConfidence
{
    Exact,
    Estimated,
    Unavailable
}

[Flags]
public enum GradeCalculationIssues
{
    None = 0,
    DuplicateMarks = 1 << 0,
    ConflictingDuplicateIds = 1 << 1,
    ExcludedMarks = 1 << 2,
    InvalidWeights = 1 << 3,
    MissingWeights = 1 << 4,
    MissingMarkIdentifiers = 1 << 5,
    InconsistentOfficialAverage = 1 << 6
}

public sealed record ResolvedWeight(double Value, WeightSource Source);

public sealed record PreparedMark(
    string MarkId,
    Mark SourceMark,
    double Value,
    ResolvedWeight Weight,
    DateTimeOffset? Date
);

public sealed class PreparedGradeCalculation
{
    public string SubjectId { get; init; } = string.Empty;
    public IReadOnlyList<PreparedMark> Marks { get; init; } = [];
    public double WeightedSum { get; init; }
    public double TotalWeight { get; init; }
    public double? CalculatedAverage => TotalWeight > 0 ? WeightedSum / TotalWeight : null;
    public double? OfficialAverage { get; init; }
    public double? DisplayAverage => OfficialAverage ?? CalculatedAverage;
    public GradeCalculationIssues Issues { get; init; }
    public GradeCalculationConfidence Confidence =>
        Marks.Count == 0
            ? GradeCalculationConfidence.Unavailable
            : (Issues == GradeCalculationIssues.None ? GradeCalculationConfidence.Exact : GradeCalculationConfidence.Estimated);

    public double? AverageWithout(string markId)
    {
        var target = Marks.FirstOrDefault(m => string.Equals(m.MarkId, markId, StringComparison.Ordinal));
        if (target is null) return CalculatedAverage;
        var remWeight = TotalWeight - target.Weight.Value;
        if (remWeight <= 1e-9) return null;
        return (WeightedSum - target.Value * target.Weight.Value) / remWeight;
    }

    public double? ImpactOf(string markId)
    {
        if (CalculatedAverage is null) return null;
        var without = AverageWithout(markId);
        return without.HasValue ? CalculatedAverage.Value - without.Value : null;
    }

    public ResolvedWeight? ResolvedWeightFor(string markId) =>
        Marks.FirstOrDefault(m => string.Equals(m.MarkId, markId, StringComparison.Ordinal))?.Weight;
}

public sealed record HypotheticalGrade(Guid Id, string MarkText, double Value, int Weight);

public sealed record GradeSimulationResult(
    double? BaselineAverage,
    double EstimatedAverage,
    double? Difference,
    bool IsRemotePrediction
);

public sealed record AverageTimelineEntry(
    string MarkId,
    DateTimeOffset Date,
    double MarkValue,
    double Weight,
    double RunningAverage,
    GradeBand Band
);
