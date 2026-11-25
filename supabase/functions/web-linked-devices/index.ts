import { timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";
import { providerSecretKey, requireUser } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import {
  containsProviderPassword,
  hasDedicatedBakalariWebSession,
  sanitizeProviderSecret,
} from "../_shared/provider-secret.ts";
import {
  providerURLsMatch,
  requireSafeProviderURL,
} from "../_shared/provider-url.ts";

const MAX_FAILED_ATTEMPTS = 5;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const url = new URL(req.url);
    const action = url.searchParams.get("action") ??
      (req.method === "GET" ? "list" : "");

    if (req.method === "GET" && action === "list") {
      const nowIso = new Date().toISOString();
      const { data, error } = await supabase
        .from("web_sessions")
        .select(
          "id,provider,student_name,class_name,school_name,browser_name,os_name,device_label,created_at,last_active_at,expires_at",
        )
        .eq("user_id", user.id)
        .is("revoked_at", null)
        .gt("expires_at", nowIso)
        .order("last_active_at", { ascending: false });
      if (error) throw error;
      return json({
        devices: (data ?? []).map((row) => ({
          id: row.id,
          provider: row.provider,
          studentName: row.student_name,
          className: row.class_name,
          schoolName: row.school_name,
          browserName: row.browser_name,
          osName: row.os_name,
          deviceLabel: row.device_label,
          firstLoginAt: row.created_at,
          lastActiveAt: row.last_active_at,
          expiresAt: row.expires_at,
        })),
      });
    }

    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    if (action === "approve") {
      if (req.headers.get("x-gradey-provider-session") !== "tokens-only-v1") {
        return json({
          error: "Update Gradey to link a web device without sending passwords.",
        }, 426);
      }
    }

    const body = await req.json();

    if (action === "revoke") {
      const sessionId = typeof body?.sessionId === "string"
        ? body.sessionId.trim()
        : "";
      if (!sessionId) return json({ error: "Missing sessionId" }, 422);
      const { data, error } = await supabase.rpc("revoke_web_session", {
        p_user_id: user.id,
        p_session_id: sessionId,
        p_reason: "mobile_revoked",
      });
      if (error) throw error;
      if (!data) return json({ error: "Linked device not found" }, 404);
      return json({ revoked: true });
    }

    if (action === "revoke-all") {
      const { data, error } = await supabase.rpc("revoke_all_web_sessions", {
        p_user_id: user.id,
        p_reason: "mobile_revoked_all",
      });
      if (error) throw error;
      return json({ revokedCount: Number(data ?? 0) });
    }

    if (action === "inspect" || action === "reject" || action === "approve") {
      const challengeId = typeof body?.challengeId === "string"
        ? body.challengeId.trim()
        : "";
      const qrSecret = typeof body?.qrSecret === "string"
        ? body.qrSecret.trim()
        : "";
      if (!challengeId || !qrSecret) {
        return json({ error: "Invalid QR pairing code" }, 422);
      }

      const { data: challenge, error: fetchError } = await supabase
        .from("web_pairing_challenges")
        .select("*")
        .eq("id", challengeId)
        .maybeSingle();
      if (fetchError) throw fetchError;
      if (!challenge) {
        return json({ error: "QR code is invalid or has expired." }, 404);
      }

      const now = Date.now();
      if (
        Date.parse(challenge.expires_at) <= now ||
        challenge.status === "expired" ||
        challenge.status === "claimed" ||
        challenge.status === "rejected" ||
        (challenge.failed_attempts ?? 0) >= MAX_FAILED_ATTEMPTS
      ) {
        return json({ error: "QR code has expired. Scan the new code on screen." }, 410);
      }

      const providedHash = await sha256Hex(qrSecret);
      if (!safeHexEqual(providedHash, challenge.qr_secret_hash)) {
        const attempts = (challenge.failed_attempts ?? 0) + 1;
        await supabase
          .from("web_pairing_challenges")
          .update({
            failed_attempts: attempts,
            status: attempts >= MAX_FAILED_ATTEMPTS ? "expired" : challenge.status,
          })
          .eq("id", challenge.id);
        return json({ error: "Invalid QR pairing code." }, 403);
      }

      if (
        challenge.scanner_user_id && challenge.scanner_user_id !== user.id
      ) {
        return json({ error: "QR code has already been scanned." }, 409);
      }

      if (action === "inspect") {
        if (challenge.status !== "pending" && challenge.status !== "scanned") {
          return json({ error: "QR code has already been used." }, 409);
        }
        const { data: updated, error: updateError } = await supabase
          .from("web_pairing_challenges")
          .update({
            status: "scanned",
            scanner_user_id: user.id,
            scanned_at: challenge.scanned_at ?? new Date().toISOString(),
          })
          .eq("id", challenge.id)
          .in("status", ["pending", "scanned"])
          .select("*")
          .maybeSingle();
        if (updateError) throw updateError;
        if (!updated) {
          return json({ error: "QR code is no longer available." }, 409);
        }
        return json({
          challengeId: updated.id,
          browserName: updated.browser_name,
          osName: updated.os_name,
          deviceLabel: updated.device_label,
          createdAt: updated.created_at,
          expiresAt: updated.expires_at,
        });
      }

      if (action === "reject") {
        await supabase
          .from("web_pairing_challenges")
          .update({ status: "rejected" })
          .eq("id", challenge.id)
          .in("status", ["pending", "scanned"]);
        return json({ rejected: true });
      }

      if (action === "approve") {
        if (containsProviderPassword(body)) {
          return json({
            error: "School passwords cannot be sent to Gradey servers.",
          }, 400);
        }
        if (challenge.status !== "scanned" || challenge.scanner_user_id !== user.id) {
          return json({ error: "Scan the QR code again before approving." }, 409);
        }

        const provider = body?.provider;
        if (provider !== "bakalari" && provider !== "eduPage") {
          return json({ error: "Unsupported school provider." }, 422);
        }
        const safeBaseURL = requireSafeProviderURL(body?.base_url, "School URL");
        const rawPayload = body?.token_payload ?? {};
        const payloadSafeURL = requireSafeProviderURL(
          rawPayload?.baseURL ?? safeBaseURL,
          "Token school URL",
        );
        if (!providerURLsMatch(safeBaseURL, payloadSafeURL)) {
          return json({ error: "School URL mismatch." }, 422);
        }
        if (
          provider === "bakalari" && !hasDedicatedBakalariWebSession(rawPayload)
        ) {
          return json({
            error: "Dedicated Bakaláři web session tokens are required.",
          }, 422);
        }

        const sanitized = sanitizeProviderSecret({
          ...rawPayload,
          provider,
          baseURL: safeBaseURL,
        });

        const { data: secretId, error: secretError } = await supabase.rpc(
          "store_provider_secret",
          {
            p_user_id: user.id,
            p_payload: sanitized,
            p_key: providerSecretKey(),
          },
        );
        if (secretError) throw secretError;

        const linkedAccountId = typeof body?.linked_account_id === "string" &&
            body.linked_account_id.length > 0
          ? body.linked_account_id
          : null;
        const placeholderHash = await sha256Hex(crypto.randomUUID() + crypto.randomUUID());
        const placeholderCsrf = await sha256Hex(crypto.randomUUID() + crypto.randomUUID());

        const { data: sessionRow, error: sessionError } = await supabase
          .from("web_sessions")
          .insert({
            user_id: user.id,
            linked_account_id: linkedAccountId,
            provider,
            provider_user_id: typeof body?.provider_user_id === "string"
              ? body.provider_user_id
              : null,
            base_url: safeBaseURL,
            student_name: typeof body?.student_name === "string" &&
                body.student_name.trim().length > 0
              ? body.student_name.trim().slice(0, 120)
              : "Student",
            class_name: typeof body?.class_name === "string"
              ? body.class_name.trim().slice(0, 40)
              : null,
            school_name: typeof body?.school_name === "string"
              ? body.school_name.trim().slice(0, 160)
              : null,
            secret_id: secretId,
            session_token_hash: placeholderHash,
            csrf_token_hash: placeholderCsrf,
            user_agent_family: challenge.user_agent_family,
            browser_name: challenge.browser_name,
            os_name: challenge.os_name,
            device_label: challenge.device_label,
            expires_at: new Date(now + SESSION_TTL_MS).toISOString(),
          })
          .select("*")
          .single();
        if (sessionError) throw sessionError;

        const { data: approvedChallenge, error: approveError } = await supabase
          .from("web_pairing_challenges")
          .update({
            status: "approved",
            web_session_id: sessionRow.id,
            approved_at: new Date().toISOString(),
          })
          .eq("id", challenge.id)
          .eq("status", "scanned")
          .eq("scanner_user_id", user.id)
          .select("*")
          .maybeSingle();

        if (approveError || !approvedChallenge) {
          await supabase.rpc("revoke_web_session", {
            p_user_id: user.id,
            p_session_id: sessionRow.id,
            p_reason: "challenge_race_cleanup",
          });
          return json({ error: "QR challenge could not be approved." }, 409);
        }

        await supabase.from("account_audit_logs").insert({
          user_id: user.id,
          linked_account_id: linkedAccountId,
          event_name: "web_session_linked",
          metadata: {
            web_session_id: sessionRow.id,
            browser_name: challenge.browser_name,
            os_name: challenge.os_name,
          },
        });

        return json({
          device: {
            id: sessionRow.id,
            provider: sessionRow.provider,
            studentName: sessionRow.student_name,
            className: sessionRow.class_name,
            schoolName: sessionRow.school_name,
            browserName: sessionRow.browser_name,
            osName: sessionRow.os_name,
            deviceLabel: sessionRow.device_label,
            firstLoginAt: sessionRow.created_at,
            lastActiveAt: sessionRow.last_active_at,
            expiresAt: sessionRow.expires_at,
          },
        });
      }
    }

    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    return errorResponse(error, "Web device request failed");
  }
});

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function safeHexEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}
