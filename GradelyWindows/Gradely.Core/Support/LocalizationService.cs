using System.ComponentModel;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Gradely.Core.Support;

public enum AppLanguagePreference
{
    System,
    Czech,
    English
}

public sealed partial class LocalizationService : INotifyPropertyChanged
{
    public static LocalizationService Instance { get; } = new();

    private AppLanguagePreference _preference = AppLanguagePreference.System;
    private bool _chronicallyOnline;

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppLanguagePreference Preference
    {
        get => _preference;
        set
        {
            if (_preference == value) return;
            _preference = value;
            NotifyAllChanged();
        }
    }

    public bool ChronicallyOnline
    {
        get => _chronicallyOnline;
        set
        {
            if (_chronicallyOnline == value) return;
            _chronicallyOnline = value;
            NotifyAllChanged();
        }
    }

    public bool IsCzech => _preference switch
    {
        AppLanguagePreference.Czech => true,
        AppLanguagePreference.English => false,
        _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("cs", StringComparison.OrdinalIgnoreCase)
    };

    public CultureInfo ActiveCulture => IsCzech ? CultureInfo.GetCultureInfo("cs-CZ") : CultureInfo.GetCultureInfo("en-US");

    public string this[string key] => Get(key);

    public string Get(string key)
    {
        var table = IsCzech ? CzechStrings : EnglishStrings;
        if (!table.TryGetValue(key, out var raw))
        {
            if (!EnglishStrings.TryGetValue(key, out raw))
                return key;
        }
        return _chronicallyOnline ? TransformChronicallyOnline(raw) : raw;
    }

    public string Format(string key, params object[] args)
    {
        var template = Get(key);
        return string.Format(ActiveCulture, template, args);
    }

