using System.Globalization;
using System.Text;
using Gradely.Core.Models;

namespace Gradely.Core.Support;

public static class SchoolDirectorySearch
{
    private static readonly CultureInfo CzechCulture = CultureInfo.GetCultureInfo("cs-CZ");

    public static List<SchoolDirectorySchool> Search(
        IReadOnlyList<SchoolDirectorySchool> schools,
        string query,
        int limit = 8)
    {
        var normalizedQuery = Normalize(query);
        if (string.IsNullOrEmpty(normalizedQuery)) return [];

        var tokens = normalizedQuery.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length == 0) return [];

        var matches = new List<(int Score, SchoolDirectorySchool School)>();

        foreach (var school in schools)
        {
            var name = Normalize(school.Name);
            var town = Normalize(school.Town);
            var url = Normalize(school.SchoolUrl);
            var acronym = BuildAcronym(name);
            var searchable = $"{name} {town} {url} {acronym}";

            if (!tokens.All(t => searchable.Contains(t, StringComparison.Ordinal)))
                continue;

            int score;
            if (name == normalizedQuery) score = 0;
            else if (acronym == normalizedQuery || acronym.StartsWith(normalizedQuery, StringComparison.Ordinal)) score = 5;
            else if (name.StartsWith(normalizedQuery, StringComparison.Ordinal)) score = 10;
            else if (town.StartsWith(normalizedQuery, StringComparison.Ordinal)) score = 20;
            else if (name.Contains(normalizedQuery, StringComparison.Ordinal)) score = 30;
            else if (town.Contains(normalizedQuery, StringComparison.Ordinal)) score = 40;
            else if (url.Contains(normalizedQuery, StringComparison.Ordinal)) score = 50;
            else score = 60;

            matches.Add((score, school));
        }

        return matches
            .OrderBy(m => m.Score)
            .ThenBy(m => m.School.Town, StringComparer.Create(CzechCulture, ignoreCase: true))
            .ThenBy(m => m.School.Name, StringComparer.Create(CzechCulture, ignoreCase: true))
            .Take(limit)
            .Select(m => m.School)
            .ToList();
    }

    public static string Normalize(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return string.Empty;
        var decomposed = input.Trim().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        bool prevSpace = false;

        foreach (var c in decomposed)
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
                sb.Append(char.ToLower(c, CzechCulture));
                prevSpace = false;
            }
        }
        return sb.ToString().Trim();
    }

    private static string BuildAcronym(string normalizedName)
    {
        var sb = new StringBuilder();
        bool inWord = false;
        foreach (var c in normalizedName)
        {
            if (char.IsLetterOrDigit(c))
            {
                if (!inWord)
                {
                    sb.Append(c);
                    inWord = true;
                }
            }
            else
            {
                inWord = false;
            }
        }
        return sb.ToString();
    }
}
