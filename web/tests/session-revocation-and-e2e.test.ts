import { describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createGradeyWebApp } from "../src/server/app.ts";
import { SqliteWebDeviceStore } from "../src/server/store.ts";
import { SchoolProviderProxy } from "../src/server/schoolClient.ts";
import {
  buildSubjectAbsenceRisks,
  overallStudyAverage,
  prepareSubjectCalculation,
  simulateSubjectGrade,
} from "../src/shared/schoolMath.ts";

const SECRET_KEY = "e2e-test-encryption-key-with-at-least-32-characters!!";

function extractCookieValue(setCookieHeader: string | null, name: string): string | null {
  if (!setCookieHeader) return null;
  const regex = new RegExp(`(?:^|,\\s*)${name}=([^;]+)`, "i");
  const match = regex.exec(setCookieHeader);
  return match?.[1] ? decodeURIComponent(match[1]) : null;
}

describe("Gradey for Web — End-to-End QR Pairing, Independent School Proxy & Session Revocation", () => {
  it("completes real-time SSE QR pairing, serves Bakaláři data while phone is offline, single-flights token refresh, and revokes immediately", async () => {
    let now = new Date("2026-11-25T09:00:00.000Z");
    const dir = mkdtempSync(join(tmpdir(), "gradey-web-e2e-"));
    const store = new SqliteWebDeviceStore(join(dir, "e2e.sqlite"), SECRET_KEY);

    // Simulated upstream school Bakaláři HTTPS server with single-use rotating refresh tokens
    let activeAccessToken = "bak-web-access-v1";
    let activeRefreshToken = "bak-web-refresh-v1";
    let refreshCallCount = 0;

    const fakeSchoolFetch: typeof fetch = async (input, init) => {
      const url = new URL(typeof input === "string" ? input : input.toString());
      expect(url.origin).toBe("https://bakalari.gymnazium.cz");
      const headers = new Headers(init?.headers);
      expect(headers.get("Accept-Language")).toBe("cs-CZ");

      if (url.pathname === "/api/login") {
        refreshCallCount += 1;
        const params = new URLSearchParams(init?.body?.toString() ?? "");
        if (
          params.get("grant_type") !== "refresh_token" ||
          params.get("refresh_token") !== activeRefreshToken
        ) {
          return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
        }
        // Single-use rotation: old refresh token is invalidated immediately
        activeAccessToken = `bak-web-access-v${refreshCallCount + 1}`;
        activeRefreshToken = `bak-web-refresh-v${refreshCallCount + 1}`;
        return new Response(
          JSON.stringify({
            access_token: activeAccessToken,
            refresh_token: activeRefreshToken,
            token_type: "Bearer",
            expires_in: 3600,
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }

      if (headers.get("Authorization") !== `Bearer ${activeAccessToken}`) {
        return new Response("Unauthorized", { status: 401 });
      }

      if (url.pathname === "/api/3/user") {
        return Response.json({
          UserUID: "S-42",
          FullName: "Filip Bukovina",
          Class: { Id: "4A", Abbrev: "4.A", Name: "Čtvrtá A" },
          SchoolOrganizationName: "Gymnázium Praha",
          UserType: "student",
          UserTypeText: "Žák",
          StudyYear: 4,
        });
      }

      if (url.pathname === "/api/3/marks") {
        return Response.json({
          Subjects: [
            {
              Subject: { Id: "MAT", Abbrev: "M", Name: "Matematika" },
              AverageText: "1,50",
              TemporaryMark: null,
              PointsOnly: false,
              MarkPredictionEnabled: true,
              Marks: [
                {
                  Id: "m1",
                  MarkDate: "2026-11-20T00:00:00+01:00",
                  Caption: "Čtvrtletní práce",
                  MarkText: "1",
                  Type: "X",
                  TypeNote: "Písemka",
                  Weight: 3,
                  SubjectId: "MAT",
                  IsNew: true,
                  IsPoints: false,
                },
                {
                  Id: "m2",
                  MarkDate: "2026-11-10T00:00:00+01:00",
                  Caption: "Malý test",
                  MarkText: "3",
                  Type: "X",
                  Weight: 1,
                  SubjectId: "MAT",
                  IsNew: false,
                  IsPoints: false,
                },
              ],
            },
          ],
        });
      }

      if (url.pathname === "/api/3/absence/student") {
        return Response.json({
          PercentageThreshold: 0.25,
          Absences: [
            {
              Date: "2026-11-18T00:00:00+01:00",
              Unsolved: 0,
              Ok: 4,
              Missed: 0,
              Late: 1,
              Soon: 0,
              School: 0,
              DistanceTeaching: 0,
            },
          ],
          AbsencesPerSubject: [
            {
              SubjectName: "Matematika",
              LessonsCount: 40,
              Base: 8,
              Late: 1,
              Soon: 0,
              School: 0,
              DistanceTeaching: 0,
            },
          ],
        });
      }

      if (url.pathname === "/api/3/timetable/actual") {
        // Includes Bakaláři's padded entity IDs (" 6", "U  12") to verify TimetableMapper fidelity
        return Response.json({
          Hours: [{ Id: 1, Caption: "1", BeginTime: "08:00", EndTime: "08:45" }],
          Subjects: [{ Id: " 6", Abbrev: "M", Name: "Matematika" }],
          Teachers: [{ Id: "U  12", Abbrev: "Nov", Name: "Mgr. Novák" }],
          Rooms: [{ Id: "R1", Abbrev: "204", Name: "Učebna 204" }],
          Groups: [],
          Cycles: [],
          Days: [
            {
              DayOfWeek: 3,
              Date: "2026-11-25T00:00:00+01:00",
              DayType: "WorkDay",
              DayDescription: "",
              Atoms: [
                {
                  HourId: 1,
                  SubjectId: " 6",
                  TeacherId: "U  12",
                  RoomId: "R1",
                  GroupIds: [],
                  CycleIds: [],
                  HomeworkIds: ["hw-1"],
                  Theme: "Derivace složené funkce",
                },
              ],
            },
          ],
        });
      }

      if (url.pathname === "/api/3/homeworks") {
        return Response.json({
          Homeworks: [
            {
              ID: "hw-1",
              DateStart: "2026-11-24T00:00:00+01:00",
              DateEnd: "2026-11-26T00:00:00+01:00",
              Content: "Spočítat příklady 4–9 ze sbírky https://matematika.cz/derivace",
              Done: false,
              Closed: false,
              Electronic: true,
              Subject: { Id: "MAT", Abbrev: "M", Name: "Matematika" },
              Teacher: { Id: "U12", Abbrev: "Nov", Name: "Mgr. Novák" },
              Attachments: [],
            },
          ],
        });
      }

      return new Response("Not Found", { status: 404 });
    };

    const schoolProxy = new SchoolProviderProxy(store, fakeSchoolFetch);
    const app = createGradeyWebApp({
      store,
      csrfSecret: SECRET_KEY,
      schoolProxy,
      forceSecureCookies: true,
      allowedOrigins: ["https://web.gradey.app"],
      now: () => now,
      verifyMobileToken: async (jwt) => {
        if (jwt === "user-a-jwt") return { userId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" };
        if (jwt === "user-b-jwt") return { userId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" };
        return null;
      },
    });

    try {
      const safariMacUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15";
      const firefoxWinUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0";

      // 1. Browser 1 (Safari on macOS) opens Gradey for Web and creates QR challenge
      const ch1Res = await app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app", "User-Agent": safariMacUA },
      });
      expect(ch1Res.status).toBe(200);
      const qrCookie1 = extractCookieValue(ch1Res.headers.get("Set-Cookie"), "__Host-gradey_qr")!;
      const ch1 = await ch1Res.json();
      const ch1Url = new URL(ch1.qrPayload);
      const qrSecret1 = ch1Url.searchParams.get("t")!;

      // Open SSE stream for Browser 1 to observe real-time transitions
      const sseRes = await app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${ch1.challengeId}/events`,
        {
          headers: {
            "User-Agent": safariMacUA,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(qrCookie1)}`,
          },
        },
      );
      expect(sseRes.status).toBe(200);

      // 2. iPhone scans QR code -> inspects browser & OS metadata
      const inspectRes = await app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer user-a-jwt",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId: ch1.challengeId, qrSecret: qrSecret1 }),
      });
      expect(inspectRes.status).toBe(200);
      const preview = await inspectRes.json();
      expect(preview.browserName).toBe("Safari");
      expect(preview.osName).toBe("macOS");
      expect(preview.deviceLabel).toBe("Safari · macOS");

      // 3. iPhone approves -> uploads dedicated web token family
      const approveRes = await app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer user-a-jwt",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId: ch1.challengeId,
          qrSecret: qrSecret1,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          student_name: "Filip Bukovina",
          class_name: "4.A",
          school_name: "Gymnázium Praha",
          token_payload: {
            provider: "bakalari",
            baseURL: "https://bakalari.gymnazium.cz/",
            accessToken: activeAccessToken,
            refreshToken: activeRefreshToken,
            tokenType: "Bearer",
            expiresAt: "2026-11-25T10:00:00.000Z",
            webSessionEstablishedAt: "2026-11-25T09:00:05.000Z",
          },
        }),
      });
      expect(approveRes.status).toBe(200);

      // Verify SSE stream received pending -> scanned -> approved and closed cleanly
      const sseText = await sseRes.text();
      expect(sseText).toContain('"status":"pending"');
      expect(sseText).toContain('"status":"scanned"');
      expect(sseText).toContain('"status":"approved"');

      // 4. Browser 1 claims approved challenge -> receives persistent HttpOnly session cookie
      const claim1 = await app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${ch1.challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": safariMacUA,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(qrCookie1)}`,
          },
        },
      );
      expect(claim1.status).toBe(200);
      const safariCookie = extractCookieValue(
        claim1.headers.get("Set-Cookie"),
        "__Host-gradey_session",
      )!;
      const claimBody1 = await claim1.json();
      const safariSessionId = claimBody1.session.id as string;

      // 5. Pair a second browser (Firefox on Windows) for User A
      const ch2Res = await app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app", "User-Agent": firefoxWinUA },
      });
      const qrCookie2 = extractCookieValue(ch2Res.headers.get("Set-Cookie"), "__Host-gradey_qr")!;
      const ch2 = await ch2Res.json();
      const qrSecret2 = new URL(ch2.qrPayload).searchParams.get("t")!;
      await app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: { Authorization: "Bearer user-a-jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ challengeId: ch2.challengeId, qrSecret: qrSecret2 }),
      });
      await app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer user-a-jwt",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId: ch2.challengeId,
          qrSecret: qrSecret2,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          student_name: "Filip Bukovina",
          token_payload: {
            provider: "bakalari",
            baseURL: "https://bakalari.gymnazium.cz/",
            accessToken: activeAccessToken,
            refreshToken: "separate-firefox-refresh-token",
            tokenType: "Bearer",
            expiresAt: "2026-11-25T10:00:00.000Z",
            webSessionEstablishedAt: "2026-11-25T09:01:00.000Z",
          },
        }),
      });
      const claim2 = await app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${ch2.challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": firefoxWinUA,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(qrCookie2)}`,
          },
        },
      );
      const firefoxCookie = extractCookieValue(
        claim2.headers.get("Set-Cookie"),
        "__Host-gradey_session",
      )!;

      // 6. Phone is now completely offline! Browser 1 fetches full school overview
      const overviewRes = await app.request("https://web.gradey.app/api/school/overview", {
        headers: {
          "User-Agent": safariMacUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(safariCookie)}`,
        },
      });
      expect(overviewRes.status).toBe(200);
      const overview = await overviewRes.json();
      expect(overview.user.fullName).toBe("Filip Bukovina");
      expect(overview.user.userClass.abbrev).toBe("4.A");
      expect(overview.marks.subjects).toHaveLength(1);
      expect(overview.timetable.days[0].lessons[0].subjectName).toBe("Matematika");
      expect(overview.timetable.days[0].lessons[0].teacherName).toBe("Mgr. Novák");
      expect(overview.homeworks.homeworks[0].isElectronic).toBe(true);

      // Verify GradeMath & AbsenceRisk calculations match Swift implementation
      const mathSubject = overview.marks.subjects[0];
      const prepared = prepareSubjectCalculation(mathSubject);
      expect(prepared.calculatedAverage).toBeCloseTo(1.5, 5); // (1*3 + 3*1) / 4 = 1.50
      expect(overallStudyAverage(overview.marks.subjects)).toBeCloseTo(1.5, 5);
      const sim = simulateSubjectGrade(prepared, "1", 2)!;
      expect(sim.estimatedAverage).toBeCloseTo(8 / 6, 4);

      const risks = buildSubjectAbsenceRisks(overview.absences);
      expect(risks[0]?.percentage).toBeCloseTo(20, 4);
      expect(risks[0]?.threshold).toBe(25);
      expect(risks[0]?.level).toBe("watch"); // 20 / 25 = 0.8 >= 0.7

      // 7. Advance past Bakaláři accessToken expiry (58 minutes) & fire 4 concurrent requests
      // Single-flight mutex MUST refresh the single-use Bakaláři token exactly ONCE!
      now = new Date("2026-11-25T09:58:00.000Z");
      const parallelResponses = await Promise.all([
        app.request("https://web.gradey.app/api/school/marks", {
          headers: { "User-Agent": safariMacUA, Cookie: `__Host-gradey_session=${safariCookie}` },
        }),
        app.request("https://web.gradey.app/api/school/absences", {
          headers: { "User-Agent": safariMacUA, Cookie: `__Host-gradey_session=${safariCookie}` },
        }),
        app.request("https://web.gradey.app/api/school/timetable", {
          headers: { "User-Agent": safariMacUA, Cookie: `__Host-gradey_session=${safariCookie}` },
        }),
        app.request("https://web.gradey.app/api/school/homeworks", {
          headers: { "User-Agent": safariMacUA, Cookie: `__Host-gradey_session=${safariCookie}` },
        }),
      ]);
      for (const r of parallelResponses) {
        expect(r.status).toBe(200);
      }
      expect(refreshCallCount).toBe(1);

      // 8. Mobile Linked Devices list & cross-user isolation
      const userBList = await app.request("https://web.gradey.app/api/mobile/devices", {
        headers: { Authorization: "Bearer user-b-jwt" },
      });
      expect((await userBList.json()).devices).toHaveLength(0);

      // User B cannot revoke User A's Safari session
      const userBRevokeAttempt = await app.request(
        `https://web.gradey.app/api/mobile/devices/${safariSessionId}`,
        {
          method: "DELETE",
          headers: { Authorization: "Bearer user-b-jwt" },
        },
      );
      expect(userBRevokeAttempt.status).toBe(404);

      const userAList = await app.request("https://web.gradey.app/api/mobile/devices", {
        headers: { Authorization: "Bearer user-a-jwt" },
      });
      const devicesBefore = (await userAList.json()).devices;
      expect(devicesBefore).toHaveLength(2);
      expect(devicesBefore.map((d: any) => d.browserName).sort()).toEqual(["Firefox", "Safari"]);

      // 9. Subscribe Browser 1 to real-time session revocation SSE & revoke Safari from mobile!
      // Note: Safari cookie rotated during step 7; grab latest cookie from response
      const rotatedSafariCookie =
        extractCookieValue(parallelResponses[0]!.headers.get("Set-Cookie"), "__Host-gradey_session") ??
        safariCookie;

      const revokeSseRes = await app.request("https://web.gradey.app/api/auth/session/events", {
        headers: {
          "User-Agent": safariMacUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(rotatedSafariCookie)}`,
        },
      });
      expect(revokeSseRes.status).toBe(200);
      const revokeSsePromise = revokeSseRes.text();

      // Trigger individual session revocation from mobile
      const revokeSafari = await app.request(
        `https://web.gradey.app/api/mobile/devices/${safariSessionId}`,
        {
          method: "DELETE",
          headers: { Authorization: "Bearer user-a-jwt" },
        },
      );
      expect(revokeSafari.status).toBe(200);

      const revokeSseOutput = await revokeSsePromise;
      expect(revokeSseOutput).toContain("event: revoked");

      // Revoked Safari session immediately gets 401 on /api/school/marks
      const safariAfterRevoke = await app.request("https://web.gradey.app/api/school/marks", {
        headers: {
          "User-Agent": safariMacUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(rotatedSafariCookie)}`,
        },
      });
      expect(safariAfterRevoke.status).toBe(401);

      // Meanwhile Firefox session is still active!
      const firefoxCheck = await app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": firefoxWinUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(firefoxCookie)}`,
        },
      });
      expect((await firefoxCheck.json()).authenticated).toBe(true);

      // 10. "Log out of all web sessions" revokes remaining Firefox session immediately
      const revokeAllRes = await app.request(
        "https://web.gradey.app/api/mobile/devices/revoke-all",
        {
          method: "POST",
          headers: { Authorization: "Bearer user-a-jwt" },
        },
      );
      expect((await revokeAllRes.json()).revokedCount).toBe(1);

      const firefoxAfterRevokeAll = await app.request("https://web.gradey.app/api/school/marks", {
        headers: {
          "User-Agent": firefoxWinUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(firefoxCookie)}`,
        },
      });
      expect(firefoxAfterRevokeAll.status).toBe(401);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
