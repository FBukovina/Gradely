using System.Globalization;
using Gradely.Core.Models;

namespace Gradely.Core.Support;

public static class DemoAccount
{
    public const string BaseUrl = "https://demo.gradely.app/";
    public const string Username = "apple-review";
    public const string Password = "GradelyDemo2026!";
    public const string AccessToken = "demo-access";
    public const string RefreshToken = "demo-refresh";
    public const string UserId = "demo-user";

    public static bool IsDemoBaseUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        var trimmed = url.Trim().TrimEnd('/').ToLowerInvariant();
        return trimmed is "demo" or "demo.gradely.app" or "https://demo.gradely.app";
    }

    public static bool IsDemoToken(string? token) =>
        string.Equals(token, AccessToken, StringComparison.Ordinal) ||
        string.Equals(token, RefreshToken, StringComparison.Ordinal);
}

public static class PreviewData
{
    public static UserResponse User => new()
    {
        UserUid = DemoAccount.UserId,
        FullName = "Alex Novák, 4.A",
        Class = new ClassInfo { Id = "4A", Abbrev = "4.A", Name = "4.A" },
        SchoolOrganizationName = "Demo škola",
        UserType = "student",
        UserTypeText = "Žák",
        StudyYear = DateTime.Now.Year
    };

    public static MarksResponse CreateMarks()
    {
        var today = DateTime.Today;
        string D(int daysAgo) => today.AddDays(-daysAgo).ToString("yyyy-MM-dd'T'10:00:00", CultureInfo.InvariantCulture);

        return new MarksResponse
        {
            Subjects =
            [
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "math", Abbrev = "M", Name = "Matematika" },
                    AverageText = "1,78",
                    MarkPredictionEnabled = true,
                    Marks =
                    [
                        new Mark { Id = "m1", SubjectId = "math", MarkText = "1-", Weight = 3, MarkDate = D(1), Caption = "Písemná práce", Theme = "Lineární rovnice", Type = "P", TypeNote = "Písemná práce", IsNew = true },
                        new Mark { Id = "m2", SubjectId = "math", MarkText = "2", Weight = 2, MarkDate = D(9), Caption = "Ústní zkoušení", Theme = "Kvadratické funkce", Type = "U", TypeNote = "Ústní zkoušení" },
                        new Mark { Id = "m3", SubjectId = "math", MarkText = "1", Weight = 1, MarkDate = D(18), Caption = "Malý test", Theme = "Mocniny a odmocniny", Type = "M", TypeNote = "Malý test" },
                        new Mark { Id = "m4", SubjectId = "math", MarkText = "8", PointsText = "8", MaxPoints = 10, IsPoints = true, MarkDate = D(5), Caption = "Aktivita v hodině", Type = "B" }
                    ]
                },
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "czech", Abbrev = "ČJ", Name = "Český jazyk" },
                    AverageText = null,
                    MarkPredictionEnabled = true,
                    Marks =
                    [
                        new Mark { Id = "c1", SubjectId = "czech", MarkText = "2+", Weight = 2, MarkDate = D(2), Caption = "Diktát", Theme = "Vyjmenovaná slova", Type = "P", TypeNote = "Písemná práce", IsNew = true },
                        new Mark { Id = "c2", SubjectId = "czech", MarkText = "1", Weight = 3, MarkDate = D(15), Caption = "Slohová práce", Theme = "Charakteristika", Type = "S", TypeNote = "Sloh" },
                        new Mark { Id = "c3", SubjectId = "czech", MarkText = "2", Weight = 1, MarkDate = D(24), Caption = "Čtenářský deník", Type = "D", TypeNote = "Referát" }
                    ]
                },
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "english", Abbrev = "AJ", Name = "Anglický jazyk" },
                    AverageText = "1,25",
                    MarkPredictionEnabled = true,
                    Marks =
                    [
                        new Mark { Id = "e1", SubjectId = "english", MarkText = "1", Weight = 2, MarkDate = D(4), Caption = "Unit 5 Test", Theme = "Conditionals & Vocabulary", Type = "T", TypeNote = "Test" },
                        new Mark { Id = "e2", SubjectId = "english", MarkText = "1-", Weight = 2, MarkDate = D(14), Caption = "Speaking", Theme = "Presentation", Type = "U", TypeNote = "Ústní" }
                    ]
                },
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "physics", Abbrev = "FY", Name = "Fyzika" },
                    AverageText = "2,83",
                    MarkPredictionEnabled = true,
                    Marks =
                    [
                        new Mark { Id = "p1", SubjectId = "physics", MarkText = "3-", Weight = 3, MarkDate = D(3), Caption = "Čtvrtletní práce", Theme = "Elektromagnetismus", Type = "P", TypeNote = "Písemná práce" },
                        new Mark { Id = "p2", SubjectId = "physics", MarkText = "2", Weight = 2, MarkDate = D(16), Caption = "Laboratorní práce", Theme = "Ohmův zákon", Type = "L", TypeNote = "Laboratoř" },
                        new Mark { Id = "p3", SubjectId = "physics", MarkText = "3", Weight = 1, MarkDate = D(26), Caption = "Zkoušení u tabule", Type = "U", TypeNote = "Ústní" }
                    ]
                },
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "biology", Abbrev = "BI", Name = "Biologie" },
                    AverageText = "1,50",
                    MarkPredictionEnabled = true,
                    Marks =
                    [
                        new Mark { Id = "b1", SubjectId = "biology", MarkText = "1", Weight = 2, MarkDate = D(6), Caption = "Genetika — test", Type = "T", TypeNote = "Test" },
                        new Mark { Id = "b2", SubjectId = "biology", MarkText = "2", Weight = 2, MarkDate = D(20), Caption = "Mikroskopování", Type = "L", TypeNote = "Laboratoř" }
                    ]
                },
                new SubjectMarks
                {
                    Subject = new SubjectInfo { Id = "informatics", Abbrev = "IVT", Name = "Informatika" },
                    PointsOnly = true,
                    Marks =
                    [
                        new Mark { Id = "i1", SubjectId = "informatics", MarkText = "18", PointsText = "18", MaxPoints = 20, IsPoints = true, MarkDate = D(7), Caption = "Webová aplikace", Type = "B" },
                        new Mark { Id = "i2", SubjectId = "informatics", MarkText = "9", PointsText = "9", MaxPoints = 10, IsPoints = true, MarkDate = D(19), Caption = "SQL dotazy", Type = "B" }
                    ]
                }
            ]
        };
    }

    public static AbsenceResponse CreateAbsence()
    {
        var today = DateTime.Today;
        string D(int daysAgo) => today.AddDays(-daysAgo).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        return new AbsenceResponse
        {
            PercentageThreshold = 25.0,
            Absences =
            [
                new AbsenceDay { Date = D(2), Unsolved = 4 },
                new AbsenceDay { Date = D(11), Ok = 6 },
                new AbsenceDay { Date = D(25), Ok = 2, Late = 1 },
                new AbsenceDay { Date = D(42), Ok = 6 },
                new AbsenceDay { Date = D(68), Ok = 5, Soon = 1 }
            ],
            AbsencesPerSubject =
            [
                new AbsencePerSubject { SubjectName = "Matematika", LessonsCount = 42, Base = 4, Late = 1 },
                new AbsencePerSubject { SubjectName = "Český jazyk", LessonsCount = 38, Base = 7 },
                new AbsencePerSubject { SubjectName = "Fyzika", LessonsCount = 38, Base = 9 },
                new AbsencePerSubject { SubjectName = "Anglický jazyk", LessonsCount = 40, Base = 3 },
                new AbsencePerSubject { SubjectName = "Biologie", LessonsCount = 30, Base = 2 },
                new AbsencePerSubject { SubjectName = "Tělesná výchova", LessonsCount = 40, Base = 11 }
            ]
        };
    }

    public static TimetableResponse CreateTimetable(DateOnly weekDate, bool permanent)
    {
        var baseResponse = new TimetableResponse
        {
            Hours =
            [
                new TimetableHour { Id = 1, Caption = "1", BeginTime = "8:00", EndTime = "8:45" },
                new TimetableHour { Id = 2, Caption = "2", BeginTime = "8:55", EndTime = "9:40" },
                new TimetableHour { Id = 3, Caption = "3", BeginTime = "9:50", EndTime = "10:35" },
                new TimetableHour { Id = 4, Caption = "4", BeginTime = "10:55", EndTime = "11:40" },
                new TimetableHour { Id = 5, Caption = "5", BeginTime = "11:50", EndTime = "12:35" }
            ],
            Subjects =
            [
                new TimetableEntity { Id = "math", Abbrev = "M", Name = "Matematika" },
                new TimetableEntity { Id = "czech", Abbrev = "ČJ", Name = "Český jazyk" },
                new TimetableEntity { Id = "biology", Abbrev = "BI", Name = "Biologie" },
                new TimetableEntity { Id = "english", Abbrev = "AJ", Name = "Anglický jazyk" },
                new TimetableEntity { Id = "physics", Abbrev = "FY", Name = "Fyzika" },
                new TimetableEntity { Id = "pe", Abbrev = "TV", Name = "Tělesná výchova" }
            ],
            Teachers =
            [
                new TimetableEntity { Id = "t1", Abbrev = "Nov", Name = "Mgr. Jan Novák" },
                new TimetableEntity { Id = "t2", Abbrev = "Svo", Name = "Mgr. Eva Svobodová" },
                new TimetableEntity { Id = "t3", Abbrev = "Dvo", Name = "RNDr. Petr Dvořák" }
            ],
            Rooms =
            [
                new TimetableEntity { Id = "r1", Abbrev = "12", Name = "Učebna 12" },
                new TimetableEntity { Id = "r2", Abbrev = "Aula", Name = "Aula" },
                new TimetableEntity { Id = "r3", Abbrev = "LAB", Name = "Laboratoř fyziky" },
                new TimetableEntity { Id = "r4", Abbrev = "TV", Name = "Tělocvična" }
            ],
            Days =
            [
                new TimetableDayDto
                {
                    DayOfWeek = 1, DayType = "WorkDay",
                    Atoms =
                    [
                        new TimetableAtom { HourId = 1, SubjectId = "math", TeacherId = "t1", RoomId = "r1", Theme = "Lineární rovnice", HomeworkIds = ["hw-1"] },
                        new TimetableAtom { HourId = 2, SubjectId = "czech", TeacherId = "t2", RoomId = "r1", Theme = "Slohová práce" },
                        new TimetableAtom { HourId = 3, SubjectId = "english", TeacherId = "t2", RoomId = "r2", Theme = "Conditionals" },
                        new TimetableAtom { HourId = 4, SubjectId = "physics", TeacherId = "t3", RoomId = "r3", Theme = "Elektromagnetická indukce" }
                    ]
                },
                new TimetableDayDto
                {
                    DayOfWeek = 2, DayType = "WorkDay",
                    Atoms =
                    [
                        new TimetableAtom { HourId = 1, SubjectId = "biology", TeacherId = "t3", RoomId = "r3", Theme = "Základy genetiky" },
                        new TimetableAtom
                        {
                            HourId = 2, SubjectId = "math", TeacherId = "t1", RoomId = "r1",
                            Change = permanent ? null : new TimetableChange { ChangeType = "Canceled", Description = "Odpadá — nepřítomnost vyučujícího" }
                        },
                        new TimetableAtom { HourId = 3, SubjectId = "czech", TeacherId = "t2", RoomId = "r1", HomeworkIds = ["hw-2"] },
                        new TimetableAtom { HourId = 4, SubjectId = "pe", TeacherId = "t1", RoomId = "r4" }
                    ]
                },
                new TimetableDayDto
                {
                    DayOfWeek = 3, DayType = "WorkDay",
                    Atoms =
                    [
                        new TimetableAtom
                        {
                            HourId = 1, SubjectId = "english", TeacherId = "t2", RoomId = "r2",
                            Change = permanent ? null : new TimetableChange { ChangeType = "RoomChanged", Description = "Přesun do Auly" }
                        },
                        new TimetableAtom { HourId = 2, SubjectId = "physics", TeacherId = "t3", RoomId = "r3" },
                        new TimetableAtom { HourId = 3, SubjectId = "math", TeacherId = "t1", RoomId = "r1" },
                        new TimetableAtom { HourId = 4, SubjectId = "biology", TeacherId = "t3", RoomId = "r3", HomeworkIds = ["hw-3"] }
                    ]
                },
                new TimetableDayDto
                {
                    DayOfWeek = 4, DayType = "WorkDay",
                    Atoms =
                    [
                        new TimetableAtom { HourId = 1, SubjectId = "czech", TeacherId = "t2", RoomId = "r1" },
                        new TimetableAtom { HourId = 2, SubjectId = "math", TeacherId = "t1", RoomId = "r1" },
                        new TimetableAtom
                        {
                            HourId = 3, SubjectId = "physics", TeacherId = "t1", RoomId = "r1",
                            Change = permanent ? null : new TimetableChange { ChangeType = "Substitution", Description = "Supluje Mgr. Jan Novák" }
                        },
                        new TimetableAtom { HourId = 4, SubjectId = "english", TeacherId = "t2", RoomId = "r2" }
                    ]
                },
                new TimetableDayDto
                {
                    DayOfWeek = 5, DayType = "WorkDay",
                    Atoms =
                    [
                        new TimetableAtom { HourId = 1, SubjectId = "math", TeacherId = "t1", RoomId = "r1" },
                        new TimetableAtom { HourId = 2, SubjectId = "english", TeacherId = "t2", RoomId = "r2" },
                        new TimetableAtom { HourId = 3, SubjectId = "biology", TeacherId = "t3", RoomId = "r3" },
                        new TimetableAtom { HourId = 4, SubjectId = "pe", TeacherId = "t1", RoomId = "r4" }
                    ]
                }
            ]
        };

        return permanent ? baseResponse : TimetableMapper.RebaseToWeek(baseResponse, weekDate);
    }

    public static HomeworkResponse CreateHomework()
    {
        var today = DateTime.Today;
        string D(int offset) => today.AddDays(offset).ToString("yyyy-MM-dd'T'08:00:00", CultureInfo.InvariantCulture);

        return new HomeworkResponse
        {
            Homeworks =
            [
                new HomeworkDto
                {
                    Id = "hw-1",
                    DateStart = D(-2),
                    DateEnd = D(1),
                    Content = "Pracovní list — soustavy lineárních rovnic (cvičení 1 až 6)",
                    Subject = new SubjectInfo { Id = "math", Abbrev = "M", Name = "Matematika" },
                    Teacher = new SubjectInfo { Id = "t1", Name = "Mgr. Jan Novák" },
                    Done = false
                },
                new HomeworkDto
                {
                    Id = "hw-2",
                    DateStart = D(-3),
                    DateEnd = D(3),
                    Content = "Napsat úvahu na vybrané téma (rozsah min. 250 slov)\nOdevzdat v PDF nebo napsané v sešitě.",
                    Subject = new SubjectInfo { Id = "czech", Abbrev = "ČJ", Name = "Český jazyk" },
                    Teacher = new SubjectInfo { Id = "t2", Name = "Mgr. Eva Svobodová" },
                    Electronic = true,
                    Attachments = [new SchoolAttachmentDto { Id = "att-hw-1", Name = "Zadání slohu.txt", Size = 1840 }]
                },
                new HomeworkDto
                {
                    Id = "hw-3",
                    DateStart = D(-1),
                    DateEnd = D(6),
                    Content = "Připravit krátkou prezentaci o vybraném ekosystému",
                    Notice = "Stačí 4–5 slidů, prezentujeme ve skupinách po dvou.",
                    Subject = new SubjectInfo { Id = "biology", Abbrev = "BI", Name = "Biologie" },
                    Teacher = new SubjectInfo { Id = "t3", Name = "RNDr. Petr Dvořák" }
                },
                new HomeworkDto
                {
                    Id = "hw-4",
                    DateStart = D(-7),
                    DateEnd = D(-1),
                    Content = "Workbook p. 42, exercises 1–4",
                    Subject = new SubjectInfo { Id = "english", Abbrev = "AJ", Name = "Anglický jazyk" },
                    Teacher = new SubjectInfo { Id = "t2", Name = "Mgr. Eva Svobodová" },
                    Done = true
                }
            ]
        };
    }

    public static KomensSnapshot CreateKomens()
    {
        var now = DateTime.Now;
        string D(int hoursAgo) => now.AddHours(-hoursAgo).ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture);

        return new KomensSnapshot
        {
            Received =
            [
                new KomensMessageDto
                {
                    Id = "msg-1",
                    Title = "Jarní exkurze do Technického muzea",
                    Text = "<p>Dobrý den,</p><p>příští čtvrtek se koná třídní exkurze. Sraz je v <strong>8:15</strong> před školou.</p><ul><li>Vzít si průkazku na MHD</li><li>Svačinu a pití</li><li>Zápisník</li></ul><p>Více info na <a href=\"https://www.ntm.cz\">webu muzea</a>.</p>",
                    SentDate = D(3),
                    Sender = new KomensSenderDto { Id = "t1", Name = "Mgr. Jan Novák", Type = "teacher" },
                    Read = false,
                    Attachments = [new SchoolAttachmentDto { Id = "att-msg-1", Name = "Program exkurze.txt", Size = 2460 }]
                },
                new KomensMessageDto
                {
                    Id = "msg-2",
                    Title = "Změna učebny pro angličtinu",
                    Text = "<p>Středeční hodina AJ se přesouvá do <b>Auly</b> z důvodu maturitních zkoušek.</p>",
                    SentDate = D(19),
                    Sender = new KomensSenderDto { Id = "t2", Name = "Mgr. Eva Svobodová", Type = "teacher" },
                    Read = false
                },
                new KomensMessageDto
                {
                    Id = "msg-3",
                    Title = null,
                    Text = "<p>Omlouvám absenci ze dne 12. 3. z důvodu návštěvy lékaře.</p>",
                    SentDate = D(72),
                    Sender = new KomensSenderDto { Id = "p1", Name = "Třídní učitel", Type = "teacher" },
                    Read = true
                }
            ],
            Noticeboard =
            [
                new KomensMessageDto
                {
                    Id = "nb-1",
                    Title = "Ředitelské volno — květen",
                    Text = "<p>V pátek následující po státním svátku je vyhlášeno ředitelské volno. Školní jídelna nebude v provozu.</p>",
                    SentDate = D(48),
                    Sender = new KomensSenderDto { Id = "dir", Name = "Ředitelství školy", Type = "director" },
                    Read = true
                },
                new KomensMessageDto
                {
                    Id = "nb-2",
                    Title = "Sběr starého papíru",
                    Text = "<p>V pondělí a úterý probíhá u hlavního vchodu školní sběr papíru od 7:15 do 8:00.</p>",
                    SentDate = D(120),
                    Sender = new KomensSenderDto { Id = "sch", Name = "Školní parlament", Type = "school" },
                    Read = true
                }
            ]
        };
    }

    public static FinalMarksResponse CreateReportCards() => new()
    {
        Terms =
        [
            new CertificateTermDto
            {
                SchoolYear = "2025/26", Semester = "1", Closed = true,
                AchievementText = "Prospěl s vyznamenáním",
                MarksAverage = 1.40, AbsentHours = 18, NotExcusedHours = 0,
                CertificateDate = "2026-01-30",
                Subjects =
                [
                    new FinalMarkSubjectDto { Id = "chov", Abbrev = "CH", Name = "Chování" },
                    new FinalMarkSubjectDto { Id = "czech", Abbrev = "ČJ", Name = "Český jazyk" },
                    new FinalMarkSubjectDto { Id = "english", Abbrev = "AJ", Name = "Anglický jazyk" },
                    new FinalMarkSubjectDto { Id = "math", Abbrev = "M", Name = "Matematika" },
                    new FinalMarkSubjectDto { Id = "physics", Abbrev = "FY", Name = "Fyzika" },
                    new FinalMarkSubjectDto { Id = "biology", Abbrev = "BI", Name = "Biologie" }
                ],
                FinalMarks =
                [
                    new FinalMarkDto { SubjectId = "chov", MarkText = "1" },
                    new FinalMarkDto { SubjectId = "czech", MarkText = "2" },
                    new FinalMarkDto { SubjectId = "english", MarkText = "1" },
                    new FinalMarkDto { SubjectId = "math", MarkText = "1" },
                    new FinalMarkDto { SubjectId = "physics", MarkText = "2" },
                    new FinalMarkDto { SubjectId = "biology", MarkText = "1" }
                ]
            },
            new CertificateTermDto
            {
                SchoolYear = "2024/25", Semester = "2", Closed = true,
                AchievementText = "Prospěl",
                MarksAverage = 1.60, AbsentHours = 24, NotExcusedHours = 0,
                CertificateDate = "2025-06-27",
                Subjects =
                [
                    new FinalMarkSubjectDto { Id = "chov", Abbrev = "CH", Name = "Chování" },
                    new FinalMarkSubjectDto { Id = "czech", Abbrev = "ČJ", Name = "Český jazyk" },
                    new FinalMarkSubjectDto { Id = "english", Abbrev = "AJ", Name = "Anglický jazyk" },
                    new FinalMarkSubjectDto { Id = "math", Abbrev = "M", Name = "Matematika" },
                    new FinalMarkSubjectDto { Id = "physics", Abbrev = "FY", Name = "Fyzika" },
                    new FinalMarkSubjectDto { Id = "biology", Abbrev = "BI", Name = "Biologie" }
                ],
                FinalMarks =
                [
                    new FinalMarkDto { SubjectId = "chov", MarkText = "1" },
                    new FinalMarkDto { SubjectId = "czech", MarkText = "2" },
                    new FinalMarkDto { SubjectId = "english", MarkText = "1" },
                    new FinalMarkDto { SubjectId = "math", MarkText = "2" },
                    new FinalMarkDto { SubjectId = "physics", MarkText = "2" },
                    new FinalMarkDto { SubjectId = "biology", MarkText = "1" }
                ]
            }
        ]
    };

    public static List<StravaCZDayMenu> CreateDemoMeals()
    {
        var today = DateOnly.FromDateTime(DateTime.Today);
        var tomorrow = today.AddDays(1);
        return
        [
            new StravaCZDayMenu(today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), today,
            [
                new StravaCZMeal
                {
                    Id = "demo-soup-1", DateKey = today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = today,
                    TypeDescription = "Polévka", Type = StravaCZMealType.Soup,
                    Name = "Hovězí vývar s nudlemi", LongDescription = "Hovězí vývar s nudlemi a zeleninou",
                    Price = 0, IsOrdered = true, OrderType = StravaCZOrderType.Restricted,
                    Allergens = [new StravaCZAllergen("1", "Lepek"), new StravaCZAllergen("9", "Celer")]
                },
                new StravaCZMeal
                {
                    Id = "demo-main-1", DateKey = today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = today,
                    TypeDescription = "Oběd 1", Type = StravaCZMealType.Main,
                    Name = "Svíčková na smetaně, houskový knedlík", LongDescription = "Svíčková na smetaně, houskový knedlík, brusinky",
                    Price = 42, IsOrdered = true, OrderType = StravaCZOrderType.Restricted,
                    Allergens = [new StravaCZAllergen("1", "Lepek"), new StravaCZAllergen("7", "Mléko")]
                },
                new StravaCZMeal
                {
                    Id = "demo-main-2", DateKey = today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = today,
                    TypeDescription = "Oběd 2", Type = StravaCZMealType.Main,
                    Name = "Zeleninové rizoto se sýrem", LongDescription = "Zeleninové rizoto se sýrem a okurkovým salátem",
                    Price = 40, IsOrdered = false, OrderType = StravaCZOrderType.Restricted,
                    Allergens = [new StravaCZAllergen("7", "Mléko")]
                }
            ]),
            new StravaCZDayMenu(tomorrow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), tomorrow,
            [
                new StravaCZMeal
                {
                    Id = "demo-soup-2", DateKey = tomorrow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = tomorrow,
                    TypeDescription = "Polévka", Type = StravaCZMealType.Soup,
                    Name = "Kulajda s vejcem", LongDescription = "Kulajda se zastřeným vejcem a koprem",
                    Price = 0, IsOrdered = true, OrderType = StravaCZOrderType.Normal,
                    Allergens = [new StravaCZAllergen("3", "Vejce"), new StravaCZAllergen("7", "Mléko")]
                },
                new StravaCZMeal
                {
                    Id = "demo-main-3", DateKey = tomorrow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = tomorrow,
                    TypeDescription = "Oběd 1", Type = StravaCZMealType.Main,
                    Name = "Kuřecí řízek, bramborová kaše", LongDescription = "Kuřecí řízek, bramborová kaše, okurkový salát",
                    Price = 44, IsOrdered = true, OrderType = StravaCZOrderType.Normal,
                    Allergens = [new StravaCZAllergen("1", "Lepek"), new StravaCZAllergen("3", "Vejce"), new StravaCZAllergen("7", "Mléko")]
                },
                new StravaCZMeal
                {
                    Id = "demo-main-4", DateKey = tomorrow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Date = tomorrow,
                    TypeDescription = "Oběd 2", Type = StravaCZMealType.Main,
                    Name = "Těstoviny s rajčatovou omáčkou", LongDescription = "Celozrnné těstoviny s rajčatovou omáčkou a parmazánem",
                    Price = 41, IsOrdered = false, OrderType = StravaCZOrderType.Normal,
                    Allergens = [new StravaCZAllergen("1", "Lepek"), new StravaCZAllergen("7", "Mléko")]
                }
            ])
        ];
    }
}
