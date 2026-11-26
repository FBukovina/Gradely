import { randomBytes, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";
import { adminClient, providerSecretKey } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { sanitizeProviderSecret } from "../_shared/provider-secret.ts";

const QR_CHALLENGE_TTL_MS = 60 * 1000;
const WEB_SESSION_IDLE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const WEB_SESSION_ROTATION_INTERVAL_MS = 15 * 60 * 1000;
const ROTATED_TOKEN_GRACE_MS = 30 * 1000;

function requireGatewaySecret(req: Request): Response | null {
  const expected = Deno.env.get("WEB_BFF_GATEWAY_SECRET") ?? "";
  const provided = req.headers.get("x-gradey-bff-secret") ?? "";
  if (!expected || expected.length < 32 || !provided) {
    return json({ error: "Unauthorized gateway request" }, 401);
  }
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(provided, "utf8");
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return json({ error: "Unauthorized gateway request" }, 401);
  }
  return null;
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function safeHexEqual(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

function generateOpaqueToken(byteLength = 32): string {
  return randomBytes(byteLength).toString("base64url");
}

function extractOsToken(family: string): string {
  const parts = family.split(":");
  return (parts[1] ?? "unknown").toLowerCase();
}

function userAgentOsCompatible(expectedFamily: string, actualFamily: string): boolean {
  const expectedOs = extractOsToken(expectedFamily);
  const actualOs = extractOsToken(actualFamily);
  if (expectedOs === "unknown" || actualOs === "unknown") return true;
  return expectedOs === actualOs;
}

function mapChallenge(row: Record<string, unknown>) {
  return {
    id: String(row.id),
    qrSecretHash: String(row.qr_secret_hash),
    browserBindingHash: String(row.browser_binding_hash),
    userAgentFamily: String(row.user_agent_family),
    browserName: String(row.browser_name),
    osName: String(row.os_name),
    deviceLabel: String(row.device_label),
    ipHash: row.ip_hash ? String(row.ip_hash) : null,
    status: String(row.status),
    scannerUserId: row.scanner_user_id ? String(row.scanner_user_id) : null,
    webSessionId: row.web_session_id ? String(row.web_session_id) : null,
    failedAttempts: Number(row.failed_attempts ?? 0),
    createdAt: String(row.created_at),
    scannedAt: row.scanned_at ? String(row.scanned_at) : null,
    approvedAt: row.approved_at ? String(row.approved_at) : null,
    claimedAt: row.claimed_at ? String(row.claimed_at) : null,
    expiresAt: String(row.expires_at),
  };
}

function mapSession(row: Record<string, unknown>) {
  return {
    id: String(row.id),
    userId: String(row.user_id),
    linkedAccountId: row.linked_account_id ? String(row.linked_account_id) : null,
    provider: String(row.provider),
    providerUserId: row.provider_user_id ? String(row.provider_user_id) : null,
    baseURL: String(row.base_url),
    studentName: String(row.student_name),
    className: row.class_name ? String(row.class_name) : null,
    schoolName: row.school_name ? String(row.school_name) : null,
    sessionTokenHash: String(row.session_token_hash),
    previousSessionTokenHash: row.previous_session_token_hash
      ? String(row.previous_session_token_hash)
      : null,
    previousTokenGraceUntil: row.previous_token_grace_until
      ? String(row.previous_token_grace_until)
      : null,
    csrfTokenHash: String(row.csrf_token_hash),
    userAgentFamily: String(row.user_agent_family),
    browserName: String(row.browser_name),
    osName: String(row.os_name),
    deviceLabel: String(row.device_label),
    createdAt: String(row.created_at),
    lastActiveAt: String(row.last_active_at),
    rotatedAt: String(row.rotated_at),
    expiresAt: String(row.expires_at),
    revokedAt: row.revoked_at ? String(row.revoked_at) : null,
    revokeReason: row.revoke_reason ? String(row.revoke_reason) : null,
  };
}

function toSessionSummary(s: ReturnType<typeof mapSession>) {
  return {
    id: s.id,
    provider: s.provider,
    studentName: s.studentName,
    className: s.className,
    schoolName: s.schoolName,
    baseURL: s.baseURL,
    browserName: s.browserName,
    osName: s.osName,
    deviceLabel: s.deviceLabel,
    firstLoginAt: s.createdAt,
    lastActiveAt: s.lastActiveAt,
    expiresAt: s.expiresAt,
  };
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  const authErr = requireGatewaySecret(req);
  if (authErr) return authErr;

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const supabase = adminClient();
    const body = await req.json();
    const action = typeof body?.action === "string" ? body.action : "";
    const now = new Date();
    const nowMs = now.getTime();
    const nowIso = now.toISOString();

    if (action === "create-challenge") {
      const expiresAt = new Date(nowMs + QR_CHALLENGE_TTL_MS).toISOString();
      const { data, error } = await supabase
        .from("web_pairing_challenges")
        .insert({
          qr_secret_hash: String(body.qrSecretHash ?? ""),
          browser_binding_hash: String(body.browserBindingHash ?? ""),
          user_agent_family: String(body.userAgentFamily ?? "unknown:unknown"),
          browser_name: String(body.browserName ?? "Browser"),
          os_name: String(body.osName ?? "Desktop"),
          device_label: String(body.deviceLabel ?? "Browser"),
          ip_hash: body.ipHash ? String(body.ipHash) : null,
          status: "pending",
          expires_at: expiresAt,
        })
        .select("*")
        .single();
      if (error || !data) throw error ?? new Error("Failed to create challenge");
      return json({ challenge: mapChallenge(data) });
    }

    if (action === "get-challenge") {
      const challengeId = String(body.challengeId ?? "");
      const browserSecret = typeof body.browserSecret === "string" ? body.browserSecret : "";
      const { data, error } = await supabase
        .from("web_pairing_challenges")
        .select("*")
        .eq("id", challengeId)
        .maybeSingle();
      if (error) throw error;
      if (!data) {
        return json({ error: "Challenge not found", code: "challenge_not_found" }, 404);
      }
      const challenge = mapChallenge(data);
      if (!browserSecret) {
        return json(
          { error: "Pairing challenge is bound to a different browser session", code: "browser_binding_mismatch" },
          403,
        );
      }
      const computedBinding = await sha256Hex(browserSecret);
      if (!safeHexEqual(computedBinding, challenge.browserBindingHash)) {
        return json(
          { error: "Pairing challenge is bound to a different browser session", code: "browser_binding_mismatch" },
          403,
        );
      }
      if (
        Date.parse(challenge.expiresAt) <= nowMs &&
        (challenge.status === "pending" || challenge.status === "scanned")
      ) {
        await supabase
          .from("web_pairing_challenges")
          .update({ status: "expired" })
          .eq("id", challenge.id);
        challenge.status = "expired";
      }
      return json({ challenge });
    }

    if (action === "claim-challenge") {
      const challengeId = String(body.challengeId ?? "");
      const browserSecret = typeof body.browserSecret === "string" ? body.browserSecret : "";
      const userAgentFamily = String(body.userAgentFamily ?? "unknown:unknown");

      const { data, error } = await supabase
        .from("web_pairing_challenges")
        .select("*")
        .eq("id", challengeId)
        .maybeSingle();
      if (error) throw error;
      if (!data) {
        return json({ error: "Challenge not found", code: "challenge_not_found" }, 404);
      }
      const challenge = mapChallenge(data);
      const computedBinding = browserSecret ? await sha256Hex(browserSecret) : "";
      if (!computedBinding || !safeHexEqual(computedBinding, challenge.browserBindingHash)) {
        return json(
          { error: "Pairing challenge is bound to a different browser session", code: "browser_binding_mismatch" },
          403,
        );
      }

      if (challenge.status === "claimed" || challenge.claimedAt != null) {
        if (challenge.webSessionId && challenge.scannerUserId) {
          await supabase.rpc("revoke_web_session", {
            p_user_id: challenge.scannerUserId,
            p_session_id: challenge.webSessionId,
            p_reason: "challenge_replay_detected",
          });
        }
        return json({ error: "Pairing challenge already claimed", code: "challenge_already_claimed" }, 409);
      }
      if (Date.parse(challenge.expiresAt) + 30_000 <= nowMs) {
        return json({ error: "Pairing challenge expired", code: "challenge_expired" }, 410);
      }
      if (challenge.status !== "approved" || !challenge.webSessionId) {
        return json({ error: "Challenge not approved yet", code: "challenge_not_approved" }, 409);
      }
      if (!userAgentOsCompatible(challenge.userAgentFamily, userAgentFamily)) {
        return json({ error: "Browser environment mismatch", code: "environment_mismatch" }, 403);
      }

      const { data: claimed, error: claimErr } = await supabase
        .from("web_pairing_challenges")
        .update({ status: "claimed", claimed_at: nowIso })
        .eq("id", challenge.id)
        .eq("status", "approved")
        .is("claimed_at", null)
        .select("*")
        .maybeSingle();

      if (claimErr || !claimed) {
        return json({ error: "Pairing challenge already claimed", code: "challenge_already_claimed" }, 409);
      }

      const sessionToken = generateOpaqueToken(32);
      const csrfToken = generateOpaqueToken(32);
      const sessionTokenHash = await sha256Hex(sessionToken);
      const csrfTokenHash = await sha256Hex(csrfToken);

      const { data: updatedSession, error: sessErr } = await supabase
        .from("web_sessions")
        .update({
          session_token_hash: sessionTokenHash,
          csrf_token_hash: csrfTokenHash,
          last_active_at: nowIso,
          rotated_at: nowIso,
        })
        .eq("id", challenge.webSessionId)
        .is("revoked_at", null)
        .select("*")
        .maybeSingle();

      if (sessErr || !updatedSession) {
        return json({ error: "Web session is unavailable", code: "session_revoked" }, 410);
      }

      return json({
        claimed: {
          sessionToken,
          csrfToken,
          session: toSessionSummary(mapSession(updatedSession)),
        },
      });
    }

    if (action === "authenticate-session") {
      const sessionToken = typeof body.sessionToken === "string" ? body.sessionToken : "";
      const userAgentFamily = String(body.userAgentFamily ?? "unknown:unknown");
      const allowRotation = body.allowRotation === true;
      if (!sessionToken) return json({ result: null });

      const incomingHash = await sha256Hex(sessionToken);
      let { data: row } = await supabase
        .from("web_sessions")
        .select("*")
        .eq("session_token_hash", incomingHash)
        .is("revoked_at", null)
        .maybeSingle();

      let matchedPreviousGrace = false;
      if (!row) {
        const prev = await supabase
          .from("web_sessions")
          .select("*")
          .eq("previous_session_token_hash", incomingHash)
          .is("revoked_at", null)
          .maybeSingle();
        if (prev.data) {
          const graceUntil = prev.data.previous_token_grace_until
            ? Date.parse(String(prev.data.previous_token_grace_until))
            : 0;
          if (graceUntil > nowMs) {
            row = prev.data;
            matchedPreviousGrace = true;
          } else {
            await supabase.rpc("revoke_web_session", {
              p_user_id: String(prev.data.user_id),
              p_session_id: String(prev.data.id),
              p_reason: "rotated_token_reuse",
            });
            return json({ result: null });
          }
        }
      }

      if (!row) return json({ result: null });
      const session = mapSession(row);

      if (
        Date.parse(session.expiresAt) <= nowMs ||
        Date.parse(session.lastActiveAt) + WEB_SESSION_IDLE_TTL_MS <= nowMs
      ) {
        await supabase.rpc("revoke_web_session", {
          p_user_id: session.userId,
          p_session_id: session.id,
          p_reason: "session_expired",
        });
        return json({ result: null });
      }

      if (!userAgentOsCompatible(session.userAgentFamily, userAgentFamily)) {
        return json({ result: null });
      }

      if (
        allowRotation &&
        !matchedPreviousGrace &&
        Date.parse(session.rotatedAt) + WEB_SESSION_ROTATION_INTERVAL_MS <= nowMs
      ) {
        const nextToken = generateOpaqueToken(32);
        const nextCsrf = generateOpaqueToken(32);
        const graceUntil = new Date(nowMs + ROTATED_TOKEN_GRACE_MS).toISOString();
        const { data: rotated } = await supabase
          .from("web_sessions")
          .update({
            previous_session_token_hash: session.sessionTokenHash,
            previous_token_grace_until: graceUntil,
            session_token_hash: await sha256Hex(nextToken),
            csrf_token_hash: await sha256Hex(nextCsrf),
            rotated_at: nowIso,
            last_active_at: nowIso,
          })
          .eq("id", session.id)
          .is("revoked_at", null)
          .select("*")
          .maybeSingle();
        if (rotated) {
          return json({
            result: {
              record: mapSession(rotated),
              rotatedSessionToken: nextToken,
              rotatedCsrfToken: nextCsrf,
            },
          });
        }
      }

      return json({ result: { record: session } });
    }

    if (action === "read-secret") {
      const sessionId = String(body.sessionId ?? "");
      const { data: session } = await supabase
        .from("web_sessions")
        .select("secret_id")
        .eq("id", sessionId)
        .is("revoked_at", null)
        .maybeSingle();
      if (!session?.secret_id) return json({ secret: null });

      const { data: secret, error } = await supabase.rpc("read_provider_secret", {
        p_secret_id: session.secret_id,
        p_key: providerSecretKey(),
      });
      if (error || !secret) return json({ secret: null });
      return json({ secret });
    }

    if (action === "update-secret") {
      const sessionId = String(body.sessionId ?? "");
      const userId = String(body.userId ?? "");
      const payload = (body.payload ?? {}) as Record<string, unknown>;
      const { data: session } = await supabase
        .from("web_sessions")
        .select("secret_id")
        .eq("id", sessionId)
        .eq("user_id", userId)
        .is("revoked_at", null)
        .maybeSingle();
      if (!session?.secret_id) {
        return json({ error: "Session is no longer active", code: "session_revoked" }, 401);
      }
      const { error } = await supabase.rpc("update_provider_secret", {
        p_secret_id: session.secret_id,
        p_user_id: userId,
        p_payload: sanitizeProviderSecret(payload),
        p_key: providerSecretKey(),
      });
      if (error) throw error;
      return json({ updated: true });
    }

    if (action === "touch-session") {
      const sessionId = String(body.sessionId ?? "");
      await supabase
        .from("web_sessions")
        .update({ last_active_at: nowIso })
        .eq("id", sessionId)
        .is("revoked_at", null);
      return json({ ok: true });
    }

    if (action === "revoke-session") {
      const sessionId = String(body.sessionId ?? "");
      const reason = typeof body.reason === "string" ? body.reason : "browser_logout";
      const { data } = await supabase
        .from("web_sessions")
        .select("user_id")
        .eq("id", sessionId)
        .maybeSingle();
      if (data?.user_id) {
        await supabase.rpc("revoke_web_session", {
          p_user_id: String(data.user_id),
          p_session_id: sessionId,
          p_reason: reason,
        });
      }
      return json({ revoked: true });
    }

    return json({ error: "Unknown gateway action" }, 400);
  } catch (error) {
    return errorResponse(error, "Web BFF gateway failed");
  }
});
