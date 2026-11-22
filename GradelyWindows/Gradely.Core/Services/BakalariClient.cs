using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Gradely.Core.Models;

namespace Gradely.Core.Services;

public sealed class BakalariClient
{
    private readonly HttpClient _http;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public BakalariClient(HttpClient? httpClient = null)
    {
        _http = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(25) };
    }

    public async Task<LoginResponse> LoginAsync(Uri baseUrl, string username, string password, CancellationToken ct = default)
    {
        var form = new Dictionary<string, string>
        {
            ["client_id"] = "ANDR",
            ["grant_type"] = "password",
            ["username"] = username,
            ["password"] = password
        };
        return await SendFormAsync<LoginResponse>(new Uri(baseUrl, "api/login"), form, ct);
    }

    public async Task<LoginResponse> RefreshTokenAsync(Uri baseUrl, string refreshToken, CancellationToken ct = default)
    {
        var form = new Dictionary<string, string>
        {
            ["client_id"] = "ANDR",
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken
        };
        return await SendFormAsync<LoginResponse>(new Uri(baseUrl, "api/login"), form, ct);
    }

    public Task<UserResponse> GetUserAsync(Uri baseUrl, string accessToken, CancellationToken ct = default) =>
        SendAuthenticatedJsonAsync<UserResponse>(HttpMethod.Get, new Uri(baseUrl, "api/3/user"), accessToken, null, ct);

    public Task<MarksResponse> GetMarksAsync(Uri baseUrl, string accessToken, CancellationToken ct = default) =>
        SendAuthenticatedJsonAsync<MarksResponse>(HttpMethod.Get, new Uri(baseUrl, "api/3/marks"), accessToken, null, ct);

    public Task<AbsenceResponse> GetAbsenceAsync(Uri baseUrl, string accessToken, CancellationToken ct = default) =>
        SendAuthenticatedJsonAsync<AbsenceResponse>(HttpMethod.Get, new Uri(baseUrl, "api/3/absence/student"), accessToken, null, ct);

    public Task<TimetableResponse> GetActualTimetableAsync(Uri baseUrl, string accessToken, DateOnly date, CancellationToken ct = default)
    {
        var dateStr = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return SendAuthenticatedJsonAsync<TimetableResponse>(HttpMethod.Get, new Uri(baseUrl, $"api/3/timetable/actual?date={dateStr}"), accessToken, null, ct);
    }

    public Task<TimetableResponse> GetPermanentTimetableAsync(Uri baseUrl, string accessToken, CancellationToken ct = default) =>
        SendAuthenticatedJsonAsync<TimetableResponse>(HttpMethod.Get, new Uri(baseUrl, "api/3/timetable/permanent"), accessToken, null, ct);

    public Task<SubjectMarks> PredictWhatIfAsync(Uri baseUrl, string accessToken, IReadOnlyList<WhatIfMarkRequest> payload, CancellationToken ct = default)
    {
        var json = JsonSerializer.Serialize(payload, _jsonOptions);
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        return SendAuthenticatedJsonAsync<SubjectMarks>(HttpMethod.Post, new Uri(baseUrl, "api/3/marks/what-if"), accessToken, content, ct);
    }

    public Task<HomeworkResponse> GetHomeworksAsync(Uri baseUrl, string accessToken, DateOnly from, DateOnly to, CancellationToken ct = default)
    {
        var f = from.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var t = to.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return SendAuthenticatedJsonAsync<HomeworkResponse>(HttpMethod.Get, new Uri(baseUrl, $"api/3/homeworks?from={f}&to={t}"), accessToken, null, ct);
    }

    public async Task SetHomeworkDoneAsync(Uri baseUrl, string accessToken, string homeworkId, bool done, CancellationToken ct = default)
    {
        var encodedId = EncodePathSegment(homeworkId);
        var flag = done ? "true" : "false";
        using var req = new HttpRequestMessage(HttpMethod.Put, new Uri(baseUrl, $"api/3/homeworks/{encodedId}/student-done/{flag}"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        // IIS quirk: explicit zero-length body so Content-Length: 0 is sent (avoids HTTP 411)
        req.Content = new ByteArrayContent([]);
        using var res = await _http.SendAsync(req, ct);
        await EnsureSuccessAsync(res, ct);
    }

    public Task<FinalMarksResponse> GetFinalMarksAsync(Uri baseUrl, string accessToken, CancellationToken ct = default) =>
        SendAuthenticatedJsonAsync<FinalMarksResponse>(HttpMethod.Get, new Uri(baseUrl, "api/3/marks/final"), accessToken, null, ct);

    public async Task<KomensResponse> GetKomensMessagesAsync(Uri baseUrl, string accessToken, KomensBox box, CancellationToken ct = default)
    {
        var boxPath = box == KomensBox.Received ? "received" : "noticeboard";
        var emptyForm = new ByteArrayContent([]);
        emptyForm.Headers.ContentType = new MediaTypeHeaderValue("application/x-www-form-urlencoded") { CharSet = "utf-8" };
        return await SendAuthenticatedJsonAsync<KomensResponse>(HttpMethod.Post, new Uri(baseUrl, $"api/3/komens/messages/{boxPath}"), accessToken, emptyForm, ct);
    }

    public async Task MarkKomensReadAsync(Uri baseUrl, string accessToken, string messageId, CancellationToken ct = default)
    {
        var encodedId = EncodePathSegment(messageId);
        using var req = new HttpRequestMessage(HttpMethod.Put, new Uri(baseUrl, $"api/3/komens/message/{encodedId}/mark-as-read"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new ByteArrayContent([]);
        using var res = await _http.SendAsync(req, ct);
        await EnsureSuccessAsync(res, ct);
    }

    public async Task<byte[]> DownloadAttachmentAsync(Uri baseUrl, string accessToken, string attachmentId, CancellationToken ct = default)
    {
        var encodedId = EncodePathSegment(attachmentId);
        using var req = new HttpRequestMessage(HttpMethod.Get, new Uri(baseUrl, $"api/3/komens/attachment/{encodedId}"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using var res = await _http.SendAsync(req, ct);
        await EnsureSuccessAsync(res, ct);
        return await res.Content.ReadAsByteArrayAsync(ct);
    }

    private async Task<T> SendFormAsync<T>(Uri uri, Dictionary<string, string> form, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, uri);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new FormUrlEncodedContent(form);
        using var res = await _http.SendAsync(req, ct);
        await EnsureSuccessAsync(res, ct);
        var stream = await res.Content.ReadAsStreamAsync(ct);
        var parsed = await JsonSerializer.DeserializeAsync<T>(stream, _jsonOptions, ct);
        return parsed ?? throw new SchoolApiException("Empty response from Bakaláři.");
    }

    private async Task<T> SendAuthenticatedJsonAsync<T>(HttpMethod method, Uri uri, string accessToken, HttpContent? content, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(method, uri);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (content is not null)
            req.Content = content;

        using var res = await _http.SendAsync(req, ct);
        await EnsureSuccessAsync(res, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (string.IsNullOrWhiteSpace(body))
            return Activator.CreateInstance<T>();
        var parsed = JsonSerializer.Deserialize<T>(body, _jsonOptions);
        return parsed ?? Activator.CreateInstance<T>();
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken ct)
    {
        if (response.IsSuccessStatusCode) return;
        var body = await response.Content.ReadAsStringAsync(ct);
        string message = $"HTTP {(int)response.StatusCode}";

        if (!string.IsNullOrWhiteSpace(body))
        {
            try
            {
                using var doc = JsonDocument.Parse(body);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    if (doc.RootElement.TryGetProperty("error_description", out var desc) && desc.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(desc.GetString()))
                        message = desc.GetString()!;
                    else if (doc.RootElement.TryGetProperty("error", out var err) && err.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(err.GetString()))
                        message = err.GetString()!;
                    else
                        message = body.Trim();
                }
            }
            catch
            {
                message = body.Trim();
            }
        }

        bool isAuth = response.StatusCode == HttpStatusCode.Unauthorized ||
                      (response.StatusCode == HttpStatusCode.BadRequest &&
                       (message.Contains("invalid_grant", StringComparison.OrdinalIgnoreCase) ||
                        message.Contains("redeemed", StringComparison.OrdinalIgnoreCase)));

        throw new SchoolApiException(message, (int)response.StatusCode, isAuth);
    }

    public static string EncodePathSegment(string raw)
    {
        var sb = new StringBuilder(raw.Length * 2);
        foreach (var b in Encoding.UTF8.GetBytes(raw))
        {
            char c = (char)b;
            bool unreserved = (c is >= 'a' and <= 'z') || (c is >= 'A' and <= 'Z') || (c is >= '0' and <= '9') || c is '-' or '.' or '_' or '~';
            if (unreserved) sb.Append(c);
            else sb.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }
}
