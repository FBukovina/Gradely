using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

public sealed class MunicipalityDto
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("schoolCount")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int SchoolCount { get; set; }
}

public sealed class MunicipalitySchoolsDto
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("schools")]
    public List<MunicipalitySchoolItemDto> Schools { get; set; } = [];
}

public sealed class MunicipalitySchoolItemDto
{
    [JsonPropertyName("id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("schoolUrl")]
    public string SchoolUrl { get; set; } = string.Empty;
}

public sealed record SchoolDirectorySchool(
    string Id,
    string Name,
    string Town,
    string SchoolUrl
)
{
    public string DisplaySubtitle => string.IsNullOrWhiteSpace(Town)
        ? SchoolUrl.TrimEnd('/')
        : $"{Town} · {SchoolUrl.TrimEnd('/')}";
}

public sealed class CachedSchoolDirectory
{
    public const int CurrentFormatVersion = 2;
    public static readonly TimeSpan DefaultMaxAge = TimeSpan.FromDays(7);

    public int FormatVersion { get; set; } = CurrentFormatVersion;
    public DateTimeOffset FetchedAt { get; set; }
    public List<SchoolDirectorySchool> Schools { get; set; } = [];

    [JsonIgnore]
    public bool IsFresh => FormatVersion == CurrentFormatVersion && DateTimeOffset.UtcNow - FetchedAt <= DefaultMaxAge;
}
