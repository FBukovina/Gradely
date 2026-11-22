namespace Gradely.Core.Support;

public enum UrlNormalizationErrorKind
{
    Empty,
    Invalid,
    Insecure,
    InvalidEduPageHost
}

public sealed class UrlNormalizationException : Exception
{
    public UrlNormalizationErrorKind Kind { get; }

    public UrlNormalizationException(UrlNormalizationErrorKind kind, string message) : base(message)
    {
        Kind = kind;
    }
}

public static class SchoolUrlNormalizer
{
    public static Uri NormalizeBakalariBaseUrl(string raw)
    {
        var trimmed = raw?.Trim() ?? string.Empty;
        if (string.IsNullOrEmpty(trimmed))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Empty, "Enter your school URL.");

        if (string.Equals(trimmed, "demo", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, "demo.gradely.app", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, "https://demo.gradely.app", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, "https://demo.gradely.app/", StringComparison.OrdinalIgnoreCase))
        {
            return new Uri("https://demo.gradely.app/");
        }

        if (!trimmed.Contains("://", StringComparison.Ordinal))
            trimmed = "https://" + trimmed;

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) || string.IsNullOrWhiteSpace(uri.Host))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Invalid, "The school URL is not valid.");

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Insecure, "School URL must use HTTPS.");

        var builder = new UriBuilder(uri)
        {
            Query = string.Empty,
            Fragment = string.Empty
        };

        var path = builder.Path;
        if (path.EndsWith("/next/login", StringComparison.OrdinalIgnoreCase))
            path = path[..^"/next/login".Length];
        else if (path.EndsWith("/login", StringComparison.OrdinalIgnoreCase))
            path = path[..^"/login".Length];

        if (!path.EndsWith('/'))
            path += "/";

        builder.Path = path;
        return builder.Uri;
    }

    public static Uri NormalizeEduPageBaseUrl(string raw)
    {
        var trimmed = raw?.Trim() ?? string.Empty;
        if (string.IsNullOrEmpty(trimmed))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Empty, "Enter your EduPage school subdomain or URL.");

        if (!trimmed.Contains("://", StringComparison.Ordinal))
        {
            trimmed = trimmed.Contains('.')
                ? "https://" + trimmed
                : $"https://{trimmed}.edupage.org";
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) || string.IsNullOrWhiteSpace(uri.Host))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Invalid, "The EduPage school address is not valid.");

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.Insecure, "EduPage URL must use HTTPS.");

        var host = uri.Host.ToLowerInvariant();
        if (host != "edupage.org" && !host.EndsWith(".edupage.org", StringComparison.Ordinal))
            throw new UrlNormalizationException(UrlNormalizationErrorKind.InvalidEduPageHost, "Address must be an edupage.org domain.");

        var builder = new UriBuilder(uri)
        {
            Path = "/",
            Query = string.Empty,
            Fragment = string.Empty
        };
        return builder.Uri;
    }

    public static string DisplayString(Uri uri) => uri.AbsoluteUri.TrimEnd('/');
    public static string DisplayString(string raw) => raw.TrimEnd('/');
}
