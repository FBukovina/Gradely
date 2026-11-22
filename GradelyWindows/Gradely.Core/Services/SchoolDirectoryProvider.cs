using System.Collections.Concurrent;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using Gradely.Core.Models;
using Gradely.Core.Stores;

namespace Gradely.Core.Services;

public sealed class SchoolDirectoryProvider
{
    private const string DirectoryCachePath = "cache/school-directory-v2.json";
    private const string BaseEndpoint = "https://sluzby.bakalari.cz/api/v1/municipality";
    private const int MaxConcurrentTownRequests = 8;

    private readonly HttpClient _http;
    private readonly JsonFileStore _store;
    private readonly JsonSerializerOptions _jsonOptions = new() { PropertyNameCaseInsensitive = true };

    public SchoolDirectoryProvider(JsonFileStore store, HttpClient? httpClient = null)
    {
        _store = store;
        _http = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
        _http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    }

    public CachedSchoolDirectory? LoadCached() => _store.Load<CachedSchoolDirectory>(DirectoryCachePath);

    public async Task<List<SchoolDirectorySchool>> GetSchoolsAsync(bool forceRefresh = false, CancellationToken ct = default)
    {
        var cached = LoadCached();
        if (!forceRefresh && cached is { IsFresh: true, Schools.Count: > 0 })
            return cached.Schools;

        try
        {
            var fresh = await FetchDirectoryAsync(cached, ct);
            if (fresh.Count > 0) return fresh;
        }
        catch
        {
            if (cached is { Schools.Count: > 0 })
                return cached.Schools;
            throw;
        }

        return cached?.Schools ?? [];
    }

    private async Task<List<SchoolDirectorySchool>> FetchDirectoryAsync(CachedSchoolDirectory? cached, CancellationToken ct)
    {
        using var batchCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        batchCts.CancelAfter(TimeSpan.FromSeconds(25));

        var rawTownsJson = await _http.GetStringAsync(BaseEndpoint, batchCts.Token);
        var towns = (JsonSerializer.Deserialize<List<MunicipalityDto>>(rawTownsJson, _jsonOptions) ?? [])
            .Where(t => !string.IsNullOrWhiteSpace(t.Name) && t.SchoolCount > 0)
            .ToList();

        if (towns.Count == 0)
            return cached?.Schools ?? [];

        int expectedTotal = towns.Sum(t => t.SchoolCount);
        int successfulExpected = 0;
        var bag = new ConcurrentBag<SchoolDirectorySchool>();
        using var gate = new SemaphoreSlim(MaxConcurrentTownRequests);

        var tasks = towns.Select(async town =>
        {
            await gate.WaitAsync(batchCts.Token);
            try
            {
                for (int attempt = 1; attempt <= 2; attempt++)
                {
                    try
                    {
                        var url = $"{BaseEndpoint}?name={Uri.EscapeDataString(town.Name)}";
                        var json = await _http.GetStringAsync(url, batchCts.Token);
                        var dto = JsonSerializer.Deserialize<MunicipalitySchoolsDto>(json, _jsonOptions);
                        if (dto?.Schools is not null)
                        {
                            foreach (var s in dto.Schools)
                            {
                                if (string.IsNullOrWhiteSpace(s.Name) || string.IsNullOrWhiteSpace(s.SchoolUrl)) continue;
                                bag.Add(new SchoolDirectorySchool(s.Id, s.Name.Trim(), town.Name.Trim(), s.SchoolUrl.Trim()));
                            }
                            Interlocked.Add(ref successfulExpected, town.SchoolCount);
                        }
                        break;
                    }
                    catch when (attempt == 1 && !batchCts.IsCancellationRequested)
                    {
                        await Task.Delay(250 * attempt, batchCts.Token);
                    }
                    catch
                    {
                        break;
                    }
                }
            }
            finally
            {
                gate.Release();
            }
        });

        try
        {
            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Batch deadline reached — proceed with coverage check
        }

        var fetched = bag.ToList();
        double requestCoverage = expectedTotal > 0 ? (double)successfulExpected / expectedTotal : 0;
        double responseCoverage = expectedTotal > 0 ? (double)fetched.Count / expectedTotal : 0;

        var merged = DeduplicateAndSort((cached?.Schools ?? []).Concat(fetched));
        bool hasTrustedCache = cached is { FormatVersion: CachedSchoolDirectory.CurrentFormatVersion, Schools.Count: > 0 };
        bool healthy = hasTrustedCache
            ? (requestCoverage >= 0.90 && responseCoverage >= 0.70)
            : (requestCoverage >= 0.98 && responseCoverage >= 0.90);

        if (healthy || (!hasTrustedCache && merged.Count > 50))
        {
            _store.Save(DirectoryCachePath, new CachedSchoolDirectory
            {
                FormatVersion = CachedSchoolDirectory.CurrentFormatVersion,
                FetchedAt = DateTimeOffset.UtcNow,
                Schools = merged
            });
        }

        return merged;
    }

    private static List<SchoolDirectorySchool> DeduplicateAndSort(IEnumerable<SchoolDirectorySchool> schools)
    {
        var csComparer = StringComparer.Create(CultureInfo.GetCultureInfo("cs-CZ"), ignoreCase: true);
        var byUrl = new Dictionary<string, SchoolDirectorySchool>(StringComparer.OrdinalIgnoreCase);

        foreach (var s in schools)
        {
            var key = s.SchoolUrl.Trim().TrimEnd('/');
            byUrl[key] = s;
        }

        return byUrl.Values
            .OrderBy(s => s.Town, csComparer)
            .ThenBy(s => s.Name, csComparer)
            .ToList();
    }
}
