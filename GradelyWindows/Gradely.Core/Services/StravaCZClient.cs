using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using Gradely.Core.Models;
using Gradely.Core.Stores;
using Gradely.Core.Support;

namespace Gradely.Core.Services;

public sealed class StravaCZException : Exception
{
    public bool IsAuthenticationError { get; }
    public bool IsInsufficientBalance { get; }

    public StravaCZException(string message, bool isAuthenticationError = false, bool isInsufficientBalance = false)
        : base(message)
    {
        IsAuthenticationError = isAuthenticationError;
        IsInsufficientBalance = isInsufficientBalance;
    }
}

public sealed class StravaCZClient
{
    private const string BaseUrl = "https://app.strava.cz";
    private const string SessionKey = "stravacz-session";
    private const string MenuCachePath = "cache/stravacz-menu.json";

    private readonly HttpClient _http;
    private readonly SecureSecretStore _secrets;
    private readonly JsonFileStore _files;
    private readonly JsonSerializerOptions _jsonOptions = new() { PropertyNameCaseInsensitive = true };
    private List<StravaCZDayMenu>? _demoMeals;

    public StravaCZClient(SecureSecretStore secrets, JsonFileStore files)
    {
        _secrets = secrets;
        _files = files;
        var handler = new HttpClientHandler
        {
            CookieContainer = new CookieContainer(),
            AutomaticDecompression = DecompressionMethods.All
        };
        _http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
    }

    public StravaCZSession? LoadSession() => _secrets.Load<StravaCZSession>(SessionKey);

    public StravaCZSession ConnectDemo()
    {
        var session = new StravaCZSession("1234", "demo", "demo-strava-sid", "https://demo.strava.cz", 420.0, "Kč", "Demo školní jídelna", "alex.novak@demo.cz");
        _demoMeals = PreviewData.CreateDemoMeals();
        _secrets.Save(SessionKey, session);
        return session;
    }

    public async Task<StravaCZSession> LoginAsync(string canteenNumber, string username, string password, CancellationToken ct = default)
    {
        if (string.Equals(canteenNumber.Trim(), "1234", StringComparison.Ordinal) &&
            string.Equals(username.Trim(), "demo", StringComparison.OrdinalIgnoreCase))
        {
            return ConnectDemo();
        }

        // Best-effort warmup for cookies
        try { await _http.GetAsync($"{BaseUrl}/en/prihlasit-se?jidelna", ct); } catch { }

        var payload = new
        {
            cislo = canteenNumber.Trim(),
            jmeno = username.Trim(),
            heslo = password,
            zustatPrihlasen = true,
            environment = "W",
            lang = "EN"
        };

        using var doc = await PostApiAsync("api/login", payload, ct);
        var root = doc.RootElement;
        var sid = GetString(root, "sid") ?? throw new StravaCZException("Invalid response from Strava.cz.", isAuthenticationError: true);
        var s5Url = GetString(root, "s5url") ?? string.Empty;
        var cislo = GetString(root, "cislo") ?? canteenNumber.Trim();
        var userNameResp = GetString(root, "jmeno") ?? username.Trim();

        double balance = 0;
        string currency = "Kč";
        string? canteenName = null;
        string? email = null;

        if (root.TryGetProperty("uzivatel", out var userEl) && userEl.ValueKind == JsonValueKind.Object)
        {
            balance = GetDouble(userEl, "konto") ?? 0;
            currency = GetString(userEl, "mena") ?? "Kč";
            canteenName = GetString(userEl, "nazevJidelny");
            email = GetString(userEl, "email");
        }

        var session = new StravaCZSession(cislo, userNameResp, sid, s5Url, balance, currency, canteenName, email);
        _secrets.Save(SessionKey, session);
        return session;
    }

