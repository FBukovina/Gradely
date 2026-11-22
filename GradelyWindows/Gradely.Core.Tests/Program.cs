using System.Text.Json;
using Gradely.Core.Models;
using Gradely.Core.Services;
using Gradely.Core.Stores;
using Gradely.Core.Support;

int passed = 0;
int failed = 0;

void Test(string name, Action body)
{
    try
    {
        body();
        Console.WriteLine($"  [PASS] {name}");
        passed++;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  [FAIL] {name}: {ex.Message}");
        failed++;
    }
}

async Task TestAsync(string name, Func<Task> body)
{
    try
    {
        await body();
        Console.WriteLine($"  [PASS] {name}");
        passed++;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  [FAIL] {name}: {ex.Message}");
        failed++;
    }
}

void Assert(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

void AssertApprox(double? actual, double expected, double tolerance = 0.005, string label = "")
{
    Assert(actual.HasValue, $"{label} expected {expected} but was null");
    Assert(Math.Abs(actual!.Value - expected) <= tolerance, $"{label} expected {expected}±{tolerance}, got {actual.Value}");
}

Console.WriteLine("Running Gradely.Core.Tests...");

// 1. URL Normalizers
Test("Bakalari URL normalization strips /login and /next/login and enforces HTTPS", () =>
{
    var u1 = SchoolUrlNormalizer.NormalizeBakalariBaseUrl("demo.bakalari.cz/next/login");
    Assert(u1.AbsoluteUri == "https://demo.bakalari.cz/", $"Got {u1.AbsoluteUri}");

    var u2 = SchoolUrlNormalizer.NormalizeBakalariBaseUrl("https://skola.cz/bakalari/login?foo=1#bar");
    Assert(u2.AbsoluteUri == "https://skola.cz/bakalari/", $"Got {u2.AbsoluteUri}");

    bool threwInsecure = false;
    try { SchoolUrlNormalizer.NormalizeBakalariBaseUrl("http://insecure.cz"); }
    catch (UrlNormalizationException ex) when (ex.Kind == UrlNormalizationErrorKind.Insecure) { threwInsecure = true; }
    Assert(threwInsecure, "Should reject HTTP");
});

Test("EduPage URL normalization accepts subdomain or full edupage.org URL", () =>
{
    var u1 = SchoolUrlNormalizer.NormalizeEduPageBaseUrl("myschool");
    Assert(u1.AbsoluteUri == "https://myschool.edupage.org/", $"Got {u1.AbsoluteUri}");

    var u2 = SchoolUrlNormalizer.NormalizeEduPageBaseUrl("https://myschool.edupage.org/login/?cmd=MainLogin");
    Assert(u2.AbsoluteUri == "https://myschool.edupage.org/", $"Got {u2.AbsoluteUri}");

    bool threwHost = false;
    try { SchoolUrlNormalizer.NormalizeEduPageBaseUrl("https://example.com"); }
    catch (UrlNormalizationException ex) when (ex.Kind == UrlNormalizationErrorKind.InvalidEduPageHost) { threwHost = true; }
    Assert(threwHost, "Should reject non-edupage host");
});

// 2. GradeMath: modifier parsing, 3-tier weight resolution, backtracking solver, counterfactuals, what-if
Test("GradeMath parses Czech +/- modifiers and computes weighted average", () =>
{
    AssertApprox(GradeMath.ParseMarkValue("1+"), 1.3);
    AssertApprox(GradeMath.ParseMarkValue("1-"), 1.7);
    AssertApprox(GradeMath.ParseMarkValue("2-"), 2.7);
    AssertApprox(GradeMath.ParseMarkValue("5-"), 5.7);

    var subj = new SubjectMarks
    {
        Subject = new SubjectInfo { Id = "math", Name = "Matematika" },
        Marks =
        [
            new Mark { Id = "1", MarkText = "1-", Weight = 3, MarkDate = "2026-03-01" },
            new Mark { Id = "2", MarkText = "2", Weight = 1, MarkDate = "2026-03-05" }
        ]
    };

    var prep = GradeMath.Prepare(subj);
    AssertApprox(prep.CalculatedAverage, (1.7 * 3 + 2.0 * 1) / 4.0, 0.0001, "weighted avg");
    Assert(prep.Confidence == GradeCalculationConfidence.Exact, "Expected Exact confidence");

    var sim = GradeMath.Simulate(prep, [new HypotheticalGrade(Guid.NewGuid(), "1", 1.0, 2)]);
    Assert(sim is not null, "Simulation should succeed");
    AssertApprox(sim!.EstimatedAverage, (1.7 * 3 + 2.0 + 1.0 * 2) / 6.0, 0.0001, "what-if avg");
    Assert(sim.Difference < 0, "Adding a 1 should improve (lower) average");
});

Test("GradeMath Tier 3 backtracking weight solver recovers unique hidden weights from official average", () =>
{
    // 1*w1 + 3*w2: with w1=1, w2=3 => (1 + 9)/4 = 2.50; let's test a unique combo:
    // Known mark: 1 (weight 2). Unknown mark: 4 (hidden weight 5). Avg = (2 + 20) / 7 = 3.1428 -> "3,14"
    var subj = new SubjectMarks
    {
        Subject = new SubjectInfo { Id = "phys", Name = "Fyzika" },
        AverageText = "3,14",
        Marks =
        [
            new Mark { Id = "a", MarkText = "1", Weight = 2, TypeNote = "Oral" },
            new Mark { Id = "b", MarkText = "4", Weight = null, TypeNote = "Exam" }
        ]
    };

    var prep = GradeMath.Prepare(subj);
    var resolved = prep.ResolvedWeightFor("b");
    Assert(resolved is not null, "Weight should be resolved");
    Assert(resolved!.Source == WeightSource.Inferred, $"Expected Inferred, got {resolved.Source}");
    AssertApprox(resolved.Value, 5.0, 0.001, "inferred weight");
});

Test("GradeMath excludes conflicting duplicate IDs and builds running timeline", () =>
{
    var subj = new SubjectMarks
    {
        Subject = new SubjectInfo { Id = "cs", Name = "ČJ" },
        Marks =
        [
            new Mark { Id = "dup", MarkText = "1", Weight = 2, MarkDate = "2026-03-01" },
            new Mark { Id = "dup", MarkText = "5", Weight = 2, MarkDate = "2026-03-02" },
            new Mark { Id = "ok1", MarkText = "2", Weight = 1, MarkDate = "2026-03-03" },
            new Mark { Id = "ok2", MarkText = "1", Weight = 3, MarkDate = "2026-03-10" }
        ]
    };
    var prep = GradeMath.Prepare(subj);
    Assert(prep.Issues.HasFlag(GradeCalculationIssues.ConflictingDuplicateIds), "Should flag conflicting dup IDs");
    Assert(prep.Marks.Count == 2, $"Expected 2 surviving marks, got {prep.Marks.Count}");

    var timeline = GradeMath.BuildTimeline(prep);
    Assert(timeline.Count == 2, "Timeline should have 2 entries");
    AssertApprox(timeline[0].RunningAverage, 2.0);
    AssertApprox(timeline[1].RunningAverage, 1.25);
});

// 3. Absence Analytics, Semester Allowance & Local Overrides
Test("Absence threshold normalization, risk levels, misses until limit, and semester allowance", () =>
{
    AssertApprox(AbsenceAnalytics.NormalizeThreshold(0.25), 25.0);
    AssertApprox(AbsenceAnalytics.NormalizeThreshold(25.0), 25.0);

    Assert(AbsenceAnalytics.ComputeRiskLevel(10, 25) == AbsenceRiskLevel.Safe, "10/25 safe");
    Assert(AbsenceAnalytics.ComputeRiskLevel(18, 25) == AbsenceRiskLevel.Watch, "18/25 watch");
    Assert(AbsenceAnalytics.ComputeRiskLevel(23, 25) == AbsenceRiskLevel.High, "23/25 high");
    Assert(AbsenceAnalytics.ComputeRiskLevel(25, 25) == AbsenceRiskLevel.OverLimit, "25/25 over");

    // 4/40 = 10%, threshold 25%. Adding k=8 -> 12/48 = 25% -> missesUntilLimit = 8
    Assert(AbsenceAnalytics.MissesUntilLimit(4, 40, 25) == 8, "Expected 8 misses until 25% limit");

    // Semester allowance: taught=30, missed=5, remaining=10 -> total=40, limit=10 -> maxMissed=9 -> canMiss=4
    var allowance = AbsenceAnalytics.ComputeSemesterAllowance(30, 5, 10, 25.0, new DateOnly(2026, 6, 30));
    Assert(allowance is { Kind: SemesterAllowanceKind.CanMiss, AllowedMisses: 4 }, $"Got {allowance}");
});

Test("Absence local overrides subtract locally without mutating denominator and pause when school data changes", () =>
{
    var raw = new AbsenceResponse
    {
        PercentageThreshold = 25,
        Absences = [new AbsenceDay { Date = "2026-04-01", Ok = 2 }],
        AbsencesPerSubject = [new AbsencePerSubject { SubjectName = "Matematika", LessonsCount = 20, Base = 5 }]
    };

    var ov = new AbsenceDayOverride
    {
        Scope = "s1",
        DateKey = "2026-04-01",
        BaselineDay = raw.Absences[0].Clone(),
        Allocations =
        [
            new AbsenceOverrideAllocation("a1", null, "Matematika", AbsenceCategory.Ok),
            new AbsenceOverrideAllocation("a2", null, "Matematika", AbsenceCategory.Ok)
        ],
        HiddenAllocationIds = ["a1", "a2"]
    };

    var proj = AbsenceAnalytics.ProjectOverrides(raw, [ov]);
    Assert(proj.HasLocalAdjustments && !proj.NeedsReview, "Override should be active");
    Assert(proj.EffectiveResponse.Absences.Count == 0, "Entire day hidden");
    Assert(proj.EffectiveResponse.AbsencesPerSubject[0].Base == 3, "Base decremented from 5 to 3");
    Assert(proj.EffectiveResponse.AbsencesPerSubject[0].LessonsCount == 20, "Denominator preserved");

    // Now simulate school changing the day count -> override must pause for review
    raw.Absences[0].Ok = 3;
    var projChanged = AbsenceAnalytics.ProjectOverrides(raw, [ov]);
    Assert(projChanged.NeedsReview && !projChanged.HasLocalAdjustments, "Changed school day should pause override");
});

// 4. Timetable Mapping (untrimmed IDs!) & TodaySummary state machine
Test("TimetableMapper preserves untrimmed Bakalari IDs and TodaySummary resolves Current/Next states", () =>
{
    var raw = new TimetableResponse
    {
        Hours = [new TimetableHour { Id = 1, Caption = "1", BeginTime = "8:00", EndTime = "8:45" }, new TimetableHour { Id = 2, Caption = "2", BeginTime = "8:55", EndTime = "9:40" }],
        Subjects = [new TimetableEntity { Id = " 6", Abbrev = "M", Name = " Matematika " }],
        Teachers = [new TimetableEntity { Id = "U  12", Abbrev = "Nov", Name = "Jan Novák" }],
        Rooms = [new TimetableEntity { Id = "R 1", Abbrev = "12", Name = "Učebna 12" }],
        Days =
        [
            new TimetableDayDto
            {
                DayOfWeek = 1, Date = "2026-04-13", DayType = "WorkDay",
                Atoms =
                [
                    new TimetableAtom { HourId = 1, SubjectId = " 6", TeacherId = "U  12", RoomId = "R 1" },
                    new TimetableAtom { HourId = 2, SubjectId = " 6", TeacherId = "U  12", RoomId = "R 1", Change = new TimetableChange { ChangeType = "RoomChanged", Description = "Aula" } }
                ]
            }
        ]
    };

    var week = TimetableMapper.Map(raw, TimetableKind.Actual);
    var firstLesson = week.Days[0].Lessons[0];
    Assert(firstLesson.SubjectName == "Matematika", $"Untrimmed ID lookup failed: {firstLesson.SubjectName}");
    Assert(firstLesson.TeacherName == "Jan Novák", "Untrimmed teacher ID lookup failed");

    var summary = TimetableMapper.BuildTodaySummary(week, new DateTime(2026, 4, 13, 8, 15, 0));
    Assert(summary is not null, "Summary should exist for matching date");
    Assert(summary!.State == TodayLessonState.Current, $"Expected Current, got {summary.State}");
    Assert(summary.MinutesRemainingInCurrent == 30, $"Expected 30 min remaining, got {summary.MinutesRemainingInCurrent}");
    Assert(summary.NextLesson?.Lesson.Hour.Id == 2, "Next lesson should be period 2");
    Assert(summary.ChangedLessons.Count == 1, "Should surface 1 changed lesson");
});

// 5. SchoolDirectorySearch ranking & Czech diacritics
Test("SchoolDirectorySearch ranks exact, acronym, and diacritic-folded Czech queries", () =>
{
    List<SchoolDirectorySchool> list =
    [
        new("1", "Gymnázium Jana Keplera", "Praha", "https://gjk.bakalari.cz"),
        new("2", "Střední průmyslová škola elektrotechnická", "Plzeň", "https://spse.bakalari.cz"),
        new("3", "Základní škola T. G. Masaryka", "Brno", "https://zstgm.bakalari.cz")
    ];

    var byAcronym = SchoolDirectorySearch.Search(list, "gjk");
    Assert(byAcronym.Count == 1 && byAcronym[0].Id == "1", "Acronym search failed");

    var byDiacritics = SchoolDirectorySearch.Search(list, "prumyslova plzen");
    Assert(byDiacritics.Count == 1 && byDiacritics[0].Id == "2", "Diacritic-insensitive token search failed");
});

// 6. Komens HTML parser & ReportCard borderline calculation
Test("KomensText strips HTML cleanly, preserves links & decodes Czech entities", () =>
{
    var html = "<p>Dobr&yacute; den,</p><ul><li>Bod 1</li><li><a href=\"https://gradey.app\">Web</a></li></ul>";
    var plain = KomensText.PlainTextFromHtml(html);
    Assert(plain.Contains("Dobrý den,"), $"Entity decode failed: {plain}");
    Assert(plain.Contains("• Bod 1"), $"List bullet failed: {plain}");
    Assert(plain.Contains("Web (https://gradey.app)"), $"Link format failed: {plain}");
});

Test("ReportCardEstimate rounds x.50 to better mark and flags borderline within 0.10", () =>
{
    Assert(ReportCardEstimate.MarkForAverage(1.50) == 1, "1.50 should be mark 1");
    Assert(ReportCardEstimate.MarkForAverage(1.51) == 2, "1.51 should be mark 2");
    var borderline = ReportCardEstimate.FindBorderline(1.46, 1);
    Assert(borderline is { NeighborMark: 2 } && Math.Abs(borderline.Distance - 0.04) < 0.001, $"Unexpected borderline: {borderline}");
});

// 7. Strava.cz menu parsing & EduPage balanced JSON extraction
Test("StravaCZClient parses dynamic table0/table1 keys and filters closed VP days", () =>
{
    const string sample = """
    {
      "table0": [
        { "datum": "14.04.2026", "druh_popis": "Polévka", "nazev": "Vývar", "delsiPopis": "Hovězí vývar", "omezeniObj": { "den": "" }, "pocet": "1", "veta": "10", "cena": "0" },
        { "datum": "14.04.2026", "druh_popis": "Oběd 1", "nazev": "Svíčková", "delsiPopis": "Svíčková na smetaně", "omezeniObj": { "den": "T" }, "pocet": 1, "veta": 11, "cena": "42,50" },
        { "datum": "15.04.2026", "druh_popis": "Oběd 1", "nazev": "Zavřeno", "delsiPopis": "Prázdniny", "omezeniObj": { "den": "VP" }, "pocet": 0, "veta": 12, "cena": 0 }
      ]
    }
    """;
    using var doc = JsonDocument.Parse(sample);
    var menu = StravaCZClient.ParseMenuResponse(doc.RootElement);
    Assert(menu.Count == 1, $"Expected 1 day (VP filtered), got {menu.Count}");
    Assert(menu[0].Meals.Count == 2, $"Expected 2 meals, got {menu[0].Meals.Count}");
    Assert(menu[0].Meals[1].Price == 42.5, $"Expected 42.5, got {menu[0].Meals[1].Price}");
    Assert(menu[0].Meals[1].CanModify, "Optional main meal should be modifiable");
});

Test("EduPageClient extracts balanced JSON containing marker from HTML script", () =>
{
    const string html = "<html><script>ASC.user = {\"userid\":\"Student123\",\"nested\":{\"a\":\"}\"}}; var x = 1;</script></html>";
    var extracted = EduPageClient.ExtractBalancedJsonContaining(html, "\"userid\"");
    Assert(extracted == "{\"userid\":\"Student123\",\"nested\":{\"a\":\"}\"}}", $"Extracted: {extracted}");
});

// 8. Windows DPAPI SecureSecretStore & End-to-End Demo Repository
await TestAsync("SecureSecretStore (Windows DPAPI) & Demo SchoolRepository end-to-end flow", async () =>
{
    var tempDir = Path.Combine(Path.GetTempPath(), "gradey-win-test-" + Guid.NewGuid().ToString("N"));
    try
    {
        var repo = new SchoolRepository(tempDir);
        var session = await repo.SignInDemoAsync();
        Assert(repo.IsSignedIn && repo.IsDemoSession, "Should be signed in to demo");
        Assert(session.SchoolName == "Demo škola", $"Got {session.SchoolName}");

        var user = await repo.GetUserAsync();
        Assert(user.NameWithoutClass == "Alex Novák", $"NameWithoutClass got {user.NameWithoutClass}");

        var marks = await repo.GetMarksAsync();
        Assert(marks.Subjects.Count >= 5, "Demo marks should load");

        var tt = await repo.GetTimetableAsync(TimetableKind.Actual, DateOnly.FromDateTime(DateTime.Today));
        Assert(tt.Days.Count == 5, "Demo timetable should have 5 days");

        var hw = await repo.GetHomeworksAsync();
        Assert(hw.Count >= 3, "Demo homework should load");
        await repo.SetHomeworkDoneAsync(hw[0].Id, true);

        var komens = await repo.GetKomensAsync();
        Assert(komens.Received.Count >= 2, "Demo Komens should load");

        var reportCards = await repo.GetReportCardsAsync();
        Assert(reportCards.Count >= 2, "Demo report cards should load");

        // Verify DPAPI persisted session loads in a fresh SchoolRepository instance
        var repo2 = new SchoolRepository(tempDir);
        Assert(repo2.IsSignedIn && repo2.CurrentSession?.Username == DemoAccount.Username, "Session should persist via Windows DPAPI");
    }
    finally
    {
        if (Directory.Exists(tempDir)) Directory.Delete(tempDir, recursive: true);
    }
});

Console.WriteLine();
Console.WriteLine($"Results: {passed} passed, {failed} failed.");
return failed == 0 ? 0 : 1;
