using System.Globalization;
using System.Text;
using Gradely.Core.Models;
using Gradely.Core.Stores;
using Gradely.Core.Support;

namespace Gradely.Core.Services;

public sealed class SchoolRepository
{
    private const string SessionSecretKey = "school-session";
    private const string CredentialsSecretKey = "school-credentials";

    private readonly BakalariClient _bakalari;
    private readonly EduPageClient _eduPage;
    private readonly SecureSecretStore _secrets;
    private readonly JsonFileStore _files;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);

    private StoredSession? _currentSession;
    private HomeworkResponse? _demoHomework;
    private KomensSnapshot? _demoKomens;

    public SchoolDirectoryProvider DirectoryProvider { get; }
    public StravaCZClient StravaClient { get; }
    public AbsenceOverrideStore AbsenceOverrides { get; }
    public PlannerStore Planner { get; }
    public AppSettingsStore SettingsStore { get; }

    public StoredSession? CurrentSession => _currentSession;
    public bool IsSignedIn => _currentSession is not null;
    public bool IsDemoSession => _currentSession is not null && DemoAccount.IsDemoBaseUrl(_currentSession.BaseUrl);

    public SchoolRepository(string? storageRoot = null)
    {
        _files = new JsonFileStore(storageRoot);
        _secrets = new SecureSecretStore(storageRoot);
        _bakalari = new BakalariClient();
        _eduPage = new EduPageClient();
        DirectoryProvider = new SchoolDirectoryProvider(_files);
        StravaClient = new StravaCZClient(_secrets, _files);
        AbsenceOverrides = new AbsenceOverrideStore(_files);
        Planner = new PlannerStore(_files);
        SettingsStore = new AppSettingsStore(_files);
        _currentSession = _secrets.Load<StoredSession>(SessionSecretKey);
    }

    public async Task<StoredSession> SignInBakalariAsync(string schoolUrl, string username, string password, string? knownSchoolName = null, CancellationToken ct = default)
    {
        var baseUrl = SchoolUrlNormalizer.NormalizeBakalariBaseUrl(schoolUrl);

        if (DemoAccount.IsDemoBaseUrl(baseUrl.AbsoluteUri))
        {
            if (!string.Equals(username.Trim(), DemoAccount.Username, StringComparison.OrdinalIgnoreCase) ||
                password != DemoAccount.Password)
            {
                throw new SchoolApiException("Invalid demo credentials.", isAuthenticationFailure: true);
            }

            _demoHomework = PreviewData.CreateHomework();
            _demoKomens = PreviewData.CreateKomens();

            var demoSession = new StoredSession(
                SchoolProvider.Bakalari,
                DemoAccount.BaseUrl,
                DemoAccount.Username,
                DemoAccount.AccessToken,
                DemoAccount.RefreshToken,
                DateTimeOffset.UtcNow.AddDays(30),
                DemoAccount.UserId,
                "Demo škola");

            PersistSession(demoSession, new StoredCredentials(SchoolProvider.Bakalari, DemoAccount.BaseUrl, DemoAccount.Username, DemoAccount.Password));
            return demoSession;
        }

        var login = await _bakalari.LoginAsync(baseUrl, username.Trim(), password, ct);
        var session = new StoredSession(
            SchoolProvider.Bakalari,
            baseUrl.AbsoluteUri,
            username.Trim(),
            login.AccessToken,
            login.RefreshToken,
            DateTimeOffset.UtcNow.AddSeconds(Math.Max(60, login.ExpiresIn)),
            login.UserId,
            knownSchoolName);

        try
        {
            var user = await _bakalari.GetUserAsync(baseUrl, session.AccessToken, ct);
            var resolvedName = user.ResolvedSchoolName ?? knownSchoolName ?? LookupDirectorySchoolName(baseUrl.AbsoluteUri);
            session = session with { SchoolName = resolvedName, UserId = string.IsNullOrEmpty(user.UserUid) ? session.UserId : user.UserUid };
            SaveCache(session, "user", user);
        }
        catch { }

        PersistSession(session, new StoredCredentials(SchoolProvider.Bakalari, baseUrl.AbsoluteUri, username.Trim(), password));
        return session;
    }

    public Task<StoredSession> SignInDemoAsync(CancellationToken ct = default) =>
        SignInBakalariAsync(DemoAccount.BaseUrl, DemoAccount.Username, DemoAccount.Password, "Demo škola", ct);

    public async Task<SchoolLoginOutcome> BeginEduPageLoginAsync(string schoolAddress, string username, string password, CancellationToken ct = default)
    {
        var baseUrl = SchoolUrlNormalizer.NormalizeEduPageBaseUrl(schoolAddress);
        var outcome = await _eduPage.BeginLoginAsync(baseUrl, username.Trim(), password, ct);
        if (outcome.Session is not null)
        {
            PersistSession(outcome.Session, new StoredCredentials(SchoolProvider.EduPage, baseUrl.AbsoluteUri, username.Trim(), password));
        }
        return outcome;
    }

    public Task<string?> PollEduPageTwoFactorAsync(EduPageTwoFactorChallenge challenge, CancellationToken ct = default) =>
        _eduPage.PollTwoFactorApprovalAsync(challenge, ct);

    public Task<bool> ResendEduPageTwoFactorAsync(EduPageTwoFactorChallenge challenge, CancellationToken ct = default) =>
        _eduPage.ResendTwoFactorNotificationAsync(challenge, ct);

    public async Task<SchoolLoginOutcome> SubmitEduPageTwoFactorAsync(EduPageTwoFactorChallenge challenge, string code, CancellationToken ct = default)
    {
        var outcome = await _eduPage.SubmitTwoFactorCodeAsync(challenge, code, ct);
        if (outcome.Session is not null)
        {
            PersistSession(outcome.Session, new StoredCredentials(SchoolProvider.EduPage, challenge.BaseUrl, challenge.Username, challenge.Password));
        }
        return outcome;
    }

    public async Task<StoredSession> CompleteEduPageParentSelectionAsync(EduPagePendingParentSession pending, SchoolStudentProfile student, CancellationToken ct = default)
    {
        var session = await _eduPage.SelectParentStudentAsync(pending, student, ct);
        PersistSession(session, new StoredCredentials(SchoolProvider.EduPage, pending.BaseUrl, pending.Username, pending.Password));
        return session;
    }

    public async Task<StoredSession> SwitchEduPageStudentAsync(SchoolStudentProfile student, CancellationToken ct = default)
    {
        var session = RequireSession();
        if (session.Provider != SchoolProvider.EduPage)
            throw new InvalidOperationException("Student switching is only supported for EduPage.");

        await _eduPage.SwitchStudentAsync(session, student, ct);
        var updated = session with { ActiveStudent = student };
        _currentSession = updated;
        _secrets.Save(SessionSecretKey, updated);
        return updated;
    }

    public void SignOut()
    {
        if (_currentSession is not null)
            _files.DeleteScopeCaches(_currentSession.ScopeKey);

        _currentSession = null;
        _demoHomework = null;
        _demoKomens = null;
        _secrets.Delete(SessionSecretKey);
        _secrets.Delete(CredentialsSecretKey);
    }

    public UserResponse? LoadCachedUser() => _currentSession is null ? null : LoadCache<UserResponse>(_currentSession, "user");
    public MarksResponse? LoadCachedMarks() => _currentSession is null ? null : LoadCache<MarksResponse>(_currentSession, "marks");
    public AbsenceResponse? LoadCachedAbsence() => _currentSession is null ? null : LoadCache<AbsenceResponse>(_currentSession, "absence");
    public TimetableResponse? LoadCachedTimetable(TimetableKind kind, DateOnly weekStart) =>
        _currentSession is null ? null : LoadCache<TimetableResponse>(_currentSession, TimetableCacheKey(kind, weekStart));
    public HomeworkResponse? LoadCachedHomework() => _currentSession is null ? null : LoadCache<HomeworkResponse>(_currentSession, "homework");
    public KomensSnapshot? LoadCachedKomens() => _currentSession is null ? null : LoadCache<KomensSnapshot>(_currentSession, "komens");
    public FinalMarksResponse? LoadCachedReportCards() => _currentSession is null ? null : LoadCache<FinalMarksResponse>(_currentSession, "report-cards");

    public async Task<UserResponse> GetUserAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
            return PreviewData.User;

        if (session.Provider == SchoolProvider.EduPage)
        {
            var user = EduPageClient.BuildUserResponse(session);
            SaveCache(session, "user", user);
            return user;
        }

        var result = await ExecuteWithAuthRetryAsync(
            (s, token) => _bakalari.GetUserAsync(new Uri(s.BaseUrl), s.AccessToken, token), ct);

        if (string.IsNullOrWhiteSpace(result.ResolvedSchoolName))
            result.SchoolName = LookupDirectorySchoolName(session.BaseUrl);

        SaveCache(session, "user", result);
        return result;
    }

    public async Task<MarksResponse> GetMarksAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
            return PreviewData.CreateMarks();

        var result = session.Provider == SchoolProvider.Bakalari
            ? await ExecuteWithAuthRetryAsync((s, token) => _bakalari.GetMarksAsync(new Uri(s.BaseUrl), s.AccessToken, token), ct)
            : await ExecuteEduPageAsync((s, token) => _eduPage.GetMarksAsync(s, token), ct);

        SaveCache(session, "marks", result);
        return result;
    }

    public async Task<AbsenceResponse> GetAbsenceAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
            return PreviewData.CreateAbsence();

        var result = session.Provider == SchoolProvider.Bakalari
            ? await ExecuteWithAuthRetryAsync((s, token) => _bakalari.GetAbsenceAsync(new Uri(s.BaseUrl), s.AccessToken, token), ct)
            : await ExecuteEduPageAsync((s, token) => _eduPage.GetAbsenceAsync(s, token), ct);

        SaveCache(session, "absence", result);
        return result;
    }

    public async Task<TimetableWeek> GetTimetableAsync(TimetableKind kind, DateOnly date, CancellationToken ct = default)
    {
        var session = RequireSession();
        var monday = TimetableMapper.MondayOfWeek(date);
        var effectiveKind = session.Provider.SupportsPermanentTimetable() ? kind : TimetableKind.Actual;

        TimetableResponse raw;
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
        {
            raw = PreviewData.CreateTimetable(monday, effectiveKind == TimetableKind.Permanent);
        }
        else if (session.Provider == SchoolProvider.Bakalari)
        {
            raw = effectiveKind == TimetableKind.Permanent
                ? await ExecuteWithAuthRetryAsync((s, token) => _bakalari.GetPermanentTimetableAsync(new Uri(s.BaseUrl), s.AccessToken, token), ct)
                : await ExecuteWithAuthRetryAsync((s, token) => _bakalari.GetActualTimetableAsync(new Uri(s.BaseUrl), s.AccessToken, monday, token), ct);
        }
        else
        {
            raw = await ExecuteEduPageAsync((s, token) => _eduPage.GetTimetableAsync(s, monday, token), ct);
        }

        SaveCache(session, TimetableCacheKey(effectiveKind, monday), raw);
        return TimetableMapper.Map(raw, effectiveKind, monday);
    }

    public async Task<GradeSimulationResult?> PredictWhatIfAsync(
        SubjectMarks subject,
        PreparedGradeCalculation prepared,
        string markText,
        int weight,
        CancellationToken ct = default)
    {
        var parsedVal = GradeMath.ParseMarkValue(markText);
        if (parsedVal is null || parsedVal.Value < 1.0 || parsedVal.Value > 5.7)
            return null;

        var clampedWeight = Math.Clamp(weight, 1, 10);
        var session = RequireSession();

        if (!DemoAccount.IsDemoBaseUrl(session.BaseUrl) &&
            session.Provider.SupportsRemoteWhatIf() &&
            subject.MarkPredictionEnabled)
        {
            try
            {
                var payload = subject.Marks
                    .Where(m => !m.IsPoints)
                    .Select(m => new WhatIfMarkRequest
                    {
                        Id = m.HasStableProviderId ? m.Id : null,
                        MarkText = m.MarkText,
                        Weight = m.Weight.HasValue ? (int)Math.Round(m.Weight.Value) : null,
                        MaxPoints = m.MaxPoints ?? 0,
                        SubjectId = subject.Id
                    })
                    .ToList();

                payload.Add(new WhatIfMarkRequest
                {
                    Id = null,
                    MarkText = markText.Trim(),
                    Weight = clampedWeight,
                    MaxPoints = 0,
                    SubjectId = subject.Id
                });

                var remoteSubject = await ExecuteWithAuthRetryAsync(
                    (s, token) => _bakalari.PredictWhatIfAsync(new Uri(s.BaseUrl), s.AccessToken, payload, token), ct);

                var remoteAvg = GradeMath.ParseAverageText(remoteSubject.AverageText);
                if (remoteAvg.HasValue)
                {
                    var baseline = prepared.DisplayAverage;
                    var diff = baseline.HasValue ? remoteAvg.Value - baseline.Value : (double?)null;
                    return new GradeSimulationResult(baseline, remoteAvg.Value, diff, IsRemotePrediction: true);
                }
            }
            catch
            {
                // Fall back cleanly to local calculation
            }
        }

        return GradeMath.Simulate(prepared, [new HypotheticalGrade(Guid.NewGuid(), markText.Trim(), parsedVal.Value, clampedWeight)]);
    }

    public async Task<List<HomeworkItem>> GetHomeworksAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (!session.Provider.SupportsHomework()) return [];

        HomeworkResponse raw;
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
        {
            _demoHomework ??= PreviewData.CreateHomework();
            raw = _demoHomework;
        }
        else
        {
            var today = DateOnly.FromDateTime(DateTime.Today);
            raw = await ExecuteWithAuthRetryAsync(
                (s, token) => _bakalari.GetHomeworksAsync(new Uri(s.BaseUrl), s.AccessToken, today.AddDays(-30), today.AddDays(90), token), ct);
        }

        SaveCache(session, "homework", raw);
        return raw.Homeworks
            .Select(HomeworkItem.FromDto)
            .OrderBy(h => h.DueOn ?? DateTimeOffset.MaxValue)
            .ThenBy(h => h.SubjectName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(h => h.Id, StringComparer.Ordinal)
            .ToList();
    }

    public async Task SetHomeworkDoneAsync(string homeworkId, bool done, CancellationToken ct = default)
    {
        var session = RequireSession();
        if (!session.Provider.SupportsHomework()) return;

        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
        {
            _demoHomework ??= PreviewData.CreateHomework();
            foreach (var hw in _demoHomework.Homeworks.Where(h => h.Id == homeworkId))
                hw.Done = done;
            return;
        }

        await ExecuteWithAuthRetryAsync(async (s, token) =>
        {
            await _bakalari.SetHomeworkDoneAsync(new Uri(s.BaseUrl), s.AccessToken, homeworkId, done, token);
            return true;
        }, ct);
    }

    public async Task<KomensSnapshot> GetKomensAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (!session.Provider.SupportsKomens()) return new KomensSnapshot();

        KomensSnapshot snapshot;
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
        {
            _demoKomens ??= PreviewData.CreateKomens();
            snapshot = _demoKomens;
        }
        else
        {
            var received = await ExecuteWithAuthRetryAsync(
                (s, token) => _bakalari.GetKomensMessagesAsync(new Uri(s.BaseUrl), s.AccessToken, KomensBox.Received, token), ct);

            List<KomensMessageDto> noticeboard = [];
            try
            {
                var nb = await ExecuteWithAuthRetryAsync(
                    (s, token) => _bakalari.GetKomensMessagesAsync(new Uri(s.BaseUrl), s.AccessToken, KomensBox.Noticeboard, token), ct);
                noticeboard = nb.Messages;
            }
            catch { }

            snapshot = new KomensSnapshot
            {
                Received = received.Messages.Where(m => !m.Hidden).ToList(),
                Noticeboard = noticeboard.Where(m => !m.Hidden).ToList()
            };
        }

        SaveCache(session, "komens", snapshot);
        return snapshot;
    }

    public async Task MarkKomensReadAsync(string messageId, CancellationToken ct = default)
    {
        var session = RequireSession();
        if (!session.Provider.SupportsKomens()) return;

        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
        {
            _demoKomens?.MarkRead(messageId);
            return;
        }

        await ExecuteWithAuthRetryAsync(async (s, token) =>
        {
            await _bakalari.MarkKomensReadAsync(new Uri(s.BaseUrl), s.AccessToken, messageId, token);
            return true;
        }, ct);
    }

    public async Task<byte[]> DownloadAttachmentAsync(string attachmentId, string fileName, CancellationToken ct = default)
    {
        var session = RequireSession();
        if (DemoAccount.IsDemoBaseUrl(session.BaseUrl))
            return Encoding.UTF8.GetBytes($"Demo attachment: {fileName}\nGenerated by Gradey for Windows.\n");

        return await ExecuteWithAuthRetryAsync(
            (s, token) => _bakalari.DownloadAttachmentAsync(new Uri(s.BaseUrl), s.AccessToken, attachmentId, token), ct);
    }

    public async Task<List<ReportCardTerm>> GetReportCardsAsync(CancellationToken ct = default)
    {
        var session = RequireSession();
        if (!session.Provider.SupportsReportCard()) return [];

        FinalMarksResponse raw = DemoAccount.IsDemoBaseUrl(session.BaseUrl)
            ? PreviewData.CreateReportCards()
            : await ExecuteWithAuthRetryAsync((s, token) => _bakalari.GetFinalMarksAsync(new Uri(s.BaseUrl), s.AccessToken, token), ct);

        SaveCache(session, "report-cards", raw);
        return ReportCardTerm.SortNewestFirst(raw.Terms.Select(ReportCardTerm.FromDto));
    }

    private async Task<T> ExecuteWithAuthRetryAsync<T>(Func<StoredSession, CancellationToken, Task<T>> operation, CancellationToken ct)
    {
        var session = RequireSession();
        if (session.IsExpired)
            session = await RefreshBakalariSessionAsync(force: false, ct);

        try
        {
            return await operation(session, ct);
        }
        catch (SchoolApiException ex) when (ex.IsAuthenticationFailure)
        {
            var latest = _currentSession;
            if (latest is not null && latest.AccessToken != session.AccessToken)
                return await operation(latest, ct);

            var refreshed = await RefreshBakalariSessionAsync(force: true, ct);
            return await operation(refreshed, ct);
        }
    }

    private async Task<StoredSession> RefreshBakalariSessionAsync(bool force, CancellationToken ct)
    {
        await _refreshLock.WaitAsync(ct);
        try
        {
            var session = RequireSession();
            if (!force && !session.IsExpired) return session;

            var baseUrl = new Uri(session.BaseUrl);
            LoginResponse? login = null;

            if (!string.IsNullOrEmpty(session.RefreshToken))
            {
                try
                {
                    login = await _bakalari.RefreshTokenAsync(baseUrl, session.RefreshToken, ct);
                }
                catch (SchoolApiException ex) when (ex.IsAuthenticationFailure)
                {
                    login = null;
                }
            }

            if (login is null)
            {
                var creds = _secrets.Load<StoredCredentials>(CredentialsSecretKey);
                if (creds is null)
                    throw new SchoolApiException("Session expired. Please sign in again.", isAuthenticationFailure: true);
                login = await _bakalari.LoginAsync(baseUrl, creds.Username, creds.Password, ct);
            }

            var updated = session with
            {
                AccessToken = login.AccessToken,
                RefreshToken = login.RefreshToken ?? session.RefreshToken,
                ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(Math.Max(60, login.ExpiresIn))
            };
            _currentSession = updated;
            _secrets.Save(SessionSecretKey, updated);
            return updated;
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    private async Task<T> ExecuteEduPageAsync<T>(Func<StoredSession, CancellationToken, Task<T>> operation, CancellationToken ct)
    {
        var session = RequireSession();
        try
        {
            return await operation(session, ct);
        }
        catch (SchoolApiException ex) when (ex.IsAuthenticationFailure)
        {
            var creds = _secrets.Load<StoredCredentials>(CredentialsSecretKey);
            var restored = await _eduPage.RestoreOrReauthenticateAsync(session, creds, ct);
            _currentSession = restored;
            _secrets.Save(SessionSecretKey, restored);
            return await operation(restored, ct);
        }
    }

    private void PersistSession(StoredSession session, StoredCredentials credentials)
    {
        _currentSession = session;
        _secrets.Save(SessionSecretKey, session);
        _secrets.Save(CredentialsSecretKey, credentials);
    }

    private StoredSession RequireSession() =>
        _currentSession ?? throw new InvalidOperationException("Not signed in.");

    private string? LookupDirectorySchoolName(string baseUrl)
    {
        var cached = DirectoryProvider.LoadCached();
        if (cached is null) return null;
        var norm = baseUrl.TrimEnd('/');
        var exact = cached.Schools.FirstOrDefault(s => string.Equals(s.SchoolUrl.TrimEnd('/'), norm, StringComparison.OrdinalIgnoreCase));
        if (exact is not null) return exact.Name;

        if (Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri))
        {
            var byHost = cached.Schools.Where(s => Uri.TryCreate(s.SchoolUrl, UriKind.Absolute, out var su) && string.Equals(su.Host, uri.Host, StringComparison.OrdinalIgnoreCase)).ToList();
            if (byHost.Count == 1) return byHost[0].Name;
        }
        return null;
    }

    private static string TimetableCacheKey(TimetableKind kind, DateOnly monday) =>
        kind == TimetableKind.Permanent ? "timetable-permanent" : $"timetable-actual-{monday:yyyy-MM-dd}";

    private void SaveCache<T>(StoredSession session, string key, T payload) =>
        _files.Save(Path.Combine("cache", JsonFileStore.ScopeHash(session.ScopeKey), key + ".json"), payload);

    private T? LoadCache<T>(StoredSession session, string key) =>
        _files.Load<T>(Path.Combine("cache", JsonFileStore.ScopeHash(session.ScopeKey), key + ".json"));
}