    public async Task<List<StravaCZDayMenu>> GetMenuAsync(StravaCZSession session, CancellationToken ct = default)
    {
        if (session.SessionId == "demo-strava-sid")
        {
            _demoMeals ??= PreviewData.CreateDemoMeals();
            return _demoMeals;
        }

        var payload = new
        {
            cislo = session.CanteenNumber,
            sid = session.SessionId,
            s5url = session.ServiceUrl,
            lang = "EN",
            konto = session.Balance,
            podminka = "",
            ignoreCert = false
        };

        try
        {
            using var doc = await PostApiAsync("api/objednavky", payload, ct);
            var meals = ParseMenuResponse(doc.RootElement);
            _files.Save(MenuCachePath, meals);
            return meals;
        }
        catch (StravaCZException ex) when (ex.IsAuthenticationError)
        {
            DisconnectLocal();
            throw;
        }
    }

    public List<StravaCZDayMenu> LoadCachedMenu() =>
        _files.Load<List<StravaCZDayMenu>>(MenuCachePath) ?? [];

    public async Task<(StravaCZSession UpdatedSession, List<StravaCZDayMenu> UpdatedMenu)> SetMealOrderAsync(
        StravaCZSession session,
        StravaCZMeal meal,
        bool ordered,
        CancellationToken ct = default)
    {
        if (!meal.CanModify)
            throw new StravaCZException("This meal cannot be modified.");

        if (session.SessionId == "demo-strava-sid")
        {
            _demoMeals ??= PreviewData.CreateDemoMeals();
            double balance = session.Balance;
            foreach (var day in _demoMeals.Where(d => d.DateKey == meal.DateKey))
            {
                foreach (var m in day.Meals.Where(m => m.Type == StravaCZMealType.Main))
                {
                    if (m.Id == meal.Id)
                    {
                        if (ordered && !m.IsOrdered) balance -= m.Price;
                        else if (!ordered && m.IsOrdered) balance += m.Price;
                        m.IsOrdered = ordered;
                    }
                    else if (ordered && m.IsOrdered)
                    {
                        balance += m.Price;
                        m.IsOrdered = false;
                    }
                }
            }
            var updatedDemo = session with { Balance = balance };
            _secrets.Save(SessionKey, updatedDemo);
            return (updatedDemo, _demoMeals);
        }

        var current = session;
        try
        {
            using (var stageDoc = await PostApiAsync("api/pridejJidloS5", new
            {
                cislo = current.CanteenNumber,
                sid = current.SessionId,
                url = current.ServiceUrl,
                veta = meal.Id,
                pocet = ordered ? "1" : "0",
                lang = "EN",
                ignoreCert = "false"
            }, ct))
            {
                if (GetDouble(stageDoc.RootElement, "konto") is double b1)
                    current = current with { Balance = b1 };
            }

            using (var saveDoc = await PostApiAsync("api/saveOrders", new
            {
                cislo = current.CanteenNumber,
                sid = current.SessionId,
                url = current.ServiceUrl,
                xml = (string?)null,
                lang = "EN",
                ignoreCert = "false"
            }, ct))
            {
                if (GetDouble(saveDoc.RootElement, "konto") is double b2)
                    current = current with { Balance = b2 };
            }

            _secrets.Save(SessionKey, current);
            var menu = await GetMenuAsync(current, ct);
            return (current, menu);
        }
        catch
        {
            // Attempt rollback
            try
            {
                await PostApiAsync("api/nactiVlastnostiPA", new
                {
                    sid = current.SessionId,
                    url = current.ServiceUrl,
                    cislo = current.CanteenNumber,
                    ignoreCert = "false",
                    lang = "EN",
                    getText = true,
                    checkVersion = true,
                    resetTables = true,
                    frontendFunction = "refreshInformations"
                }, CancellationToken.None);
            }
            catch { }
            throw;
        }
    }

    public async Task LogoutAsync(StravaCZSession? session, CancellationToken ct = default)
    {
        if (session is not null && session.SessionId != "demo-strava-sid")
        {
            try
            {
                await PostApiAsync("api/logOut", new
                {
                    sid = session.SessionId,
                    cislo = session.CanteenNumber,
                    url = session.ServiceUrl,
                    lang = "EN",
                    ignoreCert = "false"
                }, ct);
            }
            catch { }
        }
        DisconnectLocal();
    }

