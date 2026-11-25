import type {
  AbsenceSnapshot,
  HomeworkItem,
  HomeworkSnapshot,
  MarkItem,
  MarksSnapshot,
  SchoolOverviewResponse,
  SubjectMarks,
  TimetableKind,
  TimetableWeek,
  UserProfile,
} from "../shared/types.ts";
import {
  mapRawTimetableToWeek,
  mondayOfWeek,
  pragueDateString,
  shiftIsoDays,
} from "../shared/schoolMath.ts";
import { requireSafeProviderURL, sha256Hex } from "./security.ts";
import type { StoredWebSession, WebDeviceStore } from "./store.ts";

// Bakaláři's IIS servers answer HTTP 500 to Accept-Language: * (see poll-new-marks/index.ts).
const BAKALARI_ACCEPT_LANGUAGE = "cs-CZ";
const ACCESS_TOKEN_REFRESH_SKEW_MS = 5 * 60 * 1000;
const SCHOOL_REQUEST_TIMEOUT_MS = 18_000;

export class ProviderReauthRequiredError extends Error {
  constructor(message = "School session expired. Re-link this browser from Gradey.") {
    super(message);
  }
}

export type FetchLike = typeof fetch;

interface BakalariTokens {
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  expiresIn: number;
}

export class SchoolProviderProxy {
  // Per-session single-flight lock so concurrent requests never redeem the same
  // single-use Bakaláři refresh token in parallel.
  private readonly refreshLocks = new Map<string, Promise<Record<string, unknown>>>();

