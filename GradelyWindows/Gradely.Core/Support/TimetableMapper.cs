using System.Globalization;
using Gradely.Core.Models;

namespace Gradely.Core.Support;

public static class TimetableMapper
{
    public static DateOnly MondayOfWeek(DateOnly date)
    {
        int diff = ((int)date.DayOfWeek - (int)DayOfWeek.Monday + 7) % 7;
        return date.AddDays(-diff);
    }

    public static TimetableWeek Map(TimetableResponse response, TimetableKind kind, DateOnly? requestedWeekStart = null)
    {
        // IMPORTANT: Lookups MUST use raw untrimmed IDs because Bakaláři IDs can have leading/internal spaces.
        var hoursById = new Dictionary<int, TimetableHour>();
        var hourOrder = new Dictionary<int, int>();
        for (int i = 0; i < response.Hours.Count; i++)
        {
            var h = response.Hours[i];
            hoursById.TryAdd(h.Id, h);
            hourOrder.TryAdd(h.Id, i);
        }

        var subjects = BuildEntityMap(response.Subjects);
        var teachers = BuildEntityMap(response.Teachers);
        var rooms = BuildEntityMap(response.Rooms);
        var cycles = BuildEntityMap(response.Cycles);
        var groups = new Dictionary<string, TimetableGroup>(StringComparer.Ordinal);
        foreach (var g in response.Groups) groups.TryAdd(g.Id, g);

        var allCycleKeys = cycles.Keys.ToHashSet(StringComparer.Ordinal);
        var mappedDays = new List<TimetableDay>(response.Days.Count);

        foreach (var dayDto in response.Days.OrderBy(d => d.DayOfWeek))
        {
            DateOnly? parsedDate = null;
            if (!string.IsNullOrWhiteSpace(dayDto.Date) && dayDto.Date.Length >= 10 &&
                DateOnly.TryParseExact(dayDto.Date[..10], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
            {
                parsedDate = d;
            }

            var dayId = kind == TimetableKind.Permanent || string.IsNullOrWhiteSpace(dayDto.Date)
                ? $"dow-{dayDto.DayOfWeek}"
                : dayDto.Date;

            var lessons = new List<TimetableLesson>(dayDto.Atoms.Count);
            for (int offset = 0; offset < dayDto.Atoms.Count; offset++)
            {
                var atom = dayDto.Atoms[offset];
                if (!hoursById.TryGetValue(atom.HourId, out var hour))
                    hour = new TimetableHour { Id = atom.HourId, Caption = atom.HourId.ToString(CultureInfo.InvariantCulture) };

                var changeKind = ParseChangeKind(atom.Change?.ChangeType);

                string subjName = string.Empty;
                string subjAbbrev = string.Empty;
                if (atom.SubjectId is not null && subjects.TryGetValue(atom.SubjectId, out var subj))
                {
                    subjName = subj.Name.Trim();
                    subjAbbrev = subj.Abbrev.Trim();
                }

                if (string.IsNullOrEmpty(subjName))
                {
                    var fallback = atom.Change?.TypeName?.Trim();
                    if (!string.IsNullOrEmpty(fallback)) subjName = fallback;
                    else if (!string.IsNullOrEmpty(atom.Change?.Description)) subjName = atom.Change.Description.Trim();
                    else subjName = subjAbbrev;
                }

                if (string.IsNullOrEmpty(subjAbbrev))
                {
                    subjAbbrev = !string.IsNullOrEmpty(atom.Change?.TypeAbbrev)
                        ? atom.Change.TypeAbbrev.Trim()
                        : (subjName.Length <= 4 ? subjName : subjName[..Math.Min(3, subjName.Length)]);
                }

                string? teacherName = null;
                string? teacherAbbrev = null;
                if (atom.TeacherId is not null && teachers.TryGetValue(atom.TeacherId, out var t))
                {
                    teacherName = string.IsNullOrWhiteSpace(t.Name) ? t.Abbrev.Trim() : t.Name.Trim();
                    teacherAbbrev = string.IsNullOrWhiteSpace(t.Abbrev) ? null : t.Abbrev.Trim();
                }

                string? roomName = null;
                if (atom.RoomId is not null && rooms.TryGetValue(atom.RoomId, out var r))
                {
                    roomName = string.IsNullOrWhiteSpace(r.Abbrev) ? r.Name.Trim() : r.Abbrev.Trim();
                }

                var groupNames = new List<string>();
                foreach (var gid in atom.GroupIds)
                {
                    if (groups.TryGetValue(gid, out var g))
                    {
                        var label = string.IsNullOrWhiteSpace(g.Abbrev) ? g.Name.Trim() : g.Abbrev.Trim();
                        if (!string.IsNullOrEmpty(label)) groupNames.Add(label);
                    }
                }

                var lessonCycles = new List<string>();
                if (kind == TimetableKind.Permanent && allCycleKeys.Count > 0)
                {
                    var atomCycleSet = atom.CycleIds.ToHashSet(StringComparer.Ordinal);
                    if (!atomCycleSet.IsSupersetOf(allCycleKeys))
                    {
                        foreach (var cid in atom.CycleIds)
                        {
                            if (cycles.TryGetValue(cid, out var c))
                            {
                                var label = string.IsNullOrWhiteSpace(c.Abbrev) ? c.Name.Trim() : c.Abbrev.Trim();
                                if (!string.IsNullOrEmpty(label)) lessonCycles.Add(label);
                            }
                        }
                    }
                }

                var theme = string.IsNullOrWhiteSpace(atom.Theme) ? null : atom.Theme.Trim();
                lessons.Add(new TimetableLesson(
                    $"{dayId}#{atom.HourId}#{offset}",
                    hour,
                    atom.SubjectId,
                    subjName,
                    subjAbbrev,
                    teacherName,
                    teacherAbbrev,
                    roomName,
                    atom.GroupIds.ToList(),
                    groupNames,
                    lessonCycles,
                    theme,
                    atom.Change,
                    changeKind,
                    atom.HomeworkIds.ToList()));
            }

            lessons.Sort((a, b) =>
            {
                var oa = hourOrder.TryGetValue(a.Hour.Id, out var ia) ? ia : int.MaxValue;
                var ob = hourOrder.TryGetValue(b.Hour.Id, out var ib) ? ib : int.MaxValue;
                return oa.CompareTo(ob);
            });

            mappedDays.Add(new TimetableDay(
                dayId,
                dayDto.DayOfWeek,
                parsedDate,
                dayDto.DayDescription?.Trim() ?? string.Empty,
                ParseDayType(dayDto.DayType),
                lessons));
        }

        var weekStart = requestedWeekStart ?? mappedDays.Where(d => d.Date.HasValue).Select(d => MondayOfWeek(d.Date!.Value)).FirstOrDefault();
        return new TimetableWeek(kind, weekStart == default ? null : weekStart, response.Hours, mappedDays);
    }

    public static TimetableResponse RebaseToWeek(TimetableResponse source, DateOnly weekDate)
    {
        var monday = MondayOfWeek(weekDate);
        return new TimetableResponse
        {
            Hours = source.Hours,
            Classes = source.Classes,
            Groups = source.Groups,
            Subjects = source.Subjects,
            Teachers = source.Teachers,
            Rooms = source.Rooms,
            Cycles = source.Cycles,
            Days = source.Days.Select(d => new TimetableDayDto
            {
                Atoms = d.Atoms,
                DayOfWeek = d.DayOfWeek,
                Date = d.DayOfWeek is >= 1 and <= 7
                    ? monday.AddDays(d.DayOfWeek - 1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                    : d.Date,
                DayDescription = d.DayDescription,
                DayType = d.DayType
            }).ToList()
        };
    }

    public static TimetableTodaySummary? BuildTodaySummary(TimetableWeek week, DateTime now)
    {
        var today = DateOnly.FromDateTime(now);
        var day = week.Days.FirstOrDefault(d => d.Date == today);
        if (day is null) return null;

        var timed = new List<TimedLesson>();
        foreach (var lesson in day.Lessons)
        {
            if (TryParseTime(lesson.Hour.BeginTime, out var begin) &&
                TryParseTime(lesson.Hour.EndTime, out var end) &&
                end > begin)
            {
                timed.Add(new TimedLesson(lesson, today.ToDateTime(begin), today.ToDateTime(end)));
            }
        }

        timed.Sort((a, b) =>
        {
            int c = a.Start.CompareTo(b.Start);
            if (c != 0) return c;
            c = a.End.CompareTo(b.End);
            if (c != 0) return c;
            c = a.Lesson.Hour.Id.CompareTo(b.Lesson.Hour.Id);
            return c != 0 ? c : string.Compare(a.Lesson.Id, b.Lesson.Id, StringComparison.Ordinal);
        });

        var changed = timed
            .Where(t => t.End > now && t.Lesson.HasChange)
            .GroupBy(t => (t.Start, t.End, t.Lesson.Hour.Id, t.Lesson.SubjectName, t.Lesson.ChangeKind, t.Lesson.RoomName))
            .Select(g => g.First())
            .ToList();

        var active = timed.Where(t => !t.Lesson.IsCanceled).ToList();
        if (active.Count == 0)
        {
            var state = day.Lessons.Count == 0 ? TodayLessonState.Empty : TodayLessonState.AfterSchool;
            return new TimetableTodaySummary(state, null, null, null, null, 0, timed, changed);
        }

        var current = active.FirstOrDefault(t => t.Start <= now && now < t.End);
        if (current is not null)
        {
            var next = active.FirstOrDefault(t => t.Start >= current.End);
            int rem = Math.Max(0, (int)Math.Ceiling((current.End - now).TotalMinutes));
            double progress = Math.Clamp((now - current.Start).TotalSeconds / (current.End - current.Start).TotalSeconds, 0.0, 1.0);
            return new TimetableTodaySummary(TodayLessonState.Current, current, next, rem, null, progress, timed, changed);
        }

        var upcoming = active.FirstOrDefault(t => t.Start > now);
        if (upcoming is not null)
        {
            var state = ReferenceEquals(upcoming, active[0]) ? TodayLessonState.BeforeSchool : TodayLessonState.BetweenLessons;
            int until = Math.Max(0, (int)Math.Ceiling((upcoming.Start - now).TotalMinutes));
            return new TimetableTodaySummary(state, null, upcoming, null, until, 0, timed, changed);
        }

        return new TimetableTodaySummary(TodayLessonState.AfterSchool, null, null, null, null, 0, timed, changed);
    }

    public static bool TryParseTime(string? raw, out TimeOnly time)
    {
        time = default;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        var parts = raw.Trim().Split(':');
        if (parts.Length < 2) return false;
        if (!int.TryParse(parts[0], out var h) || !int.TryParse(parts[1], out var m)) return false;
        if (h is < 0 or > 23 || m is < 0 or > 59) return false;
        time = new TimeOnly(h, m);
        return true;
    }

    public static TimetableDayType ParseDayType(string? raw) => (raw?.Trim() ?? string.Empty) switch
    {
        "WorkDay" => TimetableDayType.WorkDay,
        "Weekend" => TimetableDayType.Weekend,
        "Celebration" => TimetableDayType.Celebration,
        "Holiday" => TimetableDayType.Holiday,
        "DirectorDay" => TimetableDayType.DirectorDay,
        _ => TimetableDayType.Undefined
    };

    public static LessonChangeKind ParseChangeKind(string? raw)
    {
        var s = raw?.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(s)) return LessonChangeKind.None;
        return s switch
        {
            "canceled" or "cancelled" or "removed" => LessonChangeKind.Canceled,
            "roomchanged" => LessonChangeKind.RoomChanged,
            "added" => LessonChangeKind.Added,
            _ => LessonChangeKind.Substitution
        };
    }

    private static Dictionary<string, TimetableEntity> BuildEntityMap(List<TimetableEntity> entities)
    {
        var map = new Dictionary<string, TimetableEntity>(StringComparer.Ordinal);
        foreach (var e in entities)
            map.TryAdd(e.Id, e);
        return map;
    }
}
