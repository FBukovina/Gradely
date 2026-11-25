import type {
  AbsenceDay,
  AbsenceRiskLevel,
  AbsenceSnapshot,
  DayType,
  GradeBand,
  LessonChangeKind,
  MarkItem,
  ScheduledDay,
  ScheduledLesson,
  SubjectMarks,
  TimetableHour,
  TimetableKind,
  TimetableWeek,
} from "./types.ts";

// MARK: - GradeMath (1:1 port of Gradely/Support/GradeMath.swift)

export type MarkWeightSource = "explicit" | "inferred" | "fallback";

export interface ResolvedMarkWeight {
  value: number;
  source: MarkWeightSource;
}

export interface PreparedGradeCalculation {
  subjectID: string;
  weightedSum: number;
  totalWeight: number;
  calculatedAverage: number | null;
  officialAverage: number | null;
  resolvedWeights: Record<string, ResolvedMarkWeight>;
  excludedMarkCount: number;
  canSimulate: boolean;
}

export interface GradeSimulationResult {
  baselineAverage: number | null;
  estimatedAverage: number;
  difference: number | null;
}

const MODIFIER_VALUES: Record<string, number> = {
  "1+": 1.3,
  "1-": 1.7,
  "2+": 2.3,
  "2-": 2.7,
  "3+": 3.3,
  "3-": 3.7,
  "4+": 4.3,
  "4-": 4.7,
  "5+": 5.3,
  "5-": 5.7,
};

const MAX_INFERENCE_GROUPS = 4;
const AVERAGE_PRECISION = 100;

export function parseMarkValue(markText: string): number | null {
  const trimmed = markText.trim();
  if (!trimmed) return null;
  if (trimmed in MODIFIER_VALUES) {
    return MODIFIER_VALUES[trimmed] ?? null;
  }
  const numeric = Number(trimmed.replace(",", "."));
  return Number.isFinite(numeric) ? numeric : null;
}

