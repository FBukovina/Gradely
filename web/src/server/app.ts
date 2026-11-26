import { createHmac } from "node:crypto";
import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import {
  clientIpHash,
  containsProviderPassword,
  generateOpaqueToken,
  hasDedicatedBakalariWebSession,
  isSecureRequest,
  pairingCookieName,
  parseBrowserDeviceMetadata,
  parseCookies,
  providerURLsMatch,
  requireSafeProviderURL,
  safeCompareHex,
  serializeHttpOnlyCookie,
  sessionCookieName,
  sha256Hex,
  SlidingWindowRateLimiter,
  verifySameOriginRequest,
} from "./security.ts";
import {
  PairingStoreError,
  QR_CHALLENGE_TTL_MS,
  toWebSessionSummary,
  WEB_SESSION_TTL_MS,
  type AuthenticatedWebSessionResult,
  type WebDeviceStore,
} from "./store.ts";
import {
  ProviderReauthRequiredError,
  SchoolProviderProxy,
  type FetchLike,
} from "./schoolClient.ts";
import type { TimetableKind } from "../shared/types.ts";
import { mondayOfWeek, pragueDateString, shiftIsoDays } from "../shared/schoolMath.ts";

export interface AuthenticatedMobileUser {
  userId: string;
  email?: string | null;
}

export type MobileAuthVerifier = (
  bearerToken: string,
) => Promise<AuthenticatedMobileUser | null>;

export interface GradeyWebAppOptions {
  store: WebDeviceStore;
  csrfSecret: string;
  verifyMobileToken: MobileAuthVerifier;
  schoolProxy?: SchoolProviderProxy;
  allowedOrigins?: string[];
  forceSecureCookies?: boolean;
  now?: () => Date;
}

