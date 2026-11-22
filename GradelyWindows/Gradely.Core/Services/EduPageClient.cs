using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Gradely.Core.Models;
using Gradely.Core.Support;

namespace Gradely.Core.Services;

public sealed class EduPageClient
{
    private readonly CookieContainer _cookies;
    private readonly HttpClient _http;
    private Dictionary<string, (string Name, string Short)> _cachedSubjects = new(StringComparer.Ordinal);

    public EduPageClient()
    {
        _cookies = new CookieContainer();
        var handler = new HttpClientHandler
        {
            CookieContainer = _cookies,
            AllowAutoRedirect = true,
            AutomaticDecompression = DecompressionMethods.All
        };
        _http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(25) };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36");
    }

    public async Task<SchoolLoginOutcome> BeginLoginAsync(Uri baseUrl, string username, string password, CancellationToken ct = default)
    {
        ClearCookiesFor(baseUrl);

        var loginPageUrl = new Uri(baseUrl, "login/?cmd=MainLogin");
        var loginHtml = await _http.GetStringAsync(loginPageUrl, ct);
        var csrf = ExtractAfter(loginHtml, "\"csrftoken\":\"", "\"")
                   ?? ExtractAfter(loginHtml, "name=\"csrfauth\" value=\"", "\"")
                   ?? string.Empty;

        using var loginContent = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["csrfauth"] = csrf,
            ["username"] = username,
            ["password"] = password
        });

        using var response = await _http.PostAsync(new Uri(baseUrl, "login/edubarLogin.php"), loginContent, ct);
        var finalUrl = response.RequestMessage?.RequestUri?.AbsoluteUri ?? string.Empty;
        var body = await response.Content.ReadAsStringAsync(ct);

        if (finalUrl.Contains("cap=1", StringComparison.OrdinalIgnoreCase) ||
            finalUrl.Contains("lerr=b43b43", StringComparison.OrdinalIgnoreCase))
        {
            throw new SchoolApiException("EduPage requires CAPTCHA verification. Sign in via browser first and retry.", requiresCaptcha: true);
        }

        if (finalUrl.Contains("bad=1", StringComparison.OrdinalIgnoreCase))
            throw new SchoolApiException("Invalid EduPage username or password.", isAuthenticationFailure: true);

        if (finalUrl.Contains("twofactor", StringComparison.OrdinalIgnoreCase) ||
            body.Contains("/login/twofactor", StringComparison.OrdinalIgnoreCase))
        {
            var twoFactorHtml = finalUrl.Contains("twofactor", StringComparison.OrdinalIgnoreCase)
                ? body
                : await _http.GetStringAsync(new Uri(baseUrl, "login/twofactor?sn=1"), ct);

            var sessionId = ReadPhpSessionId(baseUrl);
            var tfCsrf = ExtractAfter(twoFactorHtml, "csrfauth\" value=\"", "\"") ?? csrf;
            var au = ExtractAfter(twoFactorHtml, "au\" value=\"", "\"") ?? string.Empty;
            var gu = ExtractAfter(twoFactorHtml, "gu\" value=\"", "\"") ?? string.Empty;

            return new SchoolLoginOutcome
            {
                TwoFactorChallenge = new EduPageTwoFactorChallenge(baseUrl.AbsoluteUri, username, password, sessionId, tfCsrf, au, gu)
            };
        }

        return await FinishLoginAsync(baseUrl, username, password, body, ct);
    }

    public async Task<string?> PollTwoFactorApprovalAsync(EduPageTwoFactorChallenge challenge, CancellationToken ct = default)
    {
        var baseUrl = new Uri(challenge.BaseUrl);
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUrl, "login/twofactor?akcia=checkIfConfirmed"));
        req.Headers.Add("Cookie", $"PHPSESSID={challenge.SessionId}");
        req.Content = new FormUrlEncodedContent(new Dictionary<string, string>());
        using var res = await _http.SendAsync(req, ct);
        var json = await res.Content.ReadAsStringAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("status", out var status) &&
                string.Equals(status.GetString(), "ok", StringComparison.OrdinalIgnoreCase) &&
                doc.RootElement.TryGetProperty("data", out var data) &&
                data.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(data.GetString()))
            {
                return data.GetString();
            }
        }
        catch { }
        return null;
    }

    public async Task<bool> ResendTwoFactorNotificationAsync(EduPageTwoFactorChallenge challenge, CancellationToken ct = default)
    {
        var baseUrl = new Uri(challenge.BaseUrl);
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUrl, "login/twofactor?akcia=resendNotifs"));
        req.Headers.Add("Cookie", $"PHPSESSID={challenge.SessionId}");
        req.Content = new FormUrlEncodedContent(new Dictionary<string, string>());
        using var res = await _http.SendAsync(req, ct);
        var json = await res.Content.ReadAsStringAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("status", out var s) &&
                   string.Equals(s.GetString(), "ok", StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    public async Task<SchoolLoginOutcome> SubmitTwoFactorCodeAsync(EduPageTwoFactorChallenge challenge, string code, CancellationToken ct = default)
    {
        var baseUrl = new Uri(challenge.BaseUrl);
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUrl, "login/edubarLogin.php"));
        req.Headers.Add("Cookie", $"PHPSESSID={challenge.SessionId}");
        req.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["csrfauth"] = challenge.CsrfToken,
            ["t2fasec"] = code.Trim(),
            ["2fNoSave"] = "y",
            ["2fform"] = "1",
            ["gu"] = challenge.AuthenticationEndpoint,
            ["au"] = challenge.AuthenticationToken
        });

        using var res = await _http.SendAsync(req, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        var finalPath = res.RequestMessage?.RequestUri?.AbsolutePath ?? string.Empty;

        if (!body.Contains("window.location = gu;", StringComparison.Ordinal) &&
            finalPath.Contains("twofactor", StringComparison.OrdinalIgnoreCase))
        {
            throw new SchoolApiException("Invalid two-factor verification code.", isAuthenticationFailure: true);
        }

        var userHtml = await SendGetAuthenticatedHtmlAsync(baseUrl, challenge.SessionId, "user", ct);
        return await FinishLoginAsync(baseUrl, challenge.Username, challenge.Password, userHtml, ct, challenge.SessionId);
    }

    public async Task<StoredSession> SelectParentStudentAsync(EduPagePendingParentSession pending, SchoolStudentProfile student, CancellationToken ct = default)
    {
        var baseUrl = new Uri(pending.BaseUrl);
        var digits = DigitsOnly(student.Id);
        var resText = await SendGetAuthenticatedHtmlAsync(baseUrl, pending.SessionId, $"login/switchchild?studentid={digits}", ct);
        if (!string.Equals(resText.Trim(), "OK", StringComparison.OrdinalIgnoreCase))
            throw new SchoolApiException("Failed to switch EduPage student profile.");

        return new StoredSession(
            SchoolProvider.EduPage,
            pending.BaseUrl,
            pending.Username,
            pending.SessionId,
            null,
            DateTimeOffset.UtcNow.AddDays(30),
            pending.UserId,
            pending.SchoolName,
            student,
            pending.Students,
            pending.GsecHash);
    }

    public async Task SwitchStudentAsync(StoredSession session, SchoolStudentProfile student, CancellationToken ct = default)
    {
        var baseUrl = new Uri(session.BaseUrl);
        var digits = DigitsOnly(student.Id);
        var text = await SendGetAuthenticatedHtmlAsync(baseUrl, session.AccessToken, $"login/switchchild?studentid={digits}", ct);
        if (!string.Equals(text.Trim(), "OK", StringComparison.OrdinalIgnoreCase))
            throw new SchoolApiException("Failed to switch EduPage student.");
    }

    public async Task<StoredSession> RestoreOrReauthenticateAsync(StoredSession session, StoredCredentials? credentials, CancellationToken ct = default)
    {
        var baseUrl = new Uri(session.BaseUrl);
        try
        {
            var html = await SendGetAuthenticatedHtmlAsync(baseUrl, session.AccessToken, "user", ct);
            var parsed = ParseUserSessionHtml(html);
            if (session.ActiveStudent is not null)
                await SwitchStudentAsync(session, session.ActiveStudent, ct);

            return session with
            {
                SchoolName = parsed.SchoolName ?? session.SchoolName,
                EduPageGsecHash = parsed.GsecHash ?? session.EduPageGsecHash
            };
        }
        catch (SchoolApiException ex) when (ex.IsAuthenticationFailure && credentials is not null)
        {
            var outcome = await BeginLoginAsync(baseUrl, credentials.Username, credentials.Password, ct);
            if (outcome.RequiresTwoFactor)
                throw new SchoolApiException("EduPage requires two-factor verification.", isAuthenticationFailure: true, requiresTwoFactor: true);
            if (outcome.RequiresStudentSelection && outcome.PendingParentSession is not null)
            {
                var target = outcome.PendingParentSession.Students.FirstOrDefault(s => s.Id == session.ActiveStudent?.Id)
                             ?? outcome.PendingParentSession.Students.First();
                return await SelectParentStudentAsync(outcome.PendingParentSession, target, ct);
            }
            if (outcome.Session is not null)
                return outcome.Session;
            throw;
        }
    }

    public async Task<MarksResponse> GetMarksAsync(StoredSession session, CancellationToken ct = default)
    {
        var baseUrl = new Uri(session.BaseUrl);
        var html = await SendGetAuthenticatedHtmlAsync(baseUrl, session.AccessToken, "znamky/?barNoSkin=1", ct);
        var jsonText = ExtractBalancedJsonContaining(html, "\"vsetkyZnamky\"")
                       ?? throw new SchoolApiException("Could not parse EduPage grades page.");

        using var doc = JsonDocument.Parse(jsonText);
        var root = doc.RootElement;

        var eventsById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        if (root.TryGetProperty("vsetkyUdalosti", out var allEvents) &&
            allEvents.TryGetProperty("edupage", out var eduEvents) &&
            eduEvents.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in eduEvents.EnumerateObject())
                eventsById[prop.Name] = prop.Value;
        }

        // Also refresh subject names if present
        var subjectNames = new Dictionary<string, (string Name, string Short)>(_cachedSubjects, StringComparer.Ordinal);
        if (root.TryGetProperty("predmety", out var predmety) && predmety.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in predmety.EnumerateObject())
            {
                var name = GetStringProp(p.Value, "p_meno") ?? GetStringProp(p.Value, "name") ?? p.Name;
                var sh = GetStringProp(p.Value, "p_skratka") ?? GetStringProp(p.Value, "short") ?? name;
                subjectNames[p.Name] = (name, sh);
            }
        }

        var marksBySubject = new Dictionary<string, List<Mark>>(StringComparer.Ordinal);
        if (root.TryGetProperty("vsetkyZnamky", out var grades) && grades.ValueKind == JsonValueKind.Array)
        {
            foreach (var g in grades.EnumerateArray())
            {
                var eventId = GetStringProp(g, "udalostid") ?? string.Empty;
                eventsById.TryGetValue(eventId, out var details);

                var subjectId = GetStringProp(g, "predmetid")
                                ?? (details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "PredmetID") : null);
                if (string.IsNullOrWhiteSpace(subjectId) || string.Equals(subjectId, "vsetky", StringComparison.OrdinalIgnoreCase))
                    continue;

                var rawData = GetStringProp(g, "data") ?? string.Empty;
                string markText = rawData;
                string? theme = null;
                var parenIdx = rawData.IndexOf(" (", StringComparison.Ordinal);
                if (parenIdx >= 0)
                {
                    markText = rawData[..parenIdx].Trim();
                    theme = rawData[(parenIdx + 2)..].Trim().TrimEnd(')').Trim();
                }

                var eventType = details.ValueKind == JsonValueKind.Object ? (GetStringProp(details, "p_typ_udalosti") ?? "1") : "1";
                bool isPoints = eventType is "2" or "3";
                double? weight = null;
                int? maxPoints = null;
                string type;
                string? typeNote = null;

                if (isPoints)
                {
                    type = "points";
                    var maxStr = eventType == "2"
                        ? (details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "p_vaha") : null)
                        : (details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "p_vaha_body") : null);
                    if (double.TryParse(maxStr?.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var mp))
                        maxPoints = (int)Math.Round(mp);
                    if (eventType == "3") typeNote = "%";
                }
                else
                {
                    var parsedVal = GradeMath.ParseMarkValue(markText);
                    type = parsedVal is >= 1.0 and <= 5.0 ? "grade" : "unsupported";
                    var vahaStr = details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "p_vaha") : null;
                    if (double.TryParse(vahaStr?.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var rawW) && rawW > 0)
                        weight = rawW / 20.0;
                }

                var caption = details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "p_meno") : null;
                var teacherId = details.ValueKind == JsonValueKind.Object ? GetStringProp(details, "UcitelID") : null;
                var markDate = GetStringProp(g, "datum") ?? string.Empty;

                var mark = new Mark
                {
                    Id = string.IsNullOrEmpty(eventId) ? null : $"{eventId}-{markDate}",
                    SubjectId = subjectId,
                    MarkText = markText,
                    Theme = theme,
                    Caption = caption,
                    MarkDate = markDate,
                    TeacherId = teacherId,
                    Weight = weight,
                    IsPoints = isPoints,
                    PointsText = isPoints ? markText : null,
                    MaxPoints = maxPoints,
                    Type = type,
                    TypeNote = typeNote
                };

                if (!marksBySubject.TryGetValue(subjectId, out var list))
                {
                    list = [];
                    marksBySubject[subjectId] = list;
                }
                list.Add(mark);
            }
        }

        var response = new MarksResponse();
        foreach (var (subId, marks) in marksBySubject)
        {
            var (name, sh) = subjectNames.TryGetValue(subId, out var info) ? info : (subId, subId);
            response.Subjects.Add(new SubjectMarks
            {
                Subject = new SubjectInfo { Id = subId, Name = name, Abbrev = sh },
                AverageText = null,
                PointsOnly = marks.Count > 0 && marks.All(m => m.IsPoints),
                MarkPredictionEnabled = false,
                Marks = marks.OrderByDescending(m => m.ParsedDate ?? DateTimeOffset.MinValue).ToList()
            });
        }
        return response;
    }

    public async Task<AbsenceResponse> GetAbsenceAsync(StoredSession session, CancellationToken ct = default)
    {
        var baseUrl = new Uri(session.BaseUrl);
        var targetId = session.ActiveStudent?.Id ?? session.UserId ?? session.Username;
        var html = await SendGetAuthenticatedHtmlAsync(baseUrl, session.AccessToken, $"dashboard/eb.php?ebuid={Uri.EscapeDataString(targetId)}&mode=attendance", ct);
        var jsonText = ExtractBalancedJsonContaining(html, "\"dateStats\"");
        if (jsonText is null)
            return new AbsenceResponse();

        using var doc = JsonDocument.Parse(jsonText);
        if (!doc.RootElement.TryGetProperty("dateStats", out var dateStats) || dateStats.ValueKind != JsonValueKind.Object)
            return new AbsenceResponse();

        var numericId = DigitsOnly(targetId);
        JsonElement studentDates = default;
        if (!string.IsNullOrEmpty(numericId) && dateStats.TryGetProperty(numericId, out var d1))
            studentDates = d1;
        else if (dateStats.TryGetProperty(targetId, out var d2))
            studentDates = d2;

        var days = new List<AbsenceDay>();
        if (studentDates.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in studentDates.EnumerateObject())
            {
                if (prop.Value.ValueKind != JsonValueKind.Object) continue;
                int absent = GetIntProp(prop.Value, "absent");
                int excused = GetIntProp(prop.Value, "excused");
                int unexcused = GetIntProp(prop.Value, "unexcused");
                int late = GetIntProp(prop.Value, "late");
                int early = GetIntProp(prop.Value, "early");
                int distant = GetIntProp(prop.Value, "distant");

                if (absent + late + early + distant == 0) continue;

                days.Add(new AbsenceDay
                {
                    Date = prop.Name,
                    Ok = excused,
                    Missed = unexcused,
                    Unsolved = Math.Max(0, absent - excused - unexcused),
                    Late = late,
                    Soon = early,
                    School = 0,
                    DistanceTeaching = distant
                });
            }
        }

        return new AbsenceResponse
        {
            PercentageThreshold = null,
            Absences = days.OrderByDescending(d => d.DateKey, StringComparer.Ordinal).ToList(),
            AbsencesPerSubject = []
        };
    }

    public async Task<TimetableResponse> GetTimetableAsync(StoredSession session, DateOnly weekDate, CancellationToken ct = default)
    {
        var baseUrl = new Uri(session.BaseUrl);
        var ttHtml = await SendGetAuthenticatedHtmlAsync(baseUrl, session.AccessToken, "dashboard/eb.php?mode=ttday", ct);

        int gpid = 1;
        var gpidMatches = Regex.Matches(ttHtml, @"gpid=(\d+)");
        if (gpidMatches.Count > 0 && int.TryParse(gpidMatches[^1].Groups[1].Value, out var parsedGpid))
            gpid = parsedGpid + 1;

        var gsh = ExtractAfter(ttHtml, "gsh=", "\"")
                  ?? ExtractAfter(ttHtml, "gsechash=\"", "\"")
                  ?? session.EduPageGsecHash
                  ?? string.Empty;

        var monday = TimetableMapper.MondayOfWeek(weekDate);
        var sunday = monday.AddDays(6);
        var userTarget = session.ActiveStudent?.Id ?? session.UserId ?? session.Username;

        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUrl, "gcall"));
        req.Headers.Add("Cookie", $"PHPSESSID={session.AccessToken}");
        req.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["gpid"] = gpid.ToString(CultureInfo.InvariantCulture),
            ["gsh"] = gsh,
            ["action"] = "loadData",
            ["user"] = userTarget,
            ["changes"] = "{}",
            ["date"] = monday.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["dateto"] = sunday.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["_LJSL"] = "4096"
        });

        using var res = await _http.SendAsync(req, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        var jsonText = ExtractBalancedJsonContaining(body, "\"dates\"")
                       ?? throw new SchoolApiException("Could not parse EduPage timetable response.");

        return ParseEduPageTimetable(jsonText);
    }

    public static UserResponse BuildUserResponse(StoredSession session) => new()
    {
        UserUid = session.ActiveStudent?.Id ?? session.UserId ?? session.Username,
        FullName = session.ActiveStudent?.FullName ?? session.Username,
        Class = session.ActiveStudent?.ClassName is not null
            ? new ClassInfo { Id = session.ActiveStudent.ClassId, Abbrev = session.ActiveStudent.ClassName, Name = session.ActiveStudent.ClassName }
            : null,
        SchoolOrganizationName = session.SchoolName,
        UserType = "student",
        UserTypeText = "Student",
        StudyYear = DateTime.Now.Year
    };

    private async Task<SchoolLoginOutcome> FinishLoginAsync(
        Uri baseUrl,
        string username,
        string password,
        string html,
        CancellationToken ct,
        string? explicitSessionId = null)
    {
        var sessionId = explicitSessionId ?? ReadPhpSessionId(baseUrl);
        if (string.IsNullOrEmpty(sessionId))
            throw new SchoolApiException("EduPage did not return a session cookie.", isAuthenticationFailure: true);

        if (!html.Contains("\"userid\"", StringComparison.Ordinal))
            html = await SendGetAuthenticatedHtmlAsync(baseUrl, sessionId, "user", ct);

        var parsed = ParseUserSessionHtml(html);

        if (parsed.IsParent)
        {
            if (parsed.Students.Count == 0)
                throw new SchoolApiException("No linked students were found for this EduPage parent account.");

            return new SchoolLoginOutcome
            {
                PendingParentSession = new EduPagePendingParentSession(
                    baseUrl.AbsoluteUri,
                    username,
                    password,
                    sessionId,
                    parsed.UserId,
                    parsed.SchoolName,
                    parsed.GsecHash,
                    parsed.Students)
            };
        }

        var student = parsed.Students.FirstOrDefault();
        return new SchoolLoginOutcome
        {
            Session = new StoredSession(
                SchoolProvider.EduPage,
                baseUrl.AbsoluteUri,
                username,
                sessionId,
                null,
                DateTimeOffset.UtcNow.AddDays(30),
                parsed.UserId,
                parsed.SchoolName,
                student,
                parsed.Students,
                parsed.GsecHash)
        };
    }

    private sealed record ParsedEduPageUser(
        string UserId,
        bool IsParent,
        string? SchoolName,
        string? GsecHash,
        List<SchoolStudentProfile> Students
    );

    private ParsedEduPageUser ParseUserSessionHtml(string html)
    {
        var jsonText = ExtractBalancedJsonContaining(html, "\"userid\"")
                       ?? throw new SchoolApiException("Could not parse EduPage user session data.", isAuthenticationFailure: true);

        using var doc = JsonDocument.Parse(jsonText);
        var root = doc.RootElement;
        var userId = GetStringProp(root, "userid") ?? string.Empty;
        var isParent = userId.Contains("rodic", StringComparison.OrdinalIgnoreCase) ||
                       userId.Contains("parent", StringComparison.OrdinalIgnoreCase);

        var gsecHash = ExtractAfter(html, "ASC.gsechash=\"", "\"")
                       ?? ExtractAfter(html, "\"gsechash\":\"", "\"");
        var schoolName = FindRecursiveStringProp(root, ["schoolName", "school_name", "schoolname"]);

        var classes = new Dictionary<string, string>(StringComparer.Ordinal);
        var students = new List<SchoolStudentProfile>();

        if (root.TryGetProperty("dbi", out var dbi) && dbi.ValueKind == JsonValueKind.Object)
        {
            if (dbi.TryGetProperty("classes", out var clsObj) && clsObj.ValueKind == JsonValueKind.Object)
            {
                foreach (var c in clsObj.EnumerateObject())
                {
                    var label = GetStringProp(c.Value, "short") ?? GetStringProp(c.Value, "name") ?? c.Name;
                    classes[c.Name] = label;
                }
            }

            if (dbi.TryGetProperty("subjects", out var subjObj) && subjObj.ValueKind == JsonValueKind.Object)
            {
                var subMap = new Dictionary<string, (string, string)>(StringComparer.Ordinal);
                foreach (var s in subjObj.EnumerateObject())
                {
                    var name = GetStringProp(s.Value, "name") ?? GetStringProp(s.Value, "short") ?? s.Name;
                    var sh = GetStringProp(s.Value, "short") ?? name;
                    subMap[s.Name] = (name, sh);
                }
                _cachedSubjects = subMap;
            }

            if (dbi.TryGetProperty("students", out var studObj) && studObj.ValueKind == JsonValueKind.Object)
            {
                var userDigits = DigitsOnly(userId);
                foreach (var st in studObj.EnumerateObject())
                {
                    if (st.Value.ValueKind != JsonValueKind.Object) continue;
                    bool matches = false;
                    if (isParent)
                    {
                        foreach (var prop in st.Value.EnumerateObject())
                        {
                            if (prop.Name.Contains("parent", StringComparison.OrdinalIgnoreCase) &&
                                DigitsOnly(prop.Value.ToString()) == userDigits &&
                                !string.IsNullOrEmpty(userDigits))
                            {
                                matches = true;
                                break;
                            }
                        }
                    }
                    else
                    {
                        matches = !string.IsNullOrEmpty(userDigits) && DigitsOnly(st.Name) == userDigits;
                    }

                    if (!matches) continue;
                    var first = GetStringProp(st.Value, "firstname") ?? string.Empty;
                    var last = GetStringProp(st.Value, "lastname") ?? string.Empty;
                    var classId = GetStringProp(st.Value, "classid");
                    classes.TryGetValue(classId ?? string.Empty, out var className);
                    var normalizedId = st.Name.StartsWith("Student", StringComparison.OrdinalIgnoreCase)
                        ? st.Name
                        : $"Student{st.Name}";

                    students.Add(new SchoolStudentProfile(normalizedId, $"{first} {last}".Trim(), classId, className));
                }
            }
        }

        return new ParsedEduPageUser(userId, isParent, schoolName, gsecHash, students);
    }

    private TimetableResponse ParseEduPageTimetable(string jsonText)
    {
        using var doc = JsonDocument.Parse(jsonText);
        var response = new TimetableResponse();
        var hoursMap = new Dictionary<int, TimetableHour>();
        var subjectsMap = new Dictionary<string, TimetableEntity>(StringComparer.Ordinal);
        var teachersMap = new Dictionary<string, TimetableEntity>(StringComparer.Ordinal);
        var roomsMap = new Dictionary<string, TimetableEntity>(StringComparer.Ordinal);
        var groupsMap = new Dictionary<string, TimetableGroup>(StringComparer.Ordinal);

        if (!doc.RootElement.TryGetProperty("dates", out var datesObj) || datesObj.ValueKind != JsonValueKind.Object)
            return response;

        foreach (var dateProp in datesObj.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
        {
            if (!DateOnly.TryParseExact(dateProp.Name, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
                continue;

            int dow = date.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)date.DayOfWeek;
            var dayDto = new TimetableDayDto
            {
                Date = dateProp.Name,
                DayOfWeek = dow,
                DayType = dow <= 5 ? "WorkDay" : "Weekend"
            };

            if (dateProp.Value.TryGetProperty("plan", out var planArr) && planArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in planArr.EnumerateArray())
                {
                    if (item.TryGetProperty("header", out var hdr) && hdr.ValueKind != JsonValueKind.Null)
                        continue;

                    var type = (GetStringProp(item, "type") ?? string.Empty).ToLowerInvariant();
                    if (type is not ("lesson" or "event" or "out" or "absent" or "")) continue;

                    int period = GetIntProp(item, "uniperiod");
                    if (period <= 0) continue;

                    var startTime = (GetStringProp(item, "starttime") ?? string.Empty).Replace("24:00", "23:59");
                    var endTime = (GetStringProp(item, "endtime") ?? string.Empty).Replace("24:00", "23:59");
                    hoursMap.TryAdd(period, new TimetableHour
                    {
                        Id = period,
                        Caption = period.ToString(CultureInfo.InvariantCulture),
                        BeginTime = startTime,
                        EndTime = endTime
                    });

                    var subjectId = GetStringProp(item, "subjectid") ?? string.Empty;
                    var subjectName = _cachedSubjects.TryGetValue(subjectId, out var subInfo) ? subInfo.Name : subjectId;
                    var subjectShort = _cachedSubjects.TryGetValue(subjectId, out var subInfo2) ? subInfo2.Short : subjectId;
                    if (!string.IsNullOrEmpty(subjectId))
                        subjectsMap.TryAdd(subjectId, new TimetableEntity { Id = subjectId, Name = subjectName, Abbrev = subjectShort });

                    var teacherName = FirstArrayString(item, "teachernames");
                    var teacherId = FirstArrayString(item, "teacherids") ?? teacherName;
                    if (!string.IsNullOrEmpty(teacherId))
                        teachersMap.TryAdd(teacherId, new TimetableEntity { Id = teacherId, Name = teacherName ?? teacherId, Abbrev = teacherName ?? teacherId });

                    var roomName = FirstArrayString(item, "classroomnames");
                    var roomId = FirstArrayString(item, "classroomids") ?? roomName;
                    if (!string.IsNullOrEmpty(roomId))
                        roomsMap.TryAdd(roomId, new TimetableEntity { Id = roomId, Name = roomName ?? roomId, Abbrev = roomName ?? roomId });

                    var groupIds = new List<string>();
                    if (item.TryGetProperty("groupnames", out var gnames) && gnames.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var g in gnames.EnumerateArray())
                        {
                            var gn = g.GetString()?.Trim();
                            if (!string.IsNullOrEmpty(gn))
                            {
                                groupIds.Add(gn);
                                groupsMap.TryAdd(gn, new TimetableGroup { Id = gn, Name = gn, Abbrev = gn });
                            }
                        }
                    }

                    bool isRemoved = (item.TryGetProperty("removed", out var rem) &&
                                      ((rem.ValueKind == JsonValueKind.True) ||
                                       (rem.ValueKind == JsonValueKind.Number && rem.TryGetInt32(out var ri) && ri == 1) ||
                                       (rem.ValueKind == JsonValueKind.String && rem.GetString() == "1"))) ||
                                     type is "absent" or "";

                    TimetableChange? change = null;
                    if (isRemoved)
                    {
                        change = new TimetableChange
                        {
                            ChangeType = "Canceled",
                            Description = GetStringProp(item, "changeinfo") ?? GetStringProp(item, "note")
                        };
                    }

                    dayDto.Atoms.Add(new TimetableAtom
                    {
                        HourId = period,
                        SubjectId = string.IsNullOrEmpty(subjectId) ? null : subjectId,
                        TeacherId = teacherId,
                        RoomId = roomId,
                        GroupIds = groupIds,
                        Change = change,
                        Theme = GetStringProp(item, "curriculum")
                    });
                }
            }

            response.Days.Add(dayDto);
        }

        response.Hours = hoursMap.Values.OrderBy(h => h.Id).ToList();
        response.Subjects = subjectsMap.Values.ToList();
        response.Teachers = teachersMap.Values.ToList();
        response.Rooms = roomsMap.Values.ToList();
        response.Groups = groupsMap.Values.ToList();
        return response;
    }

    private async Task<string> SendGetAuthenticatedHtmlAsync(Uri baseUrl, string sessionId, string relativePath, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, new Uri(baseUrl, relativePath));
        req.Headers.Add("Cookie", $"PHPSESSID={sessionId}");
        using var res = await _http.SendAsync(req, ct);
        var finalPath = res.RequestMessage?.RequestUri?.AbsolutePath ?? string.Empty;
        var html = await res.Content.ReadAsStringAsync(ct);

        if ((int)res.StatusCode >= 400 ||
            finalPath.Contains("/login", StringComparison.OrdinalIgnoreCase) ||
            html.Contains("cmd=MainLogin", StringComparison.OrdinalIgnoreCase) ||
            (html.Contains("name=\"username\"", StringComparison.OrdinalIgnoreCase) &&
             html.Contains("name=\"password\"", StringComparison.OrdinalIgnoreCase)))
        {
            throw new SchoolApiException("EduPage session expired.", (int)res.StatusCode, isAuthenticationFailure: true);
        }

        return html;
    }

    private string ReadPhpSessionId(Uri baseUrl)
    {
        foreach (Cookie cookie in _cookies.GetCookies(baseUrl))
        {
            if (string.Equals(cookie.Name, "PHPSESSID", StringComparison.OrdinalIgnoreCase))
                return cookie.Value;
        }
        return string.Empty;
    }

    private void ClearCookiesFor(Uri baseUrl)
    {
        foreach (Cookie cookie in _cookies.GetCookies(baseUrl))
            cookie.Expired = true;
    }

    public static string? ExtractBalancedJsonContaining(string text, string marker)
    {
        int markerIndex = text.IndexOf(marker, StringComparison.Ordinal);
        if (markerIndex < 0) return null;

        int start = text.LastIndexOf('{', markerIndex);
        while (start >= 0)
        {
            int depth = 0;
            bool inString = false;
            bool escaped = false;
            for (int i = start; i < text.Length; i++)
            {
                char c = text[i];
                if (inString)
                {
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') inString = false;
                }
                else
                {
                    if (c == '"') inString = true;
                    else if (c == '{') depth++;
                    else if (c == '}')
                    {
                        depth--;
                        if (depth == 0)
                        {
                            if (i >= markerIndex)
                            {
                                var candidate = text[start..(i + 1)];
                                try
                                {
                                    using var _ = JsonDocument.Parse(candidate);
                                    return candidate;
                                }
                                catch { break; }
                            }
                            break;
                        }
                    }
                }
            }
            start = start > 0 ? text.LastIndexOf('{', start - 1) : -1;
        }
        return null;
    }

    private static string? ExtractAfter(string text, string prefix, string terminator)
    {
        int idx = text.IndexOf(prefix, StringComparison.Ordinal);
        if (idx < 0) return null;
        idx += prefix.Length;
        int end = text.IndexOf(terminator, idx, StringComparison.Ordinal);
        return end > idx ? text[idx..end] : null;
    }

    private static string? GetStringProp(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(name, out var val)) return null;
        return val.ValueKind switch
        {
            JsonValueKind.String => val.GetString(),
            JsonValueKind.Number => val.ToString(),
            _ => null
        };
    }

    private static int GetIntProp(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(name, out var val)) return 0;
        if (val.ValueKind == JsonValueKind.Number && val.TryGetInt32(out var i)) return i;
        if (val.ValueKind == JsonValueKind.String && int.TryParse(val.GetString(), out var si)) return si;
        return 0;
    }

    private static string? FirstArrayString(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(name, out var arr) || arr.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var item in arr.EnumerateArray())
        {
            var s = item.ValueKind == JsonValueKind.String ? item.GetString() : item.ToString();
            if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
        }
        return null;
    }

    private static string? FindRecursiveStringProp(JsonElement el, string[] names)
    {
        if (el.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in el.EnumerateObject())
            {
                if (names.Contains(p.Name, StringComparer.Ordinal) && p.Value.ValueKind == JsonValueKind.String)
                {
                    var s = p.Value.GetString()?.Trim();
                    if (!string.IsNullOrEmpty(s)) return s;
                }
                var nested = FindRecursiveStringProp(p.Value, names);
                if (nested is not null) return nested;
            }
        }
        return null;
    }

    private static string DigitsOnly(string s) => new(s.Where(char.IsDigit).ToArray());
}
