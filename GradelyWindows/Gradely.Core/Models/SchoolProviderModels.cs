using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SchoolProvider
{
    Bakalari,
    EduPage
}

public static class SchoolProviderExtensions
{
    public static string DisplayName(this SchoolProvider provider) => provider switch
    {
        SchoolProvider.Bakalari => "Bakaláři",
        SchoolProvider.EduPage => "EduPage",
        _ => provider.ToString()
    };

    public static bool SupportsParentProfiles(this SchoolProvider provider) => provider == SchoolProvider.EduPage;
    public static bool SupportsTwoFactorAuthentication(this SchoolProvider provider) => provider == SchoolProvider.EduPage;
    public static bool SupportsRemoteWhatIf(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
    public static bool ExposesAbsenceThreshold(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
    public static bool SupportsHomework(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
    public static bool SupportsKomens(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
    public static bool SupportsReportCard(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
    public static bool SupportsPermanentTimetable(this SchoolProvider provider) => provider == SchoolProvider.Bakalari;
}

public sealed record SchoolStudentProfile(
    string Id,
    string FullName,
    string? ClassId = null,
    string? ClassName = null
);

public sealed record StoredSession(
    SchoolProvider Provider,
    string BaseUrl,
    string Username,
    string AccessToken,
    string? RefreshToken,
    DateTimeOffset ExpiresAt,
    string? UserId = null,
    string? SchoolName = null,
    SchoolStudentProfile? ActiveStudent = null,
    IReadOnlyList<SchoolStudentProfile>? AvailableStudents = null,
    string? EduPageGsecHash = null
)
{
    public bool IsExpired => Provider == SchoolProvider.Bakalari && ExpiresAt <= DateTimeOffset.UtcNow.AddSeconds(60);

    public string ScopeKey
    {
        get
        {
            var student = ActiveStudent?.Id ?? UserId ?? Username;
            return $"{Provider.ToString().ToLowerInvariant()}:{BaseUrl.TrimEnd('/').ToLowerInvariant()}:{student.ToLowerInvariant()}";
        }
    }
}

public sealed record StoredCredentials(
    SchoolProvider Provider,
    string BaseUrl,
    string Username,
    string Password
);

public sealed record EduPageTwoFactorChallenge(
    string BaseUrl,
    string Username,
    string Password,
    string SessionId,
    string CsrfToken,
    string AuthenticationToken,
    string AuthenticationEndpoint
);

public sealed record EduPagePendingParentSession(
    string BaseUrl,
    string Username,
    string Password,
    string SessionId,
    string UserId,
    string? SchoolName,
    string? GsecHash,
    IReadOnlyList<SchoolStudentProfile> Students
);

public sealed class SchoolLoginOutcome
{
    public StoredSession? Session { get; init; }
    public EduPageTwoFactorChallenge? TwoFactorChallenge { get; init; }
    public EduPagePendingParentSession? PendingParentSession { get; init; }

    public bool IsSignedIn => Session is not null;
    public bool RequiresTwoFactor => TwoFactorChallenge is not null;
    public bool RequiresStudentSelection => PendingParentSession is not null;
}

public sealed class SchoolApiException : Exception
{
    public int? StatusCode { get; }
    public bool IsAuthenticationFailure { get; }
    public bool RequiresTwoFactor { get; }
    public bool RequiresCaptcha { get; }

    public SchoolApiException(
        string message,
        int? statusCode = null,
        bool isAuthenticationFailure = false,
        bool requiresTwoFactor = false,
        bool requiresCaptcha = false,
        Exception? innerException = null)
        : base(message, innerException)
    {
        StatusCode = statusCode;
        IsAuthenticationFailure = isAuthenticationFailure;
        RequiresTwoFactor = requiresTwoFactor;
        RequiresCaptcha = requiresCaptcha;
    }
}