  constructor(
    private readonly store: WebDeviceStore,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async fetchOverview(
    session: StoredWebSession,
    now: Date = new Date(),
  ): Promise<SchoolOverviewResponse> {
    const weekStart = mondayOfWeek(now);
    const hwFrom = shiftIsoDays(pragueDateString(now), -14);
    const hwTo = shiftIsoDays(pragueDateString(now), 45);

    // Pre-warm/refresh the session secret once BEFORE firing parallel school API calls!
    await this.ensureValidSecret(session, false, now);

    const partialErrors: SchoolOverviewResponse["partialErrors"] = {};

    const [userRes, marksRes, absenceRes, timetableRes, hwRes] = await Promise.allSettled([
      this.fetchUser(session, now),
      this.fetchMarks(session, now),
      this.fetchAbsences(session, now),
      this.fetchTimetable(session, weekStart, "weekly", now),
      this.fetchHomeworks(session, hwFrom, hwTo, now),
    ]);

    const unwrap = <T>(
      res: PromiseSettledResult<T>,
      key: keyof SchoolOverviewResponse["partialErrors"],
      fallback: T,
    ): T => {
      if (res.status === "fulfilled") return res.value;
      if (res.reason instanceof ProviderReauthRequiredError) {
        throw res.reason;
      }
      partialErrors[key] =
        res.reason instanceof Error ? res.reason.message : "Failed to load section";
      return fallback;
    };

    // If every single core section failed with auth error, propagate reauth.
    if (
      marksRes.status === "rejected" &&
      marksRes.reason instanceof ProviderReauthRequiredError
    ) {
      throw marksRes.reason;
    }

    return {
      fetchedAt: now.toISOString(),
      user: unwrap(userRes, "user", null),
      marks: unwrap(marksRes, "marks", { subjects: [] }),
      absences: unwrap(absenceRes, "absences", {
        percentageThreshold: null,
        absences: [],
        absencesPerSubject: [],
      }),
      timetable: unwrap(timetableRes, "timetable", null),
      homeworks: unwrap(hwRes, "homeworks", { homeworks: [] }),
      partialErrors,
    };
  }

  async fetchUser(session: StoredWebSession, now: Date = new Date()): Promise<UserProfile> {
    if (session.provider === "eduPage") {
      const secret = await this.ensureValidSecret(session, false, now);
      const edu = (secret.eduPage ?? {}) as Record<string, any>;
      const student = edu.activeStudent as Record<string, any> | undefined;
      return {
        userUID: String(student?.id ?? edu.userID ?? session.providerUserId ?? "student"),
        fullName: String(student?.fullName ?? session.studentName),
        userClass: student?.className
          ? {
              id: String(student.classID ?? student.className),
              abbrev: String(student.className),
              name: String(student.className),
            }
          : null,
        schoolName: session.schoolName,
        userType: "student",
        userTypeText: "Student",
        studyYear: null,
      };
    }

    const raw = await this.bakalariGet(session, "api/3/user", {}, now);
    const cls = raw.Class;
    const rawSchool =
      displayableSchoolName(raw.SchoolOrganizationName) ??
      displayableSchoolName(raw.SchoolName) ??
      session.schoolName;
    return {
      userUID: String(raw.UserUID ?? session.providerUserId ?? ""),
      fullName: String(raw.FullName ?? session.studentName),
      userClass: cls
        ? {
            id: String(cls.Id ?? ""),
            abbrev: String(cls.Abbrev ?? ""),
            name: cls.Name ? String(cls.Name) : null,
          }
        : null,
      schoolName: rawSchool,
      userType: String(raw.UserType ?? "student"),
      userTypeText: String(raw.UserTypeText ?? "Student"),
      studyYear: typeof raw.StudyYear === "number" ? raw.StudyYear : null,
    };
  }

  async fetchMarks(session: StoredWebSession, now: Date = new Date()): Promise<MarksSnapshot> {
    if (session.provider === "eduPage") {
      const secret = await this.ensureValidSecret(session, false, now);
      const baseURL = requireSafeProviderURL(secret.baseURL ?? session.baseURL, "School URL");
      const raw = await this.fetchEduPageMarksRaw(secret, baseURL);
      return normalizeMarksResponse(raw);
    }
    const raw = await this.bakalariGet(session, "api/3/marks", {}, now);
    return normalizeMarksResponse(raw);
  }

  async fetchAbsences(session: StoredWebSession, now: Date = new Date()): Promise<AbsenceSnapshot> {
    if (session.provider === "eduPage") {
      return {
        percentageThreshold: null,
        absences: [],
        absencesPerSubject: [],
      };
    }
    const raw = await this.bakalariGet(session, "api/3/absence/student", {}, now);
    return normalizeAbsenceResponse(raw);
  }

  async fetchTimetable(
    session: StoredWebSession,
    dateOrMonday: string,
    kind: TimetableKind = "weekly",
    now: Date = new Date(),
  ): Promise<TimetableWeek> {
    const monday = mondayOfWeek(dateOrMonday);
    if (session.provider === "eduPage") {
      return { weekStart: monday, kind, hours: [], days: [] };
    }
    const raw =
      kind === "permanent"
        ? await this.bakalariGet(session, "api/3/timetable/permanent", {}, now)
        : await this.bakalariGet(session, "api/3/timetable/actual", { date: monday }, now);
    return mapRawTimetableToWeek(raw, monday, kind, now);
  }

  async fetchHomeworks(
    session: StoredWebSession,
    from: string,
    to: string,
    now: Date = new Date(),
  ): Promise<HomeworkSnapshot> {
    if (session.provider === "eduPage") {
      return { homeworks: [] };
    }
    const raw = await this.bakalariGet(
      session,
      "api/3/homeworks",
      { from: from.slice(0, 10), to: to.slice(0, 10) },
      now,
    );
    return normalizeHomeworkResponse(raw);
  }

  // MARK: - Bakaláři Authenticated Request + Atomic Single-Flight Refresh

  private async bakalariGet(
    session: StoredWebSession,
    path: string,
    query: Record<string, string>,
    now: Date,
  ): Promise<Record<string, any>> {
    let secret = await this.ensureValidSecret(session, false, now);
    const baseURL = requireSafeProviderURL(secret.baseURL ?? session.baseURL, "School URL");

    let response = await this.sendBakalariGet(baseURL, path, query, secret);
    if (response.status === 401) {
      secret = await this.ensureValidSecret(session, true, now);
      response = await this.sendBakalariGet(baseURL, path, query, secret);
    }

    if (response.status === 401) {
      await this.store.revokeSessionByBrowser(session.id, "provider_token_rejected", now);
      throw new ProviderReauthRequiredError();
    }
    if (!response.ok) {
      throw new Error(`School server responded with HTTP ${response.status}`);
    }
    return (await response.json()) as Record<string, any>;
  }

  private async sendBakalariGet(
    baseURL: string,
    path: string,
    query: Record<string, string>,
    secret: Record<string, unknown>,
  ): Promise<Response> {
    const url = new URL(path, baseURL);
    for (const [k, v] of Object.entries(query)) {
      url.searchParams.set(k, v);
    }
    return await this.fetchImpl(url.toString(), {
      method: "GET",
      headers: {
        Authorization: `${String(secret.tokenType || "Bearer")} ${String(secret.accessToken ?? "")}`,
        Accept: "application/json",
        "Accept-Language": BAKALARI_ACCEPT_LANGUAGE,
      },
      redirect: "error",
      signal: AbortSignal.timeout(SCHOOL_REQUEST_TIMEOUT_MS),
    });
  }

  private async ensureValidSecret(
    session: StoredWebSession,
    forceRefresh: boolean,
    now: Date,
  ): Promise<Record<string, unknown>> {
    const secret = await this.store.readSessionProviderSecret(session.id);
    if (!secret) {
      throw new ProviderReauthRequiredError();
    }
    if (session.provider !== "bakalari") {
      return secret;
    }

    const expiresAtMs = Date.parse(String(secret.expiresAt ?? ""));
    const needsRefresh =
      forceRefresh ||
      !Number.isFinite(expiresAtMs) ||
      expiresAtMs <= now.getTime() + ACCESS_TOKEN_REFRESH_SKEW_MS;

    if (!needsRefresh) {
      return secret;
    }

    const existingTask = this.refreshLocks.get(session.id);
    if (existingTask) {
      return await existingTask;
    }

    const refreshPromise = this.performBakalariRefresh(session, now).finally(() => {
      this.refreshLocks.delete(session.id);
    });
    this.refreshLocks.set(session.id, refreshPromise);
    return await refreshPromise;
  }

  private async performBakalariRefresh(
    session: StoredWebSession,
    now: Date,
  ): Promise<Record<string, unknown>> {
    const current = await this.store.readSessionProviderSecret(session.id);
    if (!current) {
      throw new ProviderReauthRequiredError();
    }
    const baseURL = requireSafeProviderURL(current.baseURL ?? session.baseURL, "School URL");
    const refreshToken = String(current.refreshToken ?? "").trim();
    if (!refreshToken) {
      await this.store.revokeSessionByBrowser(session.id, "missing_refresh_token", now);
      throw new ProviderReauthRequiredError();
    }

    const body = new URLSearchParams({
      client_id: "ANDR",
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });

    const response = await this.fetchImpl(new URL("api/login", baseURL).toString(), {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Accept-Language": BAKALARI_ACCEPT_LANGUAGE,
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
      },
      body,
      redirect: "error",
      signal: AbortSignal.timeout(SCHOOL_REQUEST_TIMEOUT_MS),
    });

    if (response.status === 400 || response.status === 401) {
      await this.store.revokeSessionByBrowser(session.id, "bakalari_refresh_rejected", now);
      throw new ProviderReauthRequiredError();
    }
    if (!response.ok) {
      throw new Error(`School token refresh failed with HTTP ${response.status}`);
    }

    const tokens = parseBakalariTokens(await response.json());
    const nextSecret: Record<string, unknown> = {
      provider: "bakalari",
      baseURL,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      tokenType: tokens.tokenType,
      expiresAt: new Date(now.getTime() + tokens.expiresIn * 1000).toISOString(),
      webSessionEstablishedAt:
        typeof current.webSessionEstablishedAt === "string"
          ? current.webSessionEstablishedAt
          : now.toISOString(),
    };

    await this.store.updateSessionProviderSecret(session.id, session.userId, nextSecret);
    return nextSecret;
  }

