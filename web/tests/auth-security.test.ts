import { describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { createGradeyWebApp } from "../src/server/app.ts";
import { SqliteWebDeviceStore } from "../src/server/store.ts";
import { decryptProviderSecret, encryptProviderSecret } from "../src/server/security.ts";

const TEST_MASTER_KEY = "test-master-encryption-key-with-more-than-32-chars!!";
const TEST_CSRF_KEY = "test-csrf-hmac-secret-key-with-more-than-32-chars!!";

function extractCookieValue(setCookieHeader: string | null, name: string): string | null {
  if (!setCookieHeader) return null;
  const regex = new RegExp(`(?:^|,\\s*)${name}=([^;]+)`, "i");
  const match = regex.exec(setCookieHeader);
  return match?.[1] ? decodeURIComponent(match[1]) : null;
}

function parseQrUri(qrPayload: string): { challengeId: string; qrSecret: string } {
  const url = new URL(qrPayload);
  expect(url.protocol).toBe("gradey:");
  expect(url.host).toBe("pair");
  expect(url.searchParams.get("v")).toBe("1");
  // Must not embed any extra parameters, tokens, or student metadata
  expect([...url.searchParams.keys()].sort()).toEqual(["c", "t", "v"]);
  return {
    challengeId: url.searchParams.get("c")!,
    qrSecret: url.searchParams.get("t")!,
  };
}

function makeTestHarness(initialNow = new Date("2026-11-25T10:00:00.000Z")) {
  let currentNow = initialNow;
  const dir = mkdtempSync(join(tmpdir(), "gradey-web-sec-"));
  const dbPath = join(dir, "test.sqlite");
  const store = new SqliteWebDeviceStore(dbPath, TEST_MASTER_KEY);

  const app = createGradeyWebApp({
    store,
    csrfSecret: TEST_CSRF_KEY,
    forceSecureCookies: true,
    allowedOrigins: ["https://web.gradey.app"],
    now: () => currentNow,
    verifyMobileToken: async (token) => {
      if (token === "valid-mobile-jwt-user-1") {
        return { userId: "11111111-1111-4111-8111-111111111111", email: "jan@example.cz" };
      }
      if (token === "valid-mobile-jwt-user-2") {
        return { userId: "22222222-2222-4222-8222-222222222222", email: "petr@example.cz" };
      }
      return null;
    },
  });

  return {
    app,
    store,
    dbPath,
    advanceMs(ms: number) {
      currentNow = new Date(currentNow.getTime() + ms);
    },
    getNow: () => currentNow,
    cleanup() {
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

describe("Gradey for Web — Authentication Security Suite", () => {
  it("generates credential-free QR payloads and sets __Host- HttpOnly Secure SameSite=Lax cookies", async () => {
    const h = makeTestHarness();
    try {
      const res = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: {
          Origin: "https://web.gradey.app",
          "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        },
      });
      expect(res.status).toBe(200);
      expect(res.headers.get("Cache-Control")).toContain("no-store");
      expect(res.headers.get("X-Frame-Options")).toBe("DENY");
      expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");

      const setCookie = res.headers.get("Set-Cookie") ?? "";
      expect(setCookie).toContain("__Host-gradey_qr=");
      expect(setCookie).toContain("HttpOnly");
      expect(setCookie).toContain("Secure");
      expect(setCookie).toContain("SameSite=Lax");
      expect(setCookie).toContain("Path=/");
      expect(setCookie).not.toMatch(/Domain=/i);

      const body = await res.json();
      expect(body.ttlSeconds).toBe(60);
      const parsed = parseQrUri(body.qrPayload);
      expect(parsed.challengeId).toBe(body.challengeId);
      expect(parsed.qrSecret.length).toBeGreaterThanOrEqual(40);
      expect(body.qrPayload).not.toMatch(/password|token|bakalari|student/i);
    } finally {
      h.cleanup();
    }
  });

  it("enforces 60-second QR challenge expiration strictly", async () => {
    const h = makeTestHarness();
    try {
      const createRes = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app" },
      });
      const { qrPayload } = await createRes.json();
      const { challengeId, qrSecret } = parseQrUri(qrPayload);

      // Advance 61 seconds past TTL
      h.advanceMs(61_000);

      const inspectRes = await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });
      expect(inspectRes.status).toBe(410);
    } finally {
      h.cleanup();
    }
  });

  it("prevents QRLJacking / cross-browser session fixation when another browser tries to poll or claim", async () => {
    const h = makeTestHarness();
    try {
      const macUa =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15";
      const createRes = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app", "User-Agent": macUa },
      });
      const victimPairingCookie = extractCookieValue(
        createRes.headers.get("Set-Cookie"),
        "__Host-gradey_qr",
      )!;
      const { challengeId, qrPayload } = await createRes.json();
      const { qrSecret } = parseQrUri(qrPayload);

      // Attacker without victim's HttpOnly pairing cookie cannot read status or SSE
      const unauthStatus = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/status`,
      );
      expect(unauthStatus.status).toBe(403);

      const unauthSse = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/events`,
      );
      expect(unauthSse.status).toBe(403);

      // Victim scans and approves on iPhone
      await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });

      const approveRes = await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId,
          qrSecret,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          student_name: "Jan Novák",
          token_payload: {
            provider: "bakalari",
            baseURL: "https://bakalari.gymnazium.cz/",
            accessToken: "dedicated-web-access-token",
            refreshToken: "dedicated-web-refresh-token",
            tokenType: "Bearer",
            expiresAt: "2026-11-25T11:00:00.000Z",
            webSessionEstablishedAt: "2026-11-25T10:00:05.000Z",
          },
        }),
      });
      expect(approveRes.status).toBe(200);

      // Attacker browser with its own pairing cookie tries to claim victim's challengeId -> 403!
      const attackerClaim = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": macUa,
            Cookie: "__Host-gradey_qr=forged-attacker-cookie",
          },
        },
      );
      expect(attackerClaim.status).toBe(403);

      // Legitimate victim browser with matching HttpOnly pairing cookie succeeds
      const victimClaim = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": macUa,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(victimPairingCookie)}`,
          },
        },
      );
      expect(victimClaim.status).toBe(200);
    } finally {
      h.cleanup();
    }
  });

  it("blocks single-use QR replay and revokes the session if a claimed challenge is replayed", async () => {
    const h = makeTestHarness();
    try {
      const ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36";
      const createRes = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app", "User-Agent": ua },
      });
      const pairingCookie = extractCookieValue(
        createRes.headers.get("Set-Cookie"),
        "__Host-gradey_qr",
      )!;
      const { challengeId, qrPayload } = await createRes.json();
      const { qrSecret } = parseQrUri(qrPayload);

      await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });

      await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId,
          qrSecret,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          student_name: "Jan Novák",
          token_payload: {
            provider: "bakalari",
            baseURL: "https://bakalari.gymnazium.cz/",
            accessToken: "access-1",
            refreshToken: "refresh-1",
            tokenType: "Bearer",
            expiresAt: "2026-11-25T11:00:00.000Z",
            webSessionEstablishedAt: "2026-11-25T10:00:05.000Z",
          },
        }),
      });

      // First claim succeeds
      const claim1 = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": ua,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(pairingCookie)}`,
          },
        },
      );
      expect(claim1.status).toBe(200);
      const sessionCookie = extractCookieValue(
        claim1.headers.get("Set-Cookie"),
        "__Host-gradey_session",
      )!;
      expect(sessionCookie).toBeTruthy();

      // Replaying claim with the old pairing cookie fails with 409 AND revokes the session!
      const replayClaim = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": ua,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(pairingCookie)}`,
          },
        },
      );
      expect(replayClaim.status).toBe(409);

      const checkAfterReplay = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": ua,
          Cookie: `__Host-gradey_session=${encodeURIComponent(sessionCookie)}`,
        },
      });
      const sessionBody = await checkAfterReplay.json();
      expect(sessionBody.authenticated).toBe(false);
    } finally {
      h.cleanup();
    }
  });

  it("rejects raw Bakaláři passwords, missing protocol headers, SSRF URLs, and brute-force secret guesses", async () => {
    const h = makeTestHarness();
    try {
      const createRes = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app" },
      });
      const { challengeId, qrPayload } = await createRes.json();
      const { qrSecret } = parseQrUri(qrPayload);

      await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });

      // 1. Missing tokens-only-v1 protocol header -> 426
      const missingHeader = await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });
      expect(missingHeader.status).toBe(426);

      // 2. Payload containing a raw password -> 400
      const withPassword = await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId,
          qrSecret,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          token_payload: {
            accessToken: "a",
            refreshToken: "r",
            bakalari: { username: "jan", password: "SuperSecretPassword123" },
          },
        }),
      });
      expect(withPassword.status).toBe(400);

      // 3. SSRF internal IP / HTTP school URL -> 422
      for (const badUrl of [
        "http://bakalari.gymnazium.cz/",
        "https://127.0.0.1/",
        "https://169.254.169.254/",
        "https://192.168.1.10/",
        "https://school.localhost/",
      ]) {
        const ssrfRes = await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
          method: "POST",
          headers: {
            Authorization: "Bearer valid-mobile-jwt-user-1",
            "x-gradey-provider-session": "tokens-only-v1",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            challengeId,
            qrSecret,
            provider: "bakalari",
            base_url: badUrl,
            token_payload: {
              baseURL: badUrl,
              accessToken: "a",
              refreshToken: "r",
              webSessionEstablishedAt: "2026-11-25T10:00:00Z",
            },
          }),
        });
        expect(ssrfRes.status).toBe(422);
      }

      // 4. Brute-force wrong qrSecret 5 times permanently invalidates the challenge
      for (let i = 0; i < 5; i += 1) {
        const wrong = await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
          method: "POST",
          headers: {
            Authorization: "Bearer valid-mobile-jwt-user-1",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ challengeId, qrSecret: `wrong-secret-attempt-${i}` }),
        });
        expect(wrong.status).toBe(403);
      }

      // 6th attempt even with the REAL qrSecret now fails with 410 Gone
      const lockedOut = await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });
      expect(lockedOut.status).toBe(410);
    } finally {
      h.cleanup();
    }
  });

  it("encrypts provider tokens at rest with AES-256-GCM, enforces CSRF & OS binding, and rotates session cookies", async () => {
    const h = makeTestHarness();
    try {
      // Direct AES-256-GCM tamper test
      const envelope = encryptProviderSecret(
        {
          provider: "bakalari",
          accessToken: "sensitive-access-xyz",
          refreshToken: "sensitive-refresh-xyz",
          password: "must-be-stripped-before-encryption",
        },
        TEST_MASTER_KEY,
      );
      expect(envelope.toString("utf8")).not.toContain("sensitive-access-xyz");
      expect(envelope.toString("utf8")).not.toContain("must-be-stripped");
      const decrypted = decryptProviderSecret(envelope, TEST_MASTER_KEY);
      expect(decrypted.accessToken).toBe("sensitive-access-xyz");
      expect("password" in decrypted).toBe(false);

      const tampered = Buffer.from(envelope);
      const lastIdx = tampered.length - 1;
      tampered[lastIdx] = (tampered[lastIdx] ?? 0) ^ 0xff;
      expect(() => decryptProviderSecret(tampered, TEST_MASTER_KEY)).toThrow();

      // Establish full browser session
      const macSafariUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15";
      const createRes = await h.app.request("https://web.gradey.app/api/auth/qr/challenges", {
        method: "POST",
        headers: { Origin: "https://web.gradey.app", "User-Agent": macSafariUA },
      });
      const pairingCookie = extractCookieValue(
        createRes.headers.get("Set-Cookie"),
        "__Host-gradey_qr",
      )!;
      const { challengeId, qrPayload } = await createRes.json();
      const { qrSecret } = parseQrUri(qrPayload);

      await h.app.request("https://web.gradey.app/api/mobile/qr/inspect", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ challengeId, qrSecret }),
      });

      await h.app.request("https://web.gradey.app/api/mobile/qr/approve", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-mobile-jwt-user-1",
          "x-gradey-provider-session": "tokens-only-v1",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          challengeId,
          qrSecret,
          provider: "bakalari",
          base_url: "https://bakalari.gymnazium.cz/",
          student_name: "Jan Novák",
          token_payload: {
            provider: "bakalari",
            baseURL: "https://bakalari.gymnazium.cz/",
            accessToken: "super-secret-bakalari-access",
            refreshToken: "super-secret-bakalari-refresh",
            tokenType: "Bearer",
            expiresAt: "2026-11-25T11:00:00.000Z",
            webSessionEstablishedAt: "2026-11-25T10:00:05.000Z",
          },
        }),
      });

      const claimRes = await h.app.request(
        `https://web.gradey.app/api/auth/qr/challenges/${challengeId}/claim`,
        {
          method: "POST",
          headers: {
            Origin: "https://web.gradey.app",
            "User-Agent": macSafariUA,
            Cookie: `__Host-gradey_qr=${encodeURIComponent(pairingCookie)}`,
          },
        },
      );
      const { csrfToken } = await claimRes.json();
      const initialSessionCookie = extractCookieValue(
        claimRes.headers.get("Set-Cookie"),
        "__Host-gradey_session",
      )!;

      // Verify SQLite raw bytes contain ZERO plaintext Bakaláři or cookie tokens
      const rawDb = new DatabaseSync(h.dbPath, { open: true });
      const secretRow = rawDb.prepare("SELECT ciphertext FROM encrypted_secrets LIMIT 1").get() as {
        ciphertext: Uint8Array;
      };
      expect(Buffer.from(secretRow.ciphertext).toString("utf8")).not.toContain(
        "super-secret-bakalari-access",
      );
      const sessRow = rawDb.prepare("SELECT session_token_hash FROM web_sessions LIMIT 1").get() as {
        session_token_hash: string;
      };
      expect(sessRow.session_token_hash).not.toBe(initialSessionCookie);
      rawDb.close();

      // Cross-origin CSRF attack on logout -> 403
      const crossOriginLogout = await h.app.request("https://web.gradey.app/api/auth/logout", {
        method: "POST",
        headers: {
          Origin: "https://evil.attacker.example",
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
          "X-CSRF-Token": csrfToken,
        },
      });
      expect(crossOriginLogout.status).toBe(403);

      // Missing CSRF token on same-origin logout -> 403
      const noCsrfLogout = await h.app.request("https://web.gradey.app/api/auth/logout", {
        method: "POST",
        headers: {
          Origin: "https://web.gradey.app",
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
        },
      });
      expect(noCsrfLogout.status).toBe(403);

      // Session hijacking from a different OS (Windows) -> unauthenticated
      const hijackedCheck = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0",
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
        },
      });
      expect((await hijackedCheck.json()).authenticated).toBe(false);

      // Session token rotation after 16 minutes
      h.advanceMs(16 * 60 * 1000);
      const rotateRes = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
        },
      });
      expect((await rotateRes.json()).authenticated).toBe(true);
      const rotatedCookie = extractCookieValue(
        rotateRes.headers.get("Set-Cookie"),
        "__Host-gradey_session",
      )!;
      expect(rotatedCookie).toBeTruthy();
      expect(rotatedCookie).not.toBe(initialSessionCookie);

      // Within 30s grace window, parallel in-flight request with previous cookie still succeeds
      h.advanceMs(10_000);
      const graceRes = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
        },
      });
      expect((await graceRes.json()).authenticated).toBe(true);

      // After 30s grace window expires, replaying the old cookie triggers theft detection and revokes BOTH tokens!
      h.advanceMs(25_000);
      const stolenOldReuse = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(initialSessionCookie)}`,
        },
      });
      expect((await stolenOldReuse.json()).authenticated).toBe(false);

      const rotatedAfterTheft = await h.app.request("https://web.gradey.app/api/auth/session", {
        headers: {
          "User-Agent": macSafariUA,
          Cookie: `__Host-gradey_session=${encodeURIComponent(rotatedCookie)}`,
        },
      });
      expect((await rotatedAfterTheft.json()).authenticated).toBe(false);
    } finally {
      h.cleanup();
    }
  });
});