export function parseAverageText(averageText: string | null | undefined): number | null {
  if (!averageText) return null;
  const normalized = averageText.trim().replace(",", ".");
  if (!normalized) return null;
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

export function gradeBandForAverage(average: number | null | undefined): GradeBand {
  if (average == null || !Number.isFinite(average)) return "neutral";
  if (average <= 1.5) return "excellent";
  if (average <= 2.5) return "good";
  if (average <= 3.5) return "average";
  return "poor";
}

export function gradeBandForMark(mark: Pick<MarkItem, "isPoints" | "markText">): GradeBand {
  if (mark.isPoints) return "excellent";
  return gradeBandForMarkText(mark.markText);
}

export function gradeBandForMarkText(markText: string): GradeBand {
  switch (markText.trim()) {
    case "1":
    case "1+":
    case "1-":
      return "excellent";
    case "2":
    case "2+":
    case "2-":
      return "good";
    case "3":
    case "3+":
    case "3-":
      return "average";
    case "4":
    case "4+":
    case "4-":
    case "5":
    case "5+":
    case "5-":
      return "poor";
    default:
      return "neutral";
  }
}

export function formatAverage(average: number | null | undefined, locale = "en"): string {
  if (average == null || !Number.isFinite(average)) return "–";
  const formatted = average.toFixed(2);
  return locale.startsWith("cs") ? formatted.replace(".", ",") : formatted;
}

export function formatWeight(weight: number): string {
  if (!Number.isFinite(weight)) return "–";
  if (Math.round(weight) === weight) return String(Math.round(weight));
  return String(Number(weight.toFixed(2)));
}

function explicitWeightValue(weight: number | null | undefined): number | null {
  if (weight == null || !Number.isFinite(weight) || weight <= 0) return null;
  return weight;
}

function isLocallyGradableMark(mark: MarkItem): boolean {
  return !mark.isPoints && mark.type !== "unsupported";
}

function isSupportedGradeValue(value: number): boolean {
  return value >= 1.0 && value <= 5.7;
}

function normalizeLabel(value: string | null | undefined): string | null {
  if (!value) return null;
  const folded = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .join(" ")
    .trim();
  return folded.length > 0 ? folded : null;
}

type LabelField = "typeNote" | "type" | "caption";
const LABEL_FIELDS: LabelField[] = ["typeNote", "type", "caption"];

function primaryLabelField(mark: MarkItem): LabelField | null {
  for (const field of LABEL_FIELDS) {
    if (normalizeLabel(mark[field]) != null) return field;
  }
  return null;
}

function inferenceLabel(mark: MarkItem): string | null {
  const field = primaryLabelField(mark);
  return field ? normalizeLabel(mark[field]) : null;
}

function canonicalMarkKey(mark: MarkItem): string {
  return [
    mark.id,
    mark.subjectID,
    mark.markDate,
    mark.markText.trim(),
    mark.type,
    mark.typeNote ?? "",
    mark.caption ?? "",
    mark.theme ?? "",
    mark.weight == null ? "nil" : String(mark.weight),
    mark.isPoints ? "points" : "grade",
    mark.pointsText ?? "",
    mark.maxPoints == null ? "" : String(mark.maxPoints),
  ].join("\u001F");
}

function matchesDisplayedAverage(candidate: number, target: number): boolean {
  return Math.round(candidate * AVERAGE_PRECISION) === Math.round(target * AVERAGE_PRECISION);
}

function resolveWeightsForUniqueMarks(
  marks: MarkItem[],
  averageText: string | null,
): Record<string, ResolvedMarkWeight> {
  const resolved: Record<string, ResolvedMarkWeight> = {};

  for (const mark of marks) {
    const explicit = explicitWeightValue(mark.weight);
    if (explicit != null) {
      resolved[mark.id] = { value: explicit, source: "explicit" };
    }
  }

  for (const mark of marks) {
    if (mark.weight == null && isLocallyGradableMark(mark) && !(mark.id in resolved)) {
      const field = primaryLabelField(mark);
      const label = field ? normalizeLabel(mark[field]) : null;
      if (!field || !label) continue;
      const matching = new Set<number>();
      for (const candidate of marks) {
        if (candidate.id === mark.id || candidate.isPoints) continue;
        if (normalizeLabel(candidate[field]) !== label) continue;
        const w = explicitWeightValue(candidate.weight);
        if (w != null) matching.add(w);
      }
      if (matching.size === 1) {
        const [inferredWeight] = matching;
        if (inferredWeight != null) {
          resolved[mark.id] = { value: inferredWeight, source: "inferred" };
        }
      }
    }
  }

  const target = parseAverageText(averageText);
  if (target != null) {
    const hiddenLabels: string[] = [];
    const seen = new Set<string>();
    for (const mark of marks) {
      if (mark.weight == null && isLocallyGradableMark(mark) && !(mark.id in resolved)) {
        const label = inferenceLabel(mark);
        if (label && !seen.has(label)) {
          seen.add(label);
          hiddenLabels.push(label);
        }
      }
    }

    if (hiddenLabels.length > 0 && hiddenLabels.length <= MAX_INFERENCE_GROUPS) {
      const matches: Array<Record<string, number>> = [];
      const current: Record<string, number> = {};

      const search = (idx: number) => {
        if (matches.length > 1) return;
        if (idx === hiddenLabels.length) {
          let totalWeight = 0;
          let weightedSum = 0;
          for (const mark of marks) {
            if (!isLocallyGradableMark(mark)) continue;
            const val = parseMarkValue(mark.markText);
            if (val == null) continue;
            const label = inferenceLabel(mark);
            const w =
              resolved[mark.id]?.value ??
              (label != null && current[label] != null ? current[label]! : 1);
            totalWeight += w;
            weightedSum += val * w;
          }
          if (totalWeight > 0 && matchesDisplayedAverage(weightedSum / totalWeight, target)) {
            matches.push({ ...current });
          }
          return;
        }
        const label = hiddenLabels[idx]!;
        for (let w = 1; w <= 10; w += 1) {
          current[label] = w;
          search(idx + 1);
        }
        delete current[label];
      };

      search(0);
      if (matches.length === 1) {
        const found = matches[0]!;
        for (const mark of marks) {
          if (mark.weight == null && isLocallyGradableMark(mark) && !(mark.id in resolved)) {
            const label = inferenceLabel(mark);
            if (label && found[label] != null) {
              resolved[mark.id] = { value: found[label]!, source: "inferred" };
            }
          }
        }
      }
    }
  }

  return resolved;
}

export function prepareSubjectCalculation(subject: SubjectMarks): PreparedGradeCalculation {
  let excludedMarkCount = 0;
  const grouped = new Map<string, MarkItem[]>();
  for (const mark of subject.marks) {
    const id = mark.id || canonicalMarkKey(mark);
    const list = grouped.get(id) ?? [];
    list.push(mark);
    grouped.set(id, list);
  }

  const uniqueMarks: MarkItem[] = [];
  for (const [, group] of [...grouped.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const first = group[0];
    if (!first) continue;
    if (group.length > 1) {
      const distinctRecords = new Set(group.map(canonicalMarkKey));
      if (distinctRecords.size > 1) {
        excludedMarkCount += group.length;
        continue;
      }
      excludedMarkCount += group.length - 1;
    }

    const value = parseMarkValue(first.markText);
    if (
      subject.pointsOnly ||
      !isLocallyGradableMark(first) ||
      value == null ||
      !isSupportedGradeValue(value)
    ) {
      excludedMarkCount += 1;
      continue;
    }
    if (first.weight != null && explicitWeightValue(first.weight) == null) {
      excludedMarkCount += 1;
      continue;
    }
    uniqueMarks.push(first);
  }

  const resolvedWeights = resolveWeightsForUniqueMarks(uniqueMarks, subject.averageText);
  let weightedSum = 0;
  let totalWeight = 0;
  for (const mark of uniqueMarks) {
    const value = parseMarkValue(mark.markText);
    if (value == null) continue;
    const weight = resolvedWeights[mark.id] ?? { value: 1, source: "fallback" as const };
    resolvedWeights[mark.id] = weight;
    weightedSum += value * weight.value;
    totalWeight += weight.value;
  }

  const calculatedAverage = totalWeight > 0 ? weightedSum / totalWeight : null;
  const officialAverage = parseAverageText(subject.averageText);

  return {
    subjectID: subject.id,
    weightedSum,
    totalWeight,
    calculatedAverage,
    officialAverage,
    resolvedWeights,
    excludedMarkCount,
    canSimulate: !subject.pointsOnly && (totalWeight > 0 || subject.marks.length === 0),
  };
}

export function subjectAverage(subject: SubjectMarks): number | null {
  const official = parseAverageText(subject.averageText);
  if (official != null) return official;
  return prepareSubjectCalculation(subject).calculatedAverage;
}

/** Study average across subjects is the arithmetic mean of subject averages (GradeMath.overallAverage). */
export function overallStudyAverage(subjects: SubjectMarks[]): number | null {
  const averages = subjects
    .map(subjectAverage)
    .filter((v): v is number => v != null && Number.isFinite(v));
  if (averages.length === 0) return null;
  return averages.reduce((acc, v) => acc + v, 0) / averages.length;
}

export function simulateSubjectGrade(
  prepared: PreparedGradeCalculation,
  markText: string,
  weight: number,
): GradeSimulationResult | null {
  const value = parseMarkValue(markText);
  if (value == null || !isSupportedGradeValue(value)) return null;
  const clampedWeight = Math.min(10, Math.max(1, Math.round(weight)));
  const sum = prepared.weightedSum + value * clampedWeight;
  const totalWeight = prepared.totalWeight + clampedWeight;
  if (!Number.isFinite(sum) || !Number.isFinite(totalWeight) || totalWeight <= 0) return null;
  const estimatedAverage = sum / totalWeight;
  return {
    baselineAverage: prepared.calculatedAverage ?? prepared.officialAverage,
    estimatedAverage,
    difference:
      prepared.calculatedAverage != null
        ? estimatedAverage - prepared.calculatedAverage
        : prepared.officialAverage != null
          ? estimatedAverage - prepared.officialAverage
          : null,
  };
}

// MARK: - Absence Summary & Risk (1:1 port of AbsenceSummary.swift & AbsenceRisk.swift)

export interface AbsenceCounts {
  unsolved: number;
  ok: number;
  missed: number;
  late: number;
  soon: number;
  school: number;
  distanceTeaching: number;
  total: number;
}

export interface AbsenceSubjectRiskRow {
  id: string;
  subjectName: string;
  missedLessons: number;
  totalLessons: number;
  percentage: number;
  threshold: number | null;
  level: AbsenceRiskLevel;
  missesUntilLimit: number | null;
  exceedsThreshold: boolean;
}

export function normalizeAbsenceThreshold(threshold: number | null | undefined): number | null {
  if (threshold == null || !Number.isFinite(threshold) || threshold <= 0) return null;
  return threshold <= 1 ? threshold * 100 : threshold;
}

export function absenceRiskLevel(
  percentage: number,
  normalizedThreshold: number | null,
): AbsenceRiskLevel {
  if (normalizedThreshold == null || normalizedThreshold <= 0) return "unavailable";
  const ratio = percentage / normalizedThreshold;
  if (ratio >= 1) return "overLimit";
  if (ratio >= 0.9) return "high";
  if (ratio >= 0.7) return "watch";
  return "safe";
}

export function missesUntilAbsenceLimit(
  missedLessons: number,
  totalLessons: number,
  normalizedThreshold: number | null,
): number | null {
  if (normalizedThreshold == null || normalizedThreshold <= 0 || totalLessons <= 0) return null;
  const thresholdRatio = normalizedThreshold / 100;
  if (thresholdRatio >= 1) return null;
  if (missedLessons / totalLessons >= thresholdRatio) return 0;

  for (let futureMisses = 1; futureMisses < 10_000; futureMisses += 1) {
    if ((missedLessons + futureMisses) / (totalLessons + futureMisses) >= thresholdRatio) {
      return futureMisses;
    }
  }
  return null;
}

export function sumAbsenceDays(days: AbsenceDay[]): AbsenceCounts {
  const counts: AbsenceCounts = {
    unsolved: 0,
    ok: 0,
    missed: 0,
    late: 0,
    soon: 0,
    school: 0,
    distanceTeaching: 0,
    total: 0,
  };
  for (const day of days) {
    counts.unsolved += day.unsolved;
    counts.ok += day.ok;
    counts.missed += day.missed;
    counts.late += day.late;
    counts.soon += day.soon;
    counts.school += day.school;
    counts.distanceTeaching += day.distanceTeaching;
  }
  counts.total =
    counts.unsolved +
    counts.ok +
    counts.missed +
    counts.late +
    counts.soon +
    counts.school +
    counts.distanceTeaching;
  return counts;
}

export function buildSubjectAbsenceRisks(snapshot: AbsenceSnapshot): AbsenceSubjectRiskRow[] {
  const threshold = normalizeAbsenceThreshold(snapshot.percentageThreshold);
  return snapshot.absencesPerSubject
    .map((item, idx) => {
      const percentage = item.lessonsCount > 0 ? (item.base / item.lessonsCount) * 100 : 0;
      const level = absenceRiskLevel(percentage, threshold);
      const exceedsThreshold = threshold != null && threshold > 0 && percentage >= threshold;
      return {
        id: `${idx}-${item.subjectName.trim()}`,
        subjectName: item.subjectName.trim(),
        missedLessons: item.base,
        totalLessons: item.lessonsCount,
        percentage,
        threshold,
        level,
        missesUntilLimit: missesUntilAbsenceLimit(item.base, item.lessonsCount, threshold),
        exceedsThreshold,
      };
    })
    .sort((a, b) => {
      if (a.exceedsThreshold !== b.exceedsThreshold) {
        return a.exceedsThreshold ? -1 : 1;
      }
      if (a.percentage !== b.percentage) {
        return b.percentage - a.percentage;
      }
      return a.subjectName.localeCompare(b.subjectName, "cs");
    });
}

// MARK: - TimetableMapper & Today Lesson Resolution (1:1 port of TimetableMapper.swift)

export function parseLessonChangeKind(changeType: string | null | undefined): LessonChangeKind {
  const raw = changeType?.trim().toLowerCase() ?? "";
  if (!raw) return "none";
  if (raw === "canceled" || raw === "cancelled" || raw === "removed") return "canceled";
  if (raw === "roomchanged") return "roomChanged";
  if (raw === "added") return "added";
  return "substitution";
}

export function parseDayType(apiValue: string | null | undefined): DayType {
  switch (apiValue) {
    case "WorkDay":
      return "workDay";
    case "Weekend":
      return "weekend";
    case "Celebration":
      return "celebration";
    case "Holiday":
      return "holiday";
    case "DirectorDay":
      return "directorDay";
    default:
      return "undefined";
  }
}

export function mapRawTimetableToWeek(
  raw: Record<string, any>,
  weekStart: string,
  kind: TimetableKind = "weekly",
  now: Date = new Date(),
): TimetableWeek {
  // Bakaláři entity IDs can contain leading or inner spaces (e.g. " 6", "U  12").
  // Lookup MUST match raw IDs and only trim resolved display strings.
  const indexEntities = (items: unknown): Map<string, { id: string; abbrev: string; name: string }> => {
    const map = new Map<string, { id: string; abbrev: string; name: string }>();
    if (!Array.isArray(items)) return map;
    for (const item of items) {
      if (item && typeof item === "object") {
        const id = String(item.Id ?? item.id ?? "");
        if (!map.has(id)) {
          map.set(id, {
            id,
            abbrev: String(item.Abbrev ?? item.abbrev ?? ""),
            name: String(item.Name ?? item.name ?? ""),
          });
        }
      }
    }
    return map;
  };

  const subjects = indexEntities(raw.Subjects ?? raw.subjects);
  const teachers = indexEntities(raw.Teachers ?? raw.teachers);
  const rooms = indexEntities(raw.Rooms ?? raw.rooms);
  const groups = indexEntities(raw.Groups ?? raw.groups);
  const cycles = indexEntities(raw.Cycles ?? raw.cycles);

  const hours: TimetableHour[] = Array.isArray(raw.Hours ?? raw.hours)
    ? (raw.Hours ?? raw.hours).map((h: any) => ({
        id: Number(h.Id ?? h.id ?? 0),
        caption: String(h.Caption ?? h.caption ?? "").trim(),
        beginTime: String(h.BeginTime ?? h.beginTime ?? "").trim(),
        endTime: String(h.EndTime ?? h.endTime ?? "").trim(),
      }))
    : [];

  const hoursById = new Map<number, TimetableHour>();
  const hourOrder = new Map<number, number>();
  hours.forEach((h, idx) => {
    if (!hoursById.has(h.id)) hoursById.set(h.id, h);
    hourOrder.set(h.id, idx);
  });

  const todayPrague = pragueDateString(now);

  const trimOrNull = (v: string | null | undefined): string | null => {
    if (!v) return null;
    const t = v.trim();
    return t.length > 0 ? t : null;
  };

  const rawDays = Array.isArray(raw.Days ?? raw.days) ? (raw.Days ?? raw.days) : [];
  const days: ScheduledDay[] = rawDays.map((dto: any) => {
    const rawDate = String(dto.Date ?? dto.date ?? "");
    const dateKey = kind === "permanent" || !rawDate ? null : rawDate.slice(0, 10);
    const dayOfWeek = Number(dto.DayOfWeek ?? dto.dayOfWeek ?? 0);
    const dayID = dateKey ?? `dow-${dayOfWeek}`;
    const rawAtoms = Array.isArray(dto.Atoms ?? dto.atoms) ? (dto.Atoms ?? dto.atoms) : [];

    const lessons: ScheduledLesson[] = rawAtoms
      .map((atom: any, offset: number): ScheduledLesson => {
        const hourID = Number(atom.HourId ?? atom.hourID ?? 0);
        const hour = hoursById.get(hourID) ?? {
          id: hourID,
          caption: String(hourID),
          beginTime: "",
          endTime: "",
        };
        const rawSubjectId = atom.SubjectId ?? atom.subjectID ?? null;
        const rawTeacherId = atom.TeacherId ?? atom.teacherID ?? null;
        const rawRoomId = atom.RoomId ?? atom.roomID ?? null;
        const subject = rawSubjectId != null ? subjects.get(String(rawSubjectId)) : undefined;
        const teacher = rawTeacherId != null ? teachers.get(String(rawTeacherId)) : undefined;
        const room = rawRoomId != null ? rooms.get(String(rawRoomId)) : undefined;
        const groupIds: string[] = Array.isArray(atom.GroupIds ?? atom.groupIDs)
          ? (atom.GroupIds ?? atom.groupIDs).map(String)
          : [];
        const cycleIds: string[] = Array.isArray(atom.CycleIds ?? atom.cycleIDs)
          ? (atom.CycleIds ?? atom.cycleIDs).map(String)
          : [];
        const homeworkIDs: string[] = Array.isArray(atom.HomeworkIds ?? atom.homeworkIDs)
          ? (atom.HomeworkIds ?? atom.homeworkIDs).map(String)
          : [];
        const rawChange = atom.Change ?? atom.change ?? null;
        const change = rawChange
          ? {
              changeSubject: trimOrNull(rawChange.ChangeSubject ?? rawChange.changeSubject),
              day: trimOrNull(rawChange.Day ?? rawChange.day),
              hours: trimOrNull(rawChange.Hours ?? rawChange.hours),
              changeType: trimOrNull(rawChange.ChangeType ?? rawChange.changeType),
              description: trimOrNull(rawChange.Description ?? rawChange.description),
              time: trimOrNull(rawChange.Time ?? rawChange.time),
              typeAbbrev: trimOrNull(rawChange.TypeAbbrev ?? rawChange.typeAbbrev),
              typeName: trimOrNull(rawChange.TypeName ?? rawChange.typeName),
            }
          : null;

        return {
          id: `${dayID}#${hourID}#${offset}`,
          hour,
          subjectID: rawSubjectId != null ? String(rawSubjectId).trim() : null,
          subjectName: trimOrNull(subject?.name),
          subjectAbbrev: trimOrNull(subject?.abbrev),
          teacherName: trimOrNull(teacher?.name),
          teacherAbbrev: trimOrNull(teacher?.abbrev),
          roomName: trimOrNull(room?.name),
          roomAbbrev: trimOrNull(room?.abbrev),
          groups: groupIds
            .map((gid) => trimOrNull(groups.get(gid)?.abbrev))
            .filter((v): v is string => v != null),
          cycles:
            kind === "permanent"
              ? cycleIds
                  .map((cid) => trimOrNull(cycles.get(cid)?.name ?? cycles.get(cid)?.abbrev))
                  .filter((v): v is string => v != null)
              : [],
          theme: trimOrNull(atom.Theme ?? atom.theme),
          hasHomework: homeworkIDs.length > 0,
          homeworkIDs,
          change,
          changeKind: parseLessonChangeKind(change?.changeType),
        };
      })
      .sort(
        (a: ScheduledLesson, b: ScheduledLesson) =>
          (hourOrder.get(a.hour.id) ?? Number.MAX_SAFE_INTEGER) -
          (hourOrder.get(b.hour.id) ?? Number.MAX_SAFE_INTEGER),
      );

    return {
      id: dayID,
      date: dateKey,
      dayOfWeek,
      dayType: kind === "permanent" ? "workDay" : parseDayType(dto.DayType ?? dto.dayType),
      dayDescription:
        kind === "permanent" ? "" : String(dto.DayDescription ?? dto.dayDescription ?? "").trim(),
      lessons,
      isToday: dateKey === todayPrague,
    };
  });

  return {
    weekStart,
    kind,
    hours,
    days,
  };
}

export function pragueDateString(date: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Prague",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const y = parts.find((p) => p.type === "year")?.value ?? "2026";
  const m = parts.find((p) => p.type === "month")?.value ?? "01";
  const d = parts.find((p) => p.type === "day")?.value ?? "01";
  return `${y}-${m}-${d}`;
}

export function mondayOfWeek(dateInput: string | Date): string {
  const iso = typeof dateInput === "string" ? dateInput.slice(0, 10) : pragueDateString(dateInput);
  const [y, m, d] = iso.split("-").map(Number);
  const utc = new Date(Date.UTC(y || 2026, (m || 1) - 1, d || 1));
  const day = utc.getUTCDay(); // 0 = Sun, 1 = Mon
  const offset = day === 0 ? -6 : 1 - day;
  utc.setUTCDate(utc.getUTCDate() + offset);
  return utc.toISOString().slice(0, 10);
}

export function shiftIsoDays(isoDate: string, deltaDays: number): string {
  const [y, m, d] = isoDate.slice(0, 10).split("-").map(Number);
  const utc = new Date(Date.UTC(y || 2026, (m || 1) - 1, d || 1));
  utc.setUTCDate(utc.getUTCDate() + deltaDays);
  return utc.toISOString().slice(0, 10);
}

function parseClockMinutes(hhmm: string): number | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (!match) return null;
  const h = Number(match[1]);
  const m = Number(match[2]);
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

export function pragueMinutesNow(now: Date = new Date()): number {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Prague",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(now);
  const h = Number(parts.find((p) => p.type === "hour")?.value ?? 0);
  const m = Number(parts.find((p) => p.type === "minute")?.value ?? 0);
  return h * 60 + m;
}

export interface TodayLessonState {
  todayDay: ScheduledDay | null;
  currentLesson: ScheduledLesson | null;
  nextLesson: ScheduledLesson | null;
  minutesRemainingInCurrent: number | null;
  minutesUntilNext: number | null;
  changedLessons: ScheduledLesson[];
}

export function resolveTodayLessonState(
  week: TimetableWeek | null,
  now: Date = new Date(),
): TodayLessonState {
  if (!week) {
    return {
      todayDay: null,
      currentLesson: null,
      nextLesson: null,
      minutesRemainingInCurrent: null,
      minutesUntilNext: null,
      changedLessons: [],
    };
  }
  const todayIso = pragueDateString(now);
  const todayDay = week.days.find((d) => d.date === todayIso || d.isToday) ?? null;
  if (!todayDay) {
    return {
      todayDay: null,
      currentLesson: null,
      nextLesson: null,
      minutesRemainingInCurrent: null,
      minutesUntilNext: null,
      changedLessons: [],
    };
  }

  const nowMinutes = pragueMinutesNow(now);
  const activeLessons = todayDay.lessons.filter((l) => l.changeKind !== "canceled");
  let currentLesson: ScheduledLesson | null = null;
  let nextLesson: ScheduledLesson | null = null;
  let minutesRemainingInCurrent: number | null = null;
  let minutesUntilNext: number | null = null;

  for (const lesson of activeLessons) {
    const start = parseClockMinutes(lesson.hour.beginTime);
    const end = parseClockMinutes(lesson.hour.endTime);
    if (start == null || end == null) continue;
    if (nowMinutes >= start && nowMinutes < end && !currentLesson) {
      currentLesson = lesson;
      minutesRemainingInCurrent = end - nowMinutes;
    } else if (start > nowMinutes && !nextLesson) {
      nextLesson = lesson;
      minutesUntilNext = start - nowMinutes;
    }
  }

  return {
    todayDay,
    currentLesson,
    nextLesson,
    minutesRemainingInCurrent,
    minutesUntilNext,
    changedLessons: todayDay.lessons.filter((l) => l.changeKind !== "none"),
  };
}

/** Matches Gradely/Support/ChristmasSeason.swift: 29 Nov through 24 Dec inclusive. */
export function isChristmasSeason(now: Date = new Date()): boolean {
  const m = now.getMonth() + 1;
  const d = now.getDate();
  return (m === 11 && d >= 29) || (m === 12 && d <= 24);
}
