import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";
import { toLinkedAccount } from "../_shared/account-settings.ts";
import { containsProviderPassword, hasDedicatedBakalariPollingSession, sanitizeProviderSecret } from "../_shared/provider-secret.ts";
import {
  providerURLsMatch,
  requireSafeProviderURL,
} from "../_shared/provider-url.ts";
import {
  canonicalSchoolBaseURL,
  canonicalSchoolProviderUserID,
} from "../_shared/school-account-identity.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    const { supabase, user } = await requireUser(req);
    if (req.headers.get("x-gradey-provider-session") !== "tokens-only-v1") {
      return json({ error: "Update Gradey to link school accounts without uploading school passwords." }, 426);
    }
    const body = await req.json();
    if (containsProviderPassword(body)) {
      return json({ error: "Update Gradey and reconnect your school account. School passwords are no longer accepted." }, 426);
    }
    const provider = body.provider;
    if (provider !== "bakalari" && provider !== "eduPage") {
      return json({ error: "Unsupported school provider" }, 422);
    }

    if (!body.token_payload || typeof body.token_payload !== "object" || Array.isArray(body.token_payload)) {
      return json({ error: "Missing provider token payload" }, 422);
    }

    const suppliedBaseURL = requireSafeProviderURL(
      body.base_url,
      "School URL",
    );
    const suppliedTokenBaseURL = requireSafeProviderURL(
      body.token_payload.baseURL,
      "Token school URL",
    );
    if (
      !providerURLsMatch(suppliedBaseURL, suppliedTokenBaseURL) ||
      body.token_payload.provider !== provider
    ) {
      return json({ error: "School provider details do not match" }, 422);
    }

    const baseURL = canonicalSchoolBaseURL(suppliedBaseURL);
    const tokenBaseURL = canonicalSchoolBaseURL(suppliedTokenBaseURL);

    const tokenPayload = sanitizeProviderSecret({ ...body.token_payload, baseURL: tokenBaseURL });
    if (provider === "bakalari" && !hasDedicatedBakalariPollingSession(tokenPayload)) {
      return json({ error: "Update Gradey and reconnect your school account to enable background mark checks." }, 426);
    }
    const providerUserID = canonicalSchoolProviderUserID(
      provider,
      body.provider_user_id,
      tokenPayload,
    );

    const { data, error } = await supabase.rpc("upsert_school_link", {
      p_user_id: user.id,
      p_payload: tokenPayload,
      p_key: providerSecretKey(),
      p_provider: provider,
      p_provider_user_id: providerUserID,
      p_base_url: baseURL,
      p_display_name: body.display_name || provider,
      p_school_name: body.school_name ?? null,
    });
    if (error) throw error;

    const { error: profileError } = await supabase
      .from("profiles")
      .update({
        active_school_account_id: data.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", user.id)
      .is("active_school_account_id", null);
    if (profileError) throw profileError;

    const { error: auditError } = await supabase.from("account_audit_logs")
      .insert({
        user_id: user.id,
        linked_account_id: data.id,
        event_name: "linked_school_account",
        metadata: { provider },
      });
    if (auditError) throw auditError;

    return json(toLinkedAccount(data));
  } catch (error) {
    return errorResponse(error, "Could not link school account");
  }
});