    private void NotifyAllChanged()
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Preference)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ChronicallyOnline)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsCzech)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ActiveCulture)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
    }

    private static readonly HashSet<string> PreservedBrandTokens = new(StringComparer.OrdinalIgnoreCase)
    {
        "Gradey", "Gradely", "Bakaláři", "EduPage", "Strava.cz", "AI", "HTTPS", "URL", "2FA", "Windows", "GitHub"
    };

    private static string TransformChronicallyOnline(string input)
    {
        if (string.IsNullOrEmpty(input)) return input;
        return WordRegex().Replace(input, m =>
        {
            var token = m.Value;
            if (PreservedBrandTokens.Contains(token)) return token;
            return token.ToLower(CultureInfo.CurrentCulture);
        });
    }

    [GeneratedRegex(@"[\p{L}\p{N}\.]+")]
    private static partial Regex WordRegex();

    private static readonly Dictionary<string, string> EnglishStrings = new(StringComparer.Ordinal)
    {
        // App & Navigation
        ["app.name"] = "Gradey",
        ["nav.today"] = "Today",
        ["nav.marks"] = "Marks",
        ["nav.absence"] = "Absence",
        ["nav.timetable"] = "Timetable",
        ["nav.meals"] = "Meals",
        ["nav.messages"] = "Messages",
        ["nav.planner"] = "Planner",
        ["nav.reportCard"] = "Report card",
        ["nav.settings"] = "Settings",
        ["common.refresh"] = "Refresh",
        ["common.cancel"] = "Cancel",
        ["common.save"] = "Save",
        ["common.done"] = "Done",
        ["common.close"] = "Close",
        ["common.delete"] = "Delete",
        ["common.edit"] = "Edit",
        ["common.restore"] = "Restore",
        ["common.clear"] = "Clear",
        ["common.retry"] = "Try again",
        ["common.change"] = "Change",
        ["common.loading"] = "Loading…",
        ["common.today"] = "Today",
        ["common.tomorrow"] = "Tomorrow",
        ["common.undated"] = "Undated",
        ["common.signOut"] = "Sign out",

        // Login
        ["login.step1.label"] = "1 / 2 · School",
        ["login.step2.label"] = "2 / 2 · Credentials",
        ["login.step1.title"] = "Find your school",
        ["login.step1.subtitle"] = "Search for your Bakaláři school or enter its web address directly.",
        ["login.step2.title"] = "Sign in",
        ["login.step2.subtitle"] = "Your credentials stay encrypted on this Windows device.",
        ["login.provider"] = "School system",
        ["login.searchPlaceholder"] = "Search school by name, town, or acronym…",
        ["login.urlPlaceholder"] = "https://school.bakalari.cz",
        ["login.edupagePlaceholder"] = "school (or https://school.edupage.org)",
        ["login.edupageHint"] = "Enter your EduPage school subdomain (e.g. myschool) or its full https://myschool.edupage.org address.",
        ["login.urlHelpTitle"] = "How to find your school URL",
        ["login.urlHelpBody"] = "1. Open your school's Bakaláři login page in a browser.\n2. Copy the main address (without /login or /next/login).\n3. Paste it above — Gradey adds https:// automatically.\nExample: https://demo.bakalari.cz",
        ["login.continue"] = "Continue",
        ["login.signIn"] = "Sign in",
        ["login.signingIn"] = "Signing in…",
        ["login.username"] = "Username",
        ["login.password"] = "Password",
        ["login.demoButton"] = "Use demo account",
        ["login.noResults"] = "No schools found. Try entering the school URL below.",
        ["login.loadingDirectory"] = "Loading school directory…",
        ["login.2fa.title"] = "Two-factor verification",
        ["login.2fa.subtitle"] = "Enter the verification code or approve the sign-in in your EduPage mobile app.",
        ["login.2fa.codePlaceholder"] = "Verification code",
        ["login.2fa.verify"] = "Verify code",
        ["login.2fa.checkApproval"] = "Check device approval",
        ["login.2fa.resend"] = "Resend notification",
        ["login.child.title"] = "Select student",
        ["login.child.subtitle"] = "Choose which student account you want to view.",
        ["login.githubLink"] = "Open-source on GitHub",

        // Today
        ["today.greeting.morning"] = "Good morning, {0}",
        ["today.greeting.afternoon"] = "Good afternoon, {0}",
        ["today.greeting.evening"] = "Good evening, {0}",
        ["today.kpi.average"] = "AVERAGE",
        ["today.kpi.lessons"] = "LESSONS TODAY",
        ["today.kpi.newMarks"] = "NEW MARKS",
        ["today.nowAndNext"] = "Now & Next",
        ["today.current"] = "CURRENT · {0} min left",
        ["today.nextIn"] = "NEXT · in {0} min",
        ["today.nextAt"] = "NEXT · starts at {0}",
        ["today.noLessons"] = "No lessons today",
        ["today.afterSchool"] = "No more lessons today",
        ["today.changes"] = "Timetable changes",
        ["today.recentMarks"] = "Recent marks",
        ["today.noRecentMarks"] = "No recent marks yet.",
        ["today.planner"] = "Planner & Homework",
        ["today.noPlanner"] = "Nothing upcoming right now.",
        ["today.lunch"] = "Today's lunch",
        ["today.noMealOrdered"] = "No meal ordered for today.",
        ["today.viewAll"] = "Open",

        // Marks & Subjects
        ["marks.overallAverage"] = "Overall average",
        ["marks.summary"] = "{0} subjects · {1} marks",
        ["marks.subjects"] = "Subjects",
        ["marks.sort.focus"] = "Priority",
        ["marks.sort.average"] = "Average",
        ["marks.schoolAverage"] = "School average",
        ["marks.calculatedAverage"] = "Calculated average",
        ["marks.marksCount"] = "{0} marks",
        ["marks.absencePct"] = "Absence {0:F1} %",
        ["marks.weight"] = "Weight {0}",
        ["marks.inferredWeight"] = "~Weight {0}",
        ["marks.untitled"] = "Untitled mark",
        ["marks.whatIf.title"] = "What-If calculator",
        ["marks.whatIf.placeholder"] = "Grade (e.g. 1, 1-, 2+)",
        ["marks.whatIf.weight"] = "Weight",
        ["marks.whatIf.better"] = "{0:F2} better",
        ["marks.whatIf.worse"] = "{0:F2} worse",
        ["marks.whatIf.unchanged"] = "Unchanged",
        ["marks.whatIf.pointsOnly"] = "What-If simulation is unavailable for points-only subjects.",
        ["marks.whatIf.remote"] = "Calculated by Bakaláři",
        ["marks.whatIf.local"] = "Calculated locally",
        ["marks.history.title"] = "Average history",
        ["marks.history.calculated"] = "Calculated from marks",
        ["marks.history.empty"] = "Not enough dated marks to draw a chart.",
        ["marks.reportCard.subtitle"] = "Est. average {0} · {1} borderline",
        ["marks.reportCard.subtitleClean"] = "Est. average {0}",

        // Timetable
        ["timetable.actual"] = "Actual",
        ["timetable.permanent"] = "Permanent",
        ["timetable.permanentBanner"] = "Showing permanent timetable schedule.",
        ["timetable.lessonDetail"] = "Lesson details",
        ["timetable.time"] = "Time",
        ["timetable.teacher"] = "Teacher",
        ["timetable.room"] = "Room",
        ["timetable.groups"] = "Groups",
        ["timetable.cycles"] = "Cycles",
        ["timetable.theme"] = "Topic",
        ["timetable.change.canceled"] = "Canceled",
        ["timetable.change.substitution"] = "Substitution",
        ["timetable.change.roomChanged"] = "Room changed",
        ["timetable.change.added"] = "Added lesson",
        ["timetable.addToPlanner"] = "Add to planner",
        ["timetable.noLessonsDay"] = "Free day",

        // Absence
        ["absence.totalTitle"] = "Total absence",
        ["absence.hours"] = "hours",
        ["absence.limit"] = "Limit {0:F0} %",
        ["absence.unsolved"] = "Unsolved",
        ["absence.ok"] = "Excused",
        ["absence.missed"] = "Unexcused",
        ["absence.late"] = "Late",
        ["absence.soon"] = "Early leave",
        ["absence.school"] = "School event",
        ["absence.distance"] = "Distance",
        ["absence.tab.subjects"] = "Subjects",
        ["absence.tab.days"] = "Days",
        ["absence.tab.months"] = "Months",
        ["absence.missedOfTotal"] = "Missed {0} of {1} lessons",
        ["absence.untilLimit"] = "{0} left until limit",
        ["absence.overLimit"] = "Over limit",
        ["absence.semester.canMiss"] = "Can miss {0} more this term",
        ["absence.semester.noMore"] = "No more misses allowed this term",
        ["absence.semester.over"] = "Over limit even with full attendance",
        ["absence.predictor.title"] = "Predict absence",
        ["absence.predictor.subtitle"] = "Select upcoming lessons to see how they affect your percentages.",
        ["absence.predictor.pickDate"] = "Pick date",
        ["absence.predictor.addSelected"] = "Apply selection",
        ["absence.localAdjusted"] = "Locally adjusted ({0} day overrides active) — school records are never edited.",
        ["absence.needsReview"] = "{0} local override(s) paused because school records changed.",
        ["absence.hiddenTitle"] = "Local absence overrides",
        ["absence.override.disclaimer"] = "Changes stay on this Windows device only and never modify school records.",
        ["absence.override.hideDay"] = "Hide entire day locally",
        ["absence.override.restoreDay"] = "Restore day",
        ["absence.totalRow"] = "Total",

        // Komens
        ["komens.received"] = "Received",
        ["komens.noticeboard"] = "Noticeboard",
        ["komens.empty"] = "No messages in this box.",
        ["komens.selectPrompt"] = "Select a message to read.",
        ["komens.attachments"] = "Attachments",
        ["komens.savedAttachment"] = "Saved to {0}",

        // Planner & Homework
        ["planner.upcoming"] = "Upcoming",
        ["planner.completed"] = "Completed",
        ["planner.newItem"] = "New item",
        ["planner.editItem"] = "Edit item",
        ["planner.titlePlaceholder"] = "Title (e.g. Math test — quadratics)",
        ["planner.notesPlaceholder"] = "Notes (optional)",
        ["planner.type"] = "Type",
        ["planner.subject"] = "Subject",
        ["planner.dueDate"] = "Due date",
        ["planner.schoolHomework"] = "School homework",
        ["planner.markDone"] = "Mark as done",
        ["planner.markNotDone"] = "Mark as not done",
        ["planner.type.Homework"] = "Homework",
        ["planner.type.Test"] = "Test",
        ["planner.type.Presentation"] = "Presentation",
        ["planner.type.Note"] = "Note",
        ["planner.type.Task"] = "Task",

        // Report Card
        ["reportCard.currentEstimate"] = "Current term estimate",
        ["reportCard.pastTerms"] = "Past report cards",
        ["reportCard.written"] = "Written · Avg {0}",
        ["reportCard.estimated"] = "Avg {0}",
        ["reportCard.borderline"] = "Borderline · {0:F2} from {1}",
        ["reportCard.termTitle"] = "Semester {0} · {1}",
        ["reportCard.absentFooter"] = "Absent: {0:F0} h · Unexcused: {1:F0} h",

        // Strava.cz
        ["meals.connectTitle"] = "Connect Strava.cz",
        ["meals.connectSubtitle"] = "Check your school canteen balance and order or cancel lunches.",
        ["meals.canteenNumber"] = "Canteen number",
        ["meals.connect"] = "Connect canteen",
        ["meals.disconnect"] = "Disconnect Strava.cz",
        ["meals.balance"] = "Balance",
        ["meals.ordered"] = "ORDERED",
        ["meals.canteen"] = "CANTEEN",
        ["meals.replaceTitle"] = "Replace ordered meal?",
        ["meals.replaceBody"] = "Replace \"{0}\" with \"{1}\"?",
        ["meals.locked"] = "Locked",
        ["meals.empty"] = "No upcoming meals available.",

        // Settings
        ["settings.account"] = "Account",
        ["settings.services"] = "Connected Services",
        ["settings.preferences"] = "App Preferences",
        ["settings.about"] = "About Gradey",
        ["settings.theme"] = "Appearance",
        ["settings.theme.system"] = "System",
        ["settings.theme.light"] = "Light",
        ["settings.theme.dark"] = "Dark",
        ["settings.language"] = "Language",
        ["settings.language.system"] = "System default",
        ["settings.language.czech"] = "Čeština",
        ["settings.language.english"] = "English",
        ["settings.chronicallyOnline"] = "Chronically online dialect",
        ["settings.chronicallyOnlineDesc"] = "Casual lowercase styling across the interface.",
        ["settings.showMealsTab"] = "Show Meals (Strava.cz) tab",
        ["settings.semesterAllowance"] = "Show remaining semester absence allowance",
        ["settings.switchStudent"] = "Switch student",
        ["settings.privacyNote"] = "Gradey stores your credentials locally using Windows DPAPI encryption and communicates directly with your school over HTTPS."
    };

    private static readonly Dictionary<string, string> CzechStrings = new(StringComparer.Ordinal)
    {
        // App & Navigation
        ["app.name"] = "Gradey",
        ["nav.today"] = "Dnes",
        ["nav.marks"] = "Známky",
        ["nav.absence"] = "Absence",
        ["nav.timetable"] = "Rozvrh",
        ["nav.meals"] = "Jídelna",
        ["nav.messages"] = "Zprávy",
        ["nav.planner"] = "Plánovač",
        ["nav.reportCard"] = "Vysvědčení",
        ["nav.settings"] = "Nastavení",
        ["common.refresh"] = "Obnovit",
        ["common.cancel"] = "Zrušit",
        ["common.save"] = "Uložit",
        ["common.done"] = "Hotovo",
        ["common.close"] = "Zavřít",
        ["common.delete"] = "Smazat",
        ["common.edit"] = "Upravit",
        ["common.restore"] = "Obnovit",
        ["common.clear"] = "Vymazat",
        ["common.retry"] = "Zkusit znovu",
        ["common.change"] = "Změnit",
        ["common.loading"] = "Načítám…",
        ["common.today"] = "Dnes",
        ["common.tomorrow"] = "Zítra",
        ["common.undated"] = "Bez data",
        ["common.signOut"] = "Odhlásit se",

        // Login
        ["login.step1.label"] = "1 / 2 · Škola",
        ["login.step2.label"] = "2 / 2 · Přihlášení",
        ["login.step1.title"] = "Vyber svoji školu",
        ["login.step1.subtitle"] = "Vyhledej školu v adresáři Bakalářů nebo zadej její adresu ručně.",
        ["login.step2.title"] = "Přihlásit se",
        ["login.step2.subtitle"] = "Přihlašovací údaje jsou šifrované přímo v tomto zařízení Windows.",
        ["login.provider"] = "Školní systém",
        ["login.searchPlaceholder"] = "Hledat školu podle názvu, města nebo zkratky…",
        ["login.urlPlaceholder"] = "https://skola.bakalari.cz",
        ["login.edupagePlaceholder"] = "skola (nebo https://skola.edupage.org)",
        ["login.edupageHint"] = "Zadej subdoménu své školy v EduPage (např. mojaskola) nebo celou adresu https://mojaskola.edupage.org.",
        ["login.urlHelpTitle"] = "Jak najít URL školy",
        ["login.urlHelpBody"] = "1. Otevři přihlašovací stránku Bakalářů své školy v prohlížeči.\n2. Zkopíruj hlavní adresu (bez /login nebo /next/login).\n3. Vlož ji výše — Gradey automaticky doplní https://.\nPříklad: https://demo.bakalari.cz",
        ["login.continue"] = "Pokračovat",
        ["login.signIn"] = "Přihlásit se",
        ["login.signingIn"] = "Přihlašuji…",
        ["login.username"] = "Uživatelské jméno",
        ["login.password"] = "Heslo",
        ["login.demoButton"] = "Použít demo účet",
        ["login.noResults"] = "Žádná škola nenalezena. Zkus zadat adresu školy níže.",
        ["login.loadingDirectory"] = "Načítám seznam škol…",
        ["login.2fa.title"] = "Dvoufázové ověření",
        ["login.2fa.subtitle"] = "Zadej ověřovací kód nebo potvrď přihlášení v mobilní aplikaci EduPage.",
        ["login.2fa.codePlaceholder"] = "Ověřovací kód",
        ["login.2fa.verify"] = "Ověřit kód",
        ["login.2fa.checkApproval"] = "Zkontrolovat potvrzení v aplikaci",
        ["login.2fa.resend"] = "Poslat oznámení znovu",
        ["login.child.title"] = "Vyber studenta",
        ["login.child.subtitle"] = "Vyber účet studenta, jehož data chceš zobrazit.",
        ["login.githubLink"] = "Open-source na GitHubu",

        // Today
        ["today.greeting.morning"] = "Dobré ráno, {0}",
        ["today.greeting.afternoon"] = "Dobré odpoledne, {0}",
        ["today.greeting.evening"] = "Dobrý večer, {0}",
        ["today.kpi.average"] = "PRŮMĚR",
        ["today.kpi.lessons"] = "HODIN DNES",
        ["today.kpi.newMarks"] = "NOVÉ ZNÁMKY",
        ["today.nowAndNext"] = "Teď a dál",
        ["today.current"] = "PRÁVĚ PROBÍHÁ · zbývá {0} min",
        ["today.nextIn"] = "DALŠÍ · za {0} min",
        ["today.nextAt"] = "DALŠÍ · začíná v {0}",
        ["today.noLessons"] = "Dnes nemáš žádné hodiny",
        ["today.afterSchool"] = "Pro dnešek máš hotovo",
        ["today.changes"] = "Změny v rozvrhu",
        ["today.recentMarks"] = "Poslední známky",
        ["today.noRecentMarks"] = "Zatím žádné známky.",
        ["today.planner"] = "Plánovač a úkoly",
        ["today.noPlanner"] = "Momentálně tě nic nečeká.",
        ["today.lunch"] = "Dnešní oběd",
        ["today.noMealOrdered"] = "Na dnešek nemáš objednaný oběd.",
        ["today.viewAll"] = "Otevřít",

        // Marks & Subjects
        ["marks.overallAverage"] = "Celkový průměr",
        ["marks.summary"] = "{0} předmětů · {1} známek",
        ["marks.subjects"] = "Předměty",
        ["marks.sort.focus"] = "Priorita",
        ["marks.sort.average"] = "Průměr",
        ["marks.schoolAverage"] = "Školní průměr",
        ["marks.calculatedAverage"] = "Vypočítaný průměr",
        ["marks.marksCount"] = "{0} známek",
        ["marks.absencePct"] = "Absence {0:F1} %",
        ["marks.weight"] = "Váha {0}",
        ["marks.inferredWeight"] = "~Váha {0}",
        ["marks.untitled"] = "Známka bez názvu",
        ["marks.whatIf.title"] = "Co-kdyby kalkulačka",
        ["marks.whatIf.placeholder"] = "Známka (např. 1, 1-, 2+)",
        ["marks.whatIf.weight"] = "Váha",
        ["marks.whatIf.better"] = "o {0:F2} lepší",
        ["marks.whatIf.worse"] = "o {0:F2} horší",
        ["marks.whatIf.unchanged"] = "Beze změny",
        ["marks.whatIf.pointsOnly"] = "Simulace průměru není pro bodové předměty dostupná.",
        ["marks.whatIf.remote"] = "Spočítáno přes Bakaláři",
        ["marks.whatIf.local"] = "Spočítáno lokálně",
        ["marks.history.title"] = "Vývoj průměru",
        ["marks.history.calculated"] = "Vypočítáno ze známek",
        ["marks.history.empty"] = "Pro vykreslení grafu chybí známky s datem.",
        ["marks.reportCard.subtitle"] = "Odhad {0} · {1} na hraně",
        ["marks.reportCard.subtitleClean"] = "Odhadovaný průměr {0}",

        // Timetable
        ["timetable.actual"] = "Aktuální",
        ["timetable.permanent"] = "Stálý",
        ["timetable.permanentBanner"] = "Zobrazen stálý rozvrh hodin.",
        ["timetable.lessonDetail"] = "Detail hodiny",
        ["timetable.time"] = "Čas",
        ["timetable.teacher"] = "Učitel",
        ["timetable.room"] = "Učebna",
        ["timetable.groups"] = "Skupiny",
        ["timetable.cycles"] = "Cykly",
        ["timetable.theme"] = "Téma hodiny",
        ["timetable.change.canceled"] = "Odpadá",
        ["timetable.change.substitution"] = "Suplování",
        ["timetable.change.roomChanged"] = "Změna učebny",
        ["timetable.change.added"] = "Přidaná hodina",
        ["timetable.addToPlanner"] = "Přidat do plánovače",
        ["timetable.noLessonsDay"] = "Volný den",

        // Absence
        ["absence.totalTitle"] = "Celková absence",
        ["absence.hours"] = "hodin",
        ["absence.limit"] = "Limit {0:F0} %",
        ["absence.unsolved"] = "Neřešeno",
        ["absence.ok"] = "Omluveno",
        ["absence.missed"] = "Neomluveno",
        ["absence.late"] = "Pozdní příchod",
        ["absence.soon"] = "Brzký odchod",
        ["absence.school"] = "Školní akce",
        ["absence.distance"] = "Distanční",
        ["absence.tab.subjects"] = "Předměty",
        ["absence.tab.days"] = "Dny",
        ["absence.tab.months"] = "Měsíce",
        ["absence.missedOfTotal"] = "Zameškáno {0} z {1} hodin",
        ["absence.untilLimit"] = "Zbývá {0} hod. do limitu",
        ["absence.overLimit"] = "Přes limit",
        ["absence.semester.canMiss"] = "Do konce pololetí můžeš chybět ještě {0}×",
        ["absence.semester.noMore"] = "Do konce pololetí už nesmíš chybět",
        ["absence.semester.over"] = "Přes limit i při plné docházce",
        ["absence.predictor.title"] = "Predikce absence",
        ["absence.predictor.subtitle"] = "Vyber budoucí hodiny a zjisti, jak ovlivní tvoje procenta.",
        ["absence.predictor.pickDate"] = "Vybrat datum",
        ["absence.predictor.addSelected"] = "Použít výběr",
        ["absence.localAdjusted"] = "Lokálně upraveno ({0} dnů) — školní záznamy se nikdy nemění.",
        ["absence.needsReview"] = "{0} lokálních úprav pozastaveno kvůli změně dat ze školy.",
        ["absence.hiddenTitle"] = "Lokální úpravy absence",
        ["absence.override.disclaimer"] = "Úpravy zůstávají pouze v tomto zařízení Windows a nikdy nemění školní evidenci.",
        ["absence.override.hideDay"] = "Skrýt celý den lokálně",
        ["absence.override.restoreDay"] = "Obnovit den",
        ["absence.totalRow"] = "Celkem",

        // Komens
        ["komens.received"] = "Přijaté",
        ["komens.noticeboard"] = "Nástěnka",
        ["komens.empty"] = "V této složce nejsou žádné zprávy.",
        ["komens.selectPrompt"] = "Vyber zprávu pro zobrazení.",
        ["komens.attachments"] = "Přílohy",
        ["komens.savedAttachment"] = "Uloženo do {0}",

        // Planner & Homework
        ["planner.upcoming"] = "Nadcházející",
        ["planner.completed"] = "Hotové",
        ["planner.newItem"] = "Nová položka",
        ["planner.editItem"] = "Upravit položku",
        ["planner.titlePlaceholder"] = "Název (např. Test z matematiky)",
        ["planner.notesPlaceholder"] = "Poznámky (volitelné)",
        ["planner.type"] = "Typ",
        ["planner.subject"] = "Předmět",
        ["planner.dueDate"] = "Termín",
        ["planner.schoolHomework"] = "Školní úkol",
        ["planner.markDone"] = "Označit jako hotové",
        ["planner.markNotDone"] = "Označit jako nesplněné",
        ["planner.type.Homework"] = "Úkol",
        ["planner.type.Test"] = "Test",
        ["planner.type.Presentation"] = "Prezentace",
        ["planner.type.Note"] = "Poznámka",
        ["planner.type.Task"] = "Úloha",

        // Report Card
        ["reportCard.currentEstimate"] = "Odhad aktuálního pololetí",
        ["reportCard.pastTerms"] = "Minulá vysvědčení",
        ["reportCard.written"] = "Uzavřeno · Průměr {0}",
        ["reportCard.estimated"] = "Průměr {0}",
        ["reportCard.borderline"] = "Na hraně · {0:F2} od {1}",
        ["reportCard.termTitle"] = "{0}. pololetí · {1}",
        ["reportCard.absentFooter"] = "Zameškáno: {0:F0} h · Neomluveno: {1:F0} h",

        // Strava.cz
        ["meals.connectTitle"] = "Připojit Strava.cz",
        ["meals.connectSubtitle"] = "Sleduj zůstatek na kontě a objednávej nebo ruš obědy.",
        ["meals.canteenNumber"] = "Číslo jídelny",
        ["meals.connect"] = "Připojit jídelnu",
        ["meals.disconnect"] = "Odpojit Strava.cz",
        ["meals.balance"] = "Zůstatek",
        ["meals.ordered"] = "OBJEDNÁNO",
        ["meals.canteen"] = "JÍDELNA",
        ["meals.replaceTitle"] = "Nahradit objednané jídlo?",
        ["meals.replaceBody"] = "Nahradit „{0}“ jídlem „{1}“?",
        ["meals.locked"] = "Uzavřeno",
        ["meals.empty"] = "Žádné nadcházející obědy nejsou k dispozici.",

        // Settings
        ["settings.account"] = "Účet",
        ["settings.services"] = "Připojené služby",
        ["settings.preferences"] = "Předvolby aplikace",
        ["settings.about"] = "O aplikaci Gradey",
        ["settings.theme"] = "Vzhled",
        ["settings.theme.system"] = "Podle systému",
        ["settings.theme.light"] = "Světlý",
        ["settings.theme.dark"] = "Tmavý",
        ["settings.language"] = "Jazyk",
        ["settings.language.system"] = "Podle systému",
        ["settings.language.czech"] = "Čeština",
        ["settings.language.english"] = "English",
        ["settings.chronicallyOnline"] = "Chronically online styl",
        ["settings.chronicallyOnlineDesc"] = "Neformální styl malými písmeny napříč aplikací.",
        ["settings.showMealsTab"] = "Zobrazit záložku Jídelna (Strava.cz)",
        ["settings.semesterAllowance"] = "Zobrazovat zbývající povolenou absenci v pololetí",
        ["settings.switchStudent"] = "Přepnout studenta",
        ["settings.privacyNote"] = "Gradey ukládá přihlašovací údaje lokálně pomocí šifrování Windows DPAPI a komunikuje přímo se školou přes HTTPS."
    };
}