    public void DisconnectLocal()
    {
        _demoMeals = null;
        _secrets.Delete(SessionKey);
        _files.Delete(MenuCachePath);
    }

    public static List<StravaCZDayMenu> ParseMenuResponse(JsonElement root)
    {
        var allMeals = new List<StravaCZMeal>();
        if (root.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in root.EnumerateObject())
            {
                if (!prop.Name.StartsWith("table", StringComparison.OrdinalIgnoreCase)) continue;
                if (prop.Value.ValueKind != JsonValueKind.Array) continue;

                foreach (var item in prop.Value.EnumerateArray())
                {
                    var dto = item.Deserialize<StravaCZMealDto>();
                    var domain = dto?.ToDomain();
                    if (domain is not null)
                        allMeals.Add(domain);
                }
            }
        }

        return allMeals
            .GroupBy(m => m.DateKey, StringComparer.Ordinal)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => new StravaCZDayMenu(
                g.Key,
                g.First().Date,
                g.OrderBy(m => (int)m.Type).ThenBy(m => m.Id, StringComparer.Ordinal).ToList()))
            .ToList();
    }

    private async Task<JsonDocument> PostApiAsync(string endpoint, object payload, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(payload, _jsonOptions);
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{BaseUrl}/{endpoint}");
        // Critical Strava.cz quirk: JSON payload must be sent as text/plain;charset=UTF-8
        req.Content = new StringContent(json, Encoding.UTF8, "text/plain");
        req.Headers.TryAddWithoutValidation("Accept", "*/*");
        req.Headers.TryAddWithoutValidation("Accept-Language", "en-US,en;q=0.9,cs;q=0.8");
        req.Headers.TryAddWithoutValidation("Origin", BaseUrl);
        req.Headers.TryAddWithoutValidation("Referer", $"{BaseUrl}/en/prihlasit-se?jidelna");
        req.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36");

        using var res = await _http.SendAsync(req, ct);
        var body = await res.Content.ReadAsStringAsync(ct);

        if (!res.IsSuccessStatusCode)
        {
            string message = $"Strava.cz error (HTTP {(int)res.StatusCode})";
            int? errNum = null;
            try
            {
                using var errDoc = JsonDocument.Parse(body);
                errNum = (int?)GetDouble(errDoc.RootElement, "number");
                if (GetString(errDoc.RootElement, "message") is string m && !string.IsNullOrWhiteSpace(m))
                    message = m;
            }
            catch { }

            if (errNum == 35)
                throw new StravaCZException(message, isInsufficientBalance: true);
            if (res.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                throw new StravaCZException(message, isAuthenticationError: true);
            throw new StravaCZException(message);
        }

        if (string.IsNullOrWhiteSpace(body))
            return JsonDocument.Parse("{}");

        var doc = JsonDocument.Parse(body);
        if (doc.RootElement.ValueKind == JsonValueKind.Object)
        {
            var errNum = (int?)GetDouble(doc.RootElement, "number");
            var errMsg = GetString(doc.RootElement, "message");
            if (errNum == 35)
            {
                doc.Dispose();
                throw new StravaCZException(errMsg ?? "Insufficient balance.", isInsufficientBalance: true);
            }
        }
        return doc;
    }

    private static string? GetString(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(name, out var el)) return null;
        return el.ValueKind == JsonValueKind.String ? el.GetString() : (el.ValueKind == JsonValueKind.Number ? el.ToString() : null);
    }

    private static double? GetDouble(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(name, out var el)) return null;
        if (el.ValueKind == JsonValueKind.Number && el.TryGetDouble(out var d)) return d;
        if (el.ValueKind == JsonValueKind.String &&
            double.TryParse(el.GetString()?.Trim().Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var sd))
            return sd;
        return null;
    }
}