  private async fetchEduPageMarksRaw(
    secret: Record<string, unknown>,
    baseURL: string,
  ): Promise<Record<string, any>> {
    const eduPage = (secret.eduPage ?? {}) as Record<string, any>;
    const sessionID = String(eduPage.sessionID ?? "").trim();
    if (!sessionID) throw new ProviderReauthRequiredError();

    const url = new URL("znamky/", baseURL);
    url.searchParams.set("barNoSkin", "1");
    const response = await this.fetchImpl(url.toString(), {
      headers: {
        Accept: "text/html,application/xhtml+xml",
        Cookie: `PHPSESSID=${sessionID}`,
      },
      redirect: "error",
      signal: AbortSignal.timeout(SCHOOL_REQUEST_TIMEOUT_MS),
    });
    if (response.status === 401 || response.status === 403) {
      throw new ProviderReauthRequiredError();
    }
    if (!response.ok) throw new Error(`EduPage responded with HTTP ${response.status}`);
    const text = await response.text();
    if (
      text.includes("cmd=MainLogin") ||
      (text.includes('name="username"') && text.includes('name="password"'))
    ) {
      throw new ProviderReauthRequiredError();
    }
    return { Subjects: [] };
  }
}

function parseBakalariTokens(raw: unknown): BakalariTokens {
  const rec = raw && typeof raw === "object" ? (raw as Record<string, any>) : {};
  const accessToken = String(rec.access_token ?? rec.accessToken ?? "").trim();
  const refreshToken = String(rec.refresh_token ?? rec.refreshToken ?? "").trim();
  const tokenType = String(rec.token_type ?? rec.tokenType ?? "Bearer").trim() || "Bearer";
  const expiresIn = Number(rec.expires_in ?? rec.expiresIn ?? 0);
  if (!accessToken || !refreshToken || !Number.isFinite(expiresIn) || expiresIn <= 0) {
    throw new Error("Invalid Bakaláři token response");
  }
  return { accessToken, refreshToken, tokenType, expiresIn };
}