export function createSupabaseMobileVerifier(
  supabaseUrl: string,
  supabaseAnonOrServiceKey: string,
  fetchImpl: FetchLike = fetch,
): MobileAuthVerifier {
  const cleanBase = supabaseUrl.replace(/\/+$/, "");
  return async (bearerToken: string) => {
    if (!bearerToken || bearerToken.length > 8192) return null;
    const response = await fetchImpl(`${cleanBase}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: supabaseAnonOrServiceKey,
        Authorization: `Bearer ${bearerToken}`,
        Accept: "application/json",
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) return null;
    const data = (await response.json()) as Record<string, any>;
    const id = typeof data?.id === "string" ? data.id.trim() : "";
    if (!id) return null;
    return {
      userId: id,
      email: typeof data?.email === "string" ? data.email : null,
    };
  };
}

function deriveCsrfToken(
  csrfSecret: string,
  sessionId: string,
  tokenHash: string,
): string {
  return createHmac("sha256", csrfSecret)
    .update(`gradey-web-csrf-v1:${sessionId}:${tokenHash}`, "utf8")
    .digest("hex");
}

function verifySessionCsrf(
  csrfSecret: string,
  providedCsrf: string | null | undefined,
  authResult: AuthenticatedWebSessionResult,
): boolean {
  if (!providedCsrf || typeof providedCsrf !== "string") return false;
  const expectedCurrent = deriveCsrfToken(
    csrfSecret,
    authResult.record.id,
    authResult.record.sessionTokenHash,
  );
  if (safeCompareHex(providedCsrf, expectedCurrent)) return true;

  if (authResult.record.previousSessionTokenHash) {
    const expectedPrev = deriveCsrfToken(
      csrfSecret,
      authResult.record.id,
      authResult.record.previousSessionTokenHash,
    );
    if (safeCompareHex(providedCsrf, expectedPrev)) return true;
  }
  return false;
}

export function createGradeyWebApp(options: GradeyWebAppOptions): Hono {
  if (!options.csrfSecret || options.csrfSecret.length < 32) {
    throw new Error("csrfSecret must be at least 32 characters");
  }

  const app = new Hono();
  const store = options.store;
  const schoolProxy = options.schoolProxy ?? new SchoolProviderProxy(store);
  const allowedOrigins = new Set(options.allowedOrigins ?? []);
  const nowFn = options.now ?? (() => new Date());

  // Rate limiters against brute-force & DoS
  const qrCreateLimiter = new SlidingWindowRateLimiter(25, 60_000); // 25/min/IP
  const qrClaimLimiter = new SlidingWindowRateLimiter(30, 60_000); // 30/min/IP
  const mobileInspectLimiter = new SlidingWindowRateLimiter(20, 60_000); // 20/min/user+IP

  // Security headers on every response
  app.use("*", async (c, next) => {
    await next();
    c.header("X-Content-Type-Options", "nosniff");
    c.header("X-Frame-Options", "DENY");
    c.header("Referrer-Policy", "no-referrer");
    c.header("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    if (c.req.path.startsWith("/api/")) {
      c.header("Cache-Control", "no-store, no-cache, must-revalidate, private");
      c.header("Pragma", "no-cache");
    } else {
      c.header(
        "Content-Security-Policy",
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
      );
    }
  });

  // Helper: read session cookie & apply rotation Set-Cookie if rotated
  const resolveBrowserSession = async (
    c: any,
    allowRotation = false,
  ): Promise<AuthenticatedWebSessionResult | null> => {
    const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
    const cookies = parseCookies(c.req.header("cookie") ?? null);
    const cookieName = sessionCookieName(secure);
    const rawToken =
      cookies[cookieName] ??
      cookies["__Host-gradey_session"] ??
      cookies["gradey_session"];
    if (!rawToken) return null;

    const device = parseBrowserDeviceMetadata(c.req.raw.headers);
    const now = nowFn();
    const result = await store.authenticateWebSession({
      sessionToken: rawToken,
      userAgentFamily: device.userAgentFamily,
      allowRotation,
      now,
    });

    if (result?.rotatedSessionToken) {
      c.header(
        "Set-Cookie",
        serializeHttpOnlyCookie(cookieName, result.rotatedSessionToken, {
          secure,
          maxAgeSeconds: Math.floor(WEB_SESSION_TTL_MS / 1000),
          sameSite: "Lax",
        }),
        { append: true },
      );
      const nextCsrf = deriveCsrfToken(
        options.csrfSecret,
        result.record.id,
        result.record.sessionTokenHash,
      );
      c.header("X-Gradey-CSRF-Token", nextCsrf);
    }
    return result;
  };

  const clearSessionCookies = (c: any) => {
    const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
    c.header(
      "Set-Cookie",
      serializeHttpOnlyCookie(sessionCookieName(secure), "", {
        secure,
        maxAgeSeconds: 0,
        sameSite: "Lax",
      }),
      { append: true },
    );
  };

  const clearPairingCookie = (c: any) => {
    const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
    c.header(
      "Set-Cookie",
      serializeHttpOnlyCookie(pairingCookieName(secure), "", {
        secure,
        maxAgeSeconds: 0,
        sameSite: "Lax",
      }),
      { append: true },
    );
  };

  const readBrowserPairingSecret = (c: any): string | undefined => {
    const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
    const cookies = parseCookies(c.req.header("cookie") ?? null);
    return (
      cookies[pairingCookieName(secure)] ??
      cookies["__Host-gradey_qr"] ??
      cookies["gradey_qr"]
    );
  };

  const requireMobileAuth = async (c: any): Promise<AuthenticatedMobileUser> => {
    const authHeader = c.req.header("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
    if (!match?.[1]) {
      throw new PairingStoreError("Missing Gradey ID authorization", 401, "unauthorized");
    }
    const verified = await options.verifyMobileToken(match[1].trim());
    if (!verified?.userId) {
      throw new PairingStoreError("Invalid or expired Gradey ID session", 401, "unauthorized");
    }
    return verified;
  };

  // MARK: - Health

  app.get("/api/health", (c) => c.json({ ok: true, service: "gradey-web" }));

  // MARK: - Browser QR Pairing Routes

  app.post("/api/auth/qr/challenges", async (c) => {
    try {
      if (!verifySameOriginRequest(c.req.raw, allowedOrigins)) {
        return c.json({ error: "Cross-origin challenge creation is forbidden" }, 403);
      }

      const now = nowFn();
      const ipHash = clientIpHash(c.req.raw);
      if (!qrCreateLimiter.allow(ipHash, now.getTime())) {
        return c.json({ error: "Too many QR code requests. Wait a moment." }, 429);
      }

      const qrSecret = generateOpaqueToken(32);
      const browserSecret = generateOpaqueToken(32);
      const device = parseBrowserDeviceMetadata(c.req.raw.headers);

      const challenge = await store.createChallenge({
        qrSecretHash: sha256Hex(qrSecret),
        browserBindingHash: sha256Hex(browserSecret),
        userAgentFamily: device.userAgentFamily,
        browserName: device.browserName,
        osName: device.osName,
        deviceLabel: device.deviceLabel,
        ipHash,
        now,
      });

      const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
      c.header(
        "Set-Cookie",
        serializeHttpOnlyCookie(pairingCookieName(secure), browserSecret, {
          secure,
          maxAgeSeconds: 90,
          sameSite: "Lax",
        }),
        { append: true },
      );

      // QR code contains ONLY version + random challenge UUID + 256-bit random token.
      // Never embeds credentials, Bakaláři tokens, or student information.
      const qrPayload = `gradey://pair?v=1&c=${encodeURIComponent(challenge.id)}&t=${encodeURIComponent(qrSecret)}`;

      return c.json({
        challengeId: challenge.id,
        qrPayload,
        expiresAt: challenge.expiresAt,
        ttlSeconds: Math.floor(QR_CHALLENGE_TTL_MS / 1000),
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.get("/api/auth/qr/challenges/:id/status", async (c) => {
    try {
      const challengeId = c.req.param("id");
      const browserSecret = readBrowserPairingSecret(c);
      const challenge = await store.getChallengeForBrowser(
        challengeId,
        browserSecret,
        nowFn(),
      );
      return c.json({
        challengeId: challenge.id,
        status: challenge.status,
        expiresAt: challenge.expiresAt,
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.get("/api/auth/qr/challenges/:id/events", async (c) => {
    try {
      const challengeId = c.req.param("id");
      const browserSecret = readBrowserPairingSecret(c);
      const initial = await store.getChallengeForBrowser(
        challengeId,
        browserSecret,
        nowFn(),
      );

      return streamSSE(c, async (stream) => {
        let closed = false;
        let resolveDone!: () => void;
        const donePromise = new Promise<void>((resolve) => {
          resolveDone = resolve;
        });

        const remainingMs = Math.max(250, Date.parse(initial.expiresAt) - nowFn().getTime());
        const isTerminal = (st: string) =>
          st === "approved" || st === "expired" || st === "rejected" || st === "claimed";

        let lastEmittedStatus = initial.status;
        const emitStatus = (ev: { challengeId: string; status: string; expiresAt: string }) => {
          if (closed) return;
          lastEmittedStatus = ev.status as typeof initial.status;
          void stream
            .writeSSE({
              event: "status",
              data: JSON.stringify(ev),
            })
            .catch(() => {})
            .finally(() => {
              if (isTerminal(ev.status)) {
                cleanup();
                resolveDone();
              }
            });
        };

        // Subscribe BEFORE writing the initial frame so zero events can be missed or deadlocked.
        const unsubscribe = store.events.subscribeChallenge(challengeId, emitStatus);

        // When backed by Supabase (distributed store where mobile updates land in Edge Functions),
        // also poll the challenge status every 1.2s so the open SSE stream pushes real-time transitions.
        const remotePollTimer = store.isDistributed
          ? setInterval(async () => {
              if (closed) return;
              try {
                const latest = await store.getChallengeForBrowser(
                  challengeId,
                  browserSecret,
                  nowFn(),
                );
                if (!closed && latest.status !== lastEmittedStatus) {
                  emitStatus({
                    challengeId: latest.id,
                    status: latest.status,
                    expiresAt: latest.expiresAt,
                  });
                }
              } catch {
                // Handled by expiry timer / client reconnect
              }
            }, 1200)
          : null;

        const expiryTimer = setTimeout(() => {
          if (!closed) {
            void stream
              .writeSSE({
                event: "status",
                data: JSON.stringify({
                  challengeId: initial.id,
                  status: "expired",
                  expiresAt: initial.expiresAt,
                }),
              })
              .catch(() => {})
              .finally(() => {
                cleanup();
                resolveDone();
              });
          } else {
            cleanup();
            resolveDone();
          }
        }, remainingMs);

        const cleanup = () => {
          closed = true;
          clearTimeout(expiryTimer);
          if (remotePollTimer) clearInterval(remotePollTimer);
          unsubscribe();
        };

        stream.onAbort(() => {
          cleanup();
          resolveDone();
        });

        await stream.writeSSE({
          event: "status",
          data: JSON.stringify({
            challengeId: initial.id,
            status: initial.status,
            expiresAt: initial.expiresAt,
          }),
        });

        if (isTerminal(initial.status)) {
          cleanup();
          return;
        }

        await donePromise;
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/auth/qr/challenges/:id/claim", async (c) => {
    try {
      if (!verifySameOriginRequest(c.req.raw, allowedOrigins)) {
        return c.json({ error: "Cross-origin claim request rejected" }, 403);
      }
      const now = nowFn();
      const ipHash = clientIpHash(c.req.raw);
      if (!qrClaimLimiter.allow(ipHash, now.getTime())) {
        return c.json({ error: "Too many attempts. Try again shortly." }, 429);
      }

      const challengeId = c.req.param("id");
      const browserSecret = readBrowserPairingSecret(c);
      const device = parseBrowserDeviceMetadata(c.req.raw.headers);

      const claimed = await store.claimChallengeForBrowser({
        challengeId,
        browserSecret,
        userAgentFamily: device.userAgentFamily,
        now,
      });

      const secure = isSecureRequest(c.req.raw, options.forceSecureCookies);
      clearPairingCookie(c);
      c.header(
        "Set-Cookie",
        serializeHttpOnlyCookie(sessionCookieName(secure), claimed.sessionToken, {
          secure,
          maxAgeSeconds: Math.floor(WEB_SESSION_TTL_MS / 1000),
          sameSite: "Lax",
        }),
        { append: true },
      );

      const csrfToken = deriveCsrfToken(
        options.csrfSecret,
        claimed.session.id,
        sha256Hex(claimed.sessionToken),
      );

      return c.json({
        authenticated: true,
        csrfToken,
        session: claimed.session,
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  // MARK: - Browser Session & Logout Routes

  app.get("/api/auth/session", async (c) => {
    try {
      const auth = await resolveBrowserSession(c, true);
      if (!auth) {
        clearSessionCookies(c);
        return c.json({ authenticated: false });
      }
      const csrfToken = deriveCsrfToken(
        options.csrfSecret,
        auth.record.id,
        auth.record.sessionTokenHash,
      );
      return c.json({
        authenticated: true,
        csrfToken,
        session: toWebSessionSummary(auth.record),
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.get("/api/auth/session/events", async (c) => {
    try {
      const auth = await resolveBrowserSession(c, false);
      if (!auth) {
        return c.json({ error: "Unauthorized" }, 401);
      }
      const sessionId = auth.record.id;

      return streamSSE(c, async (stream) => {
        let resolveDone!: () => void;
        const donePromise = new Promise<void>((resolve) => {
          resolveDone = resolve;
        });

        let closed = false;
        const emitRevoked = (ev: { sessionId: string; type: "revoked"; reason: string }) => {
          if (closed) return;
          closed = true;
          void stream
            .writeSSE({
              event: "revoked",
              data: JSON.stringify(ev),
            })
            .catch(() => {})
            .finally(() => {
              cleanup();
              resolveDone();
            });
        };

        // Subscribe synchronously before the initial writeSSE so revocation events cannot race.
        const unsubscribe = store.events.subscribeSession(sessionId, emitRevoked);

        // Detect mobile-initiated revocations made against Supabase Edge Functions in real time.
        const remoteSessionCheck = store.isDistributed
          ? setInterval(async () => {
              if (closed) return;
              try {
                const stillValid = await resolveBrowserSession(c, false);
                if (!closed && !stillValid) {
                  emitRevoked({
                    sessionId,
                    type: "revoked",
                    reason: "mobile_revoked",
                  });
                }
              } catch {
                // Transient network error; retry on next tick
              }
            }, 4_000)
          : null;

        const heartbeat = setInterval(() => {
          void stream.writeSSE({ event: "ping", data: "{}" }).catch(() => {
            cleanup();
            resolveDone();
          });
        }, 25_000);

        const cleanup = () => {
          closed = true;
          clearInterval(heartbeat);
          if (remoteSessionCheck) clearInterval(remoteSessionCheck);
          unsubscribe();
        };

        stream.onAbort(() => {
          cleanup();
          resolveDone();
        });

        await stream.writeSSE({
          event: "connected",
          data: JSON.stringify({ sessionId }),
        });

        await donePromise;
      });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/auth/logout", async (c) => {
    try {
      if (!verifySameOriginRequest(c.req.raw, allowedOrigins)) {
        return c.json({ error: "Cross-origin logout rejected" }, 403);
      }
      const auth = await resolveBrowserSession(c, false);
      if (!auth) {
        clearSessionCookies(c);
        return c.json({ signedOut: true });
      }
      const csrfHeader = c.req.header("x-csrf-token");
      if (!verifySessionCsrf(options.csrfSecret, csrfHeader, auth)) {
        return c.json({ error: "Invalid CSRF token" }, 403);
      }
      await store.revokeSessionByBrowser(auth.record.id, "browser_logout", nowFn());
      clearSessionCookies(c);
      return c.json({ signedOut: true });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  // MARK: - Mobile Linked-Devices Management & QR Authorization Routes

  app.get("/api/mobile/devices", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const devices = await store.listDevicesForUser(mobileUser.userId, nowFn());
      return c.json({ devices });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/mobile/qr/inspect", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const now = nowFn();
      const rateKey = `${mobileUser.userId}:${clientIpHash(c.req.raw)}`;
      if (!mobileInspectLimiter.allow(rateKey, now.getTime())) {
        return c.json({ error: "Too many scan attempts. Wait a moment." }, 429);
      }

      const body = await c.req.json().catch(() => ({}));
      const challengeId = typeof body?.challengeId === "string" ? body.challengeId.trim() : "";
      const qrSecret = typeof body?.qrSecret === "string" ? body.qrSecret.trim() : "";
      if (!challengeId || !qrSecret) {
        return c.json({ error: "Invalid QR pairing payload" }, 422);
      }

      const preview = await store.inspectChallengeFromMobile({
        challengeId,
        qrSecret,
        userId: mobileUser.userId,
        now,
      });
      return c.json(preview);
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/mobile/qr/reject", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const body = await c.req.json().catch(() => ({}));
      const challengeId = typeof body?.challengeId === "string" ? body.challengeId.trim() : "";
      const qrSecret = typeof body?.qrSecret === "string" ? body.qrSecret.trim() : "";
      if (!challengeId || !qrSecret) {
        return c.json({ error: "Invalid QR pairing payload" }, 422);
      }
      await store.rejectChallengeFromMobile({
        challengeId,
        qrSecret,
        userId: mobileUser.userId,
        now: nowFn(),
      });
      return c.json({ rejected: true });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/mobile/qr/approve", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      if (c.req.header("x-gradey-provider-session") !== "tokens-only-v1") {
        return c.json(
          { error: "Update Gradey to link a web device without sending passwords." },
          426,
        );
      }

      const body = await c.req.json().catch(() => ({}));
      if (containsProviderPassword(body)) {
        return c.json(
          { error: "School passwords cannot be transmitted to Gradey servers." },
          400,
        );
      }

      const challengeId = typeof body?.challengeId === "string" ? body.challengeId.trim() : "";
      const qrSecret = typeof body?.qrSecret === "string" ? body.qrSecret.trim() : "";
      if (!challengeId || !qrSecret) {
        return c.json({ error: "Invalid QR pairing payload" }, 422);
      }

      const provider = body?.provider;
      if (provider !== "bakalari" && provider !== "eduPage") {
        return c.json({ error: "Unsupported school provider" }, 422);
      }

      let safeBaseURL: string;
      let tokenSafeURL: string;
      try {
        safeBaseURL = requireSafeProviderURL(body?.base_url ?? body?.baseURL, "School URL");
        tokenSafeURL = requireSafeProviderURL(
          body?.token_payload?.baseURL ?? safeBaseURL,
          "Token school URL",
        );
      } catch (err) {
        return c.json(
          { error: err instanceof Error ? err.message : "Invalid school URL" },
          422,
        );
      }

      if (!providerURLsMatch(safeBaseURL, tokenSafeURL)) {
        return c.json({ error: "School URL mismatch" }, 422);
      }

      const tokenPayload =
        body?.token_payload && typeof body.token_payload === "object"
          ? (body.token_payload as Record<string, unknown>)
          : {};

      if (provider === "bakalari" && !hasDedicatedBakalariWebSession(tokenPayload)) {
        return c.json(
          { error: "A dedicated Bakaláři web session token family is required." },
          422,
        );
      }

      const device = await store.approveChallengeFromMobile(
        {
          challengeId,
          qrSecret,
          userId: mobileUser.userId,
          linkedAccountId:
            typeof body?.linked_account_id === "string" && body.linked_account_id.trim()
              ? body.linked_account_id.trim()
              : null,
          provider,
          providerUserId:
            typeof body?.provider_user_id === "string" ? body.provider_user_id : null,
          baseURL: safeBaseURL,
          studentName:
            typeof body?.student_name === "string" && body.student_name.trim()
              ? body.student_name.trim()
              : "Student",
          className: typeof body?.class_name === "string" ? body.class_name : null,
          schoolName: typeof body?.school_name === "string" ? body.school_name : null,
          tokenPayload,
        },
        nowFn(),
      );

      return c.json({ device });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.delete("/api/mobile/devices/:id", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const sessionId = c.req.param("id");
      const revoked = await store.revokeSessionForUser(
        mobileUser.userId,
        sessionId,
        "mobile_revoked",
        nowFn(),
      );
      if (!revoked) {
        return c.json({ error: "Linked device not found" }, 404);
      }
      return c.json({ revoked: true });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/mobile/devices/revoke", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const body = await c.req.json().catch(() => ({}));
      const sessionId = typeof body?.sessionId === "string" ? body.sessionId.trim() : "";
      if (!sessionId) return c.json({ error: "Missing sessionId" }, 422);
      const revoked = await store.revokeSessionForUser(
        mobileUser.userId,
        sessionId,
        "mobile_revoked",
        nowFn(),
      );
      if (!revoked) {
        return c.json({ error: "Linked device not found" }, 404);
      }
      return c.json({ revoked: true });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  app.post("/api/mobile/devices/revoke-all", async (c) => {
    try {
      const mobileUser = await requireMobileAuth(c);
      const revokedCount = await store.revokeAllSessionsForUser(
        mobileUser.userId,
        "mobile_revoked_all",
        nowFn(),
      );
      return c.json({ revokedCount });
    } catch (error) {
      return handleApiError(c, error);
    }
  });

  // MARK: - Authenticated Read-Only School Data Routes (BFF)

  const withWebSession = async (
    c: any,
    handler: (auth: AuthenticatedWebSessionResult, now: Date) => Promise<Response>,
  ): Promise<Response> => {
    try {
      const now = nowFn();
      const auth = await resolveBrowserSession(c, true);
      if (!auth) {
        clearSessionCookies(c);
        return c.json({ error: "Session expired or revoked", code: "unauthenticated" }, 401);
      }
      await store.touchSessionActivity(auth.record.id, now);
      return await handler(auth, now);
    } catch (error) {
      if (error instanceof ProviderReauthRequiredError) {
        clearSessionCookies(c);
        return c.json(
          { error: error.message, code: "provider_reauth_required" },
          401,
        );
      }
      return handleApiError(c, error);
    }
  };

  app.get("/api/school/overview", (c) =>
    withWebSession(c, async (auth, now) => {
      const overview = await schoolProxy.fetchOverview(auth.record, now);
      return c.json(overview);
    }),
  );

  app.get("/api/school/marks", (c) =>
    withWebSession(c, async (auth, now) => {
      const marks = await schoolProxy.fetchMarks(auth.record, now);
      return c.json(marks);
    }),
  );

  app.get("/api/school/timetable", (c) =>
    withWebSession(c, async (auth, now) => {
      const rawKind = c.req.query("kind");
      const kind: TimetableKind = rawKind === "permanent" ? "permanent" : "weekly";
      const dateParam = c.req.query("date") ?? mondayOfWeek(now);
      const week = await schoolProxy.fetchTimetable(auth.record, dateParam, kind, now);
      return c.json(week);
    }),
  );

  app.get("/api/school/absences", (c) =>
    withWebSession(c, async (auth, now) => {
      const absences = await schoolProxy.fetchAbsences(auth.record, now);
      return c.json(absences);
    }),
  );

  app.get("/api/school/homeworks", (c) =>
    withWebSession(c, async (auth, now) => {
      const from = c.req.query("from") ?? shiftIsoDays(pragueDateString(now), -14);
      const to = c.req.query("to") ?? shiftIsoDays(pragueDateString(now), 45);
      const homeworks = await schoolProxy.fetchHomeworks(auth.record, from, to, now);
      return c.json(homeworks);
    }),
  );

  app.get("/api/school/profile", (c) =>
    withWebSession(c, async (auth, now) => {
      const user = await schoolProxy.fetchUser(auth.record, now);
      return c.json({
        user,
        session: toWebSessionSummary(auth.record),
      });
    }),
  );

  return app;
}

function handleApiError(c: any, error: unknown): Response {
  if (error instanceof PairingStoreError) {
    return c.json({ error: error.message, code: error.code }, error.statusCode);
  }
  const message = error instanceof Error ? error.message : "Internal server error";
  return c.json({ error: message }, 500);
}
