import type {
  AbsenceSnapshot,
  HomeworkSnapshot,
  MarksSnapshot,
  PairingChallengeStatus,
  QRChallengeCreateResponse,
  QRChallengeStatusResponse,
  SchoolOverviewResponse,
  TimetableKind,
  TimetableWeek,
  UserProfile,
  WebAuthStateResponse,
  WebSessionSummary,
} from "../shared/types.ts";

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code?: string,
  ) {
    super(message);
  }
}

let currentCsrfToken: string | null = null;

export function setCsrfToken(token: string | null | undefined): void {
  if (token) currentCsrfToken = token;
}

async function requestJson<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  headers.set("X-Gradey-Client", "web-v1");
  if (init.method && init.method !== "GET" && init.method !== "HEAD") {
    if (currentCsrfToken) {
      headers.set("X-CSRF-Token", currentCsrfToken);
    }
    if (init.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json; charset=utf-8");
    }
  }

  const response = await fetch(path, {
    ...init,
    headers,
    credentials: "same-origin",
  });

  const rotatedCsrf = response.headers.get("X-Gradey-CSRF-Token");
  if (rotatedCsrf) {
    currentCsrfToken = rotatedCsrf;
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new ApiError(
      typeof data?.error === "string" ? data.error : `HTTP ${response.status}`,
      response.status,
      typeof data?.code === "string" ? data.code : undefined,
    );
  }
  return data as T;
}

export const webApi = {
  async checkSession(): Promise<WebAuthStateResponse> {
    const res = await requestJson<WebAuthStateResponse>("/api/auth/session");
    if (res.csrfToken) currentCsrfToken = res.csrfToken;
    return res;
  },

  async createQRChallenge(): Promise<QRChallengeCreateResponse> {
    return await requestJson<QRChallengeCreateResponse>("/api/auth/qr/challenges", {
      method: "POST",
      body: "{}",
    });
  },

  async pollQRChallenge(challengeId: string): Promise<QRChallengeStatusResponse> {
    return await requestJson<QRChallengeStatusResponse>(
      `/api/auth/qr/challenges/${encodeURIComponent(challengeId)}/status`,
    );
  },

  subscribeQRChallenge(
    challengeId: string,
    onStatus: (status: PairingChallengeStatus) => void,
    onError: () => void,
  ): () => void {
    const source = new EventSource(
      `/api/auth/qr/challenges/${encodeURIComponent(challengeId)}/events`,
      { withCredentials: true },
    );
    const handler = (event: MessageEvent) => {
      try {
        const parsed = JSON.parse(event.data) as QRChallengeStatusResponse;
        if (parsed?.status) onStatus(parsed.status);
      } catch {
        // Ignore malformed frame
      }
    };
    source.addEventListener("status", handler);
    source.onerror = () => {
      source.close();
      onError();
    };
    return () => {
      source.removeEventListener("status", handler);
      source.close();
    };
  },

  async claimQRChallenge(challengeId: string): Promise<{
    authenticated: true;
    csrfToken: string;
    session: WebSessionSummary;
  }> {
    const res = await requestJson<{
      authenticated: true;
      csrfToken: string;
      session: WebSessionSummary;
    }>(`/api/auth/qr/challenges/${encodeURIComponent(challengeId)}/claim`, {
      method: "POST",
      body: "{}",
    });
    currentCsrfToken = res.csrfToken;
    return res;
  },

  subscribeSessionRevocation(onRevoked: () => void): () => void {
    const source = new EventSource("/api/auth/session/events", {
      withCredentials: true,
    });
    const handler = () => {
      source.close();
      onRevoked();
    };
    source.addEventListener("revoked", handler);
    return () => {
      source.removeEventListener("revoked", handler);
      source.close();
    };
  },

  async logout(): Promise<void> {
    try {
      await requestJson("/api/auth/logout", { method: "POST", body: "{}" });
    } finally {
      currentCsrfToken = null;
    }
  },

  async fetchOverview(): Promise<SchoolOverviewResponse> {
    return await requestJson<SchoolOverviewResponse>("/api/school/overview");
  },

  async fetchMarks(): Promise<MarksSnapshot> {
    return await requestJson<MarksSnapshot>("/api/school/marks");
  },

  async fetchTimetable(date: string, kind: TimetableKind): Promise<TimetableWeek> {
    const params = new URLSearchParams({ date, kind });
    return await requestJson<TimetableWeek>(`/api/school/timetable?${params.toString()}`);
  },

  async fetchAbsences(): Promise<AbsenceSnapshot> {
    return await requestJson<AbsenceSnapshot>("/api/school/absences");
  },

  async fetchHomeworks(from?: string, to?: string): Promise<HomeworkSnapshot> {
    const params = new URLSearchParams();
    if (from) params.set("from", from);
    if (to) params.set("to", to);
    const qs = params.toString();
    return await requestJson<HomeworkSnapshot>(`/api/school/homeworks${qs ? `?${qs}` : ""}`);
  },

  async fetchProfile(): Promise<{ user: UserProfile; session: WebSessionSummary }> {
    return await requestJson<{ user: UserProfile; session: WebSessionSummary }>(
      "/api/school/profile",
    );
  },
};