function displayableSchoolName(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const normalized = trimmed
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
  if (normalized === "nazev skoly") return null;
  return trimmed;
}

function normalizeMarksResponse(raw: Record<string, any>): MarksSnapshot {
  const rawSubjects = Array.isArray(raw.Subjects ?? raw.subjects)
    ? (raw.Subjects ?? raw.subjects)
    : [];

  const subjects: SubjectMarks[] = rawSubjects.map((s: any) => {
    const info = s.Subject ?? s.subjectInfo ?? {};
    const subjectID = String(info.Id ?? info.id ?? "");
    const rawMarks = Array.isArray(s.Marks ?? s.marks) ? (s.Marks ?? s.marks) : [];
    const marks: MarkItem[] = rawMarks.map((m: any) => {
      const markDate = String(m.MarkDate ?? m.markDate ?? "");
      const markText = String(m.MarkText ?? m.markText ?? "");
      const type = String(m.Type ?? m.type ?? "");
      const typeNote = m.TypeNote ?? m.typeNote ?? null;
      const caption = m.Caption ?? m.caption ?? null;
      const theme = m.Theme ?? m.theme ?? null;
      const rawWeight = m.Weight ?? m.weight;
      const weight =
        typeof rawWeight === "number"
          ? rawWeight
          : typeof rawWeight === "string" && rawWeight.trim()
            ? Number(rawWeight.replace(",", "."))
            : null;
      const isPoints = Boolean(m.IsPoints ?? m.isPoints ?? false);
      const pointsText = m.PointsText ?? m.pointsText ?? null;
      const maxPoints =
        typeof (m.MaxPoints ?? m.maxPoints) === "number"
          ? Number(m.MaxPoints ?? m.maxPoints)
          : null;
      const providerId = String(m.Id ?? m.id ?? "").trim();
      const id =
        providerId ||
        `local-mark-${sha256Hex(
          [subjectID, markDate, markText, type, caption ?? "", theme ?? "", String(weight)].join("|"),
        ).slice(0, 24)}`;

      return {
        id,
        markDate,
        editDate: m.EditDate ?? m.editDate ?? null,
        caption: caption ? String(caption) : null,
        theme: theme ? String(theme) : null,
        markText,
        teacherID: m.TeacherId ?? m.teacherID ?? null,
        type,
        typeNote: typeNote ? String(typeNote) : null,
        weight: weight != null && Number.isFinite(weight) ? weight : null,
        subjectID: String(m.SubjectId ?? m.subjectID ?? subjectID),
        isNew: Boolean(m.IsNew ?? m.isNew ?? false),
        isPoints,
        calculatedMarkText: m.CalculatedMarkText ?? m.calculatedMarkText ?? null,
        classRankText: m.ClassRankText ?? m.classRankText ?? null,
        pointsText: pointsText ? String(pointsText) : null,
        maxPoints,
      };
    });

    return {
      id: subjectID,
      subjectInfo: {
        id: subjectID,
        abbrev: String(info.Abbrev ?? info.abbrev ?? "").trim(),
        name: String(info.Name ?? info.name ?? "").trim(),
      },
      marks,
      averageText: s.AverageText != null ? String(s.AverageText).trim() || null : null,
      temporaryMark: s.TemporaryMark != null ? String(s.TemporaryMark).trim() || null : null,
      subjectNote: s.SubjectNote != null ? String(s.SubjectNote).trim() || null : null,
      temporaryMarkNote:
        s.TemporaryMarkNote != null ? String(s.TemporaryMarkNote).trim() || null : null,
      pointsOnly: Boolean(s.PointsOnly ?? s.pointsOnly ?? false),
      markPredictionEnabled: Boolean(s.MarkPredictionEnabled ?? s.markPredictionEnabled ?? false),
    };
  });

  return { subjects };
}

function normalizeAbsenceResponse(raw: Record<string, any>): AbsenceSnapshot {
  const threshold =
    typeof raw.PercentageThreshold === "number" ? raw.PercentageThreshold : null;
  const absences = Array.isArray(raw.Absences)
    ? raw.Absences.map((d: any) => ({
        date: String(d.Date ?? ""),
        unsolved: Number(d.Unsolved ?? 0),
        ok: Number(d.Ok ?? 0),
        missed: Number(d.Missed ?? 0),
        late: Number(d.Late ?? 0),
        soon: Number(d.Soon ?? 0),
        school: Number(d.School ?? 0),
        distanceTeaching: Number(d.DistanceTeaching ?? 0),
      }))
    : [];
  const absencesPerSubject = Array.isArray(raw.AbsencesPerSubject)
    ? raw.AbsencesPerSubject.map((s: any) => ({
        subjectName: String(s.SubjectName ?? "").trim(),
        lessonsCount: Number(s.LessonsCount ?? 0),
        base: Number(s.Base ?? 0),
        late: Number(s.Late ?? 0),
        soon: Number(s.Soon ?? 0),
        school: Number(s.School ?? 0),
        distanceTeaching: Number(s.DistanceTeaching ?? 0),
      }))
    : [];
  return { percentageThreshold: threshold, absences, absencesPerSubject };
}

function normalizeHomeworkResponse(raw: Record<string, any>): HomeworkSnapshot {
  const list = Array.isArray(raw.Homeworks) ? raw.Homeworks : [];
  const homeworks: HomeworkItem[] = list.map((hw: any) => {
    const content = String(hw.Content ?? "").trim();
    const firstLine = content.split(/\r?\n/).find((l: string) => l.trim().length > 0)?.trim() ?? "";
    const subjectName = hw.Subject?.Name ? String(hw.Subject.Name).trim() : null;
    const subjectAbbrev = hw.Subject?.Abbrev ? String(hw.Subject.Abbrev).trim() : null;
    return {
      id: String(hw.ID ?? hw.Id ?? ""),
      subjectID: hw.Subject?.Id ? String(hw.Subject.Id).trim() : null,
      subjectName,
      subjectAbbrev,
      teacherName: hw.Teacher?.Name ? String(hw.Teacher.Name).trim() : null,
      title: firstLine || subjectName || subjectAbbrev || "Homework",
      content,
      notice: hw.Notice ? String(hw.Notice).trim() || null : null,
      assignedOn: hw.DateStart ? String(hw.DateStart) : null,
      dueOn: hw.DateEnd ? String(hw.DateEnd) : null,
      isDone: Boolean(hw.Done ?? false),
      isClosed: Boolean(hw.Closed ?? false),
      isElectronic: Boolean(hw.Electronic ?? false),
      attachments: Array.isArray(hw.Attachments)
        ? hw.Attachments.map((a: any) => ({
            id: String(a.Id ?? ""),
            name: String(a.Name ?? a.Id ?? "Attachment").trim(),
            size: typeof a.Size === "number" && a.Size > 0 ? a.Size : null,
          }))
        : [],
    };
  });
  return { homeworks };
}
