import { toLinkedAccount } from "../_shared/account-settings.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
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
    const body = await req.json();
    if (typeof body.id !== "string" || body.id.length === 0) {
      return json({ error: "Missing linked account id" }, 422);
    }
    if (!body.token_payload || typeof body.token_payload !== "object") {
      return json({ error: "Missing provider token payload" }, 422);
    }

    const { data: account, error: accountError } = await supabase
      .from("linked_accounts")
      .select("*")
      .eq("id", body.id)
      .eq("user_id", user.id)
      .in("provider", ["bakalari", "eduPage"])
      .maybeSingle();
    if (accountError) throw accountError;
    if (!account) {
      return json({ error: "Linked school account not found" }, 404);
    }

    const provider = body.provider ?? account.provider;
    if (
      provider !== account.provider ||
      body.token_payload.provider !== account.provider
    ) {
      return json({
        error: "Relinked provider must match the existing account",
      }, 422);
    }

    const suppliedTokenBaseURL = requireSafeProviderURL(
      body.token_payload.baseURL,
      "Token school URL",
    );
    const suppliedBaseURL = requireSafeProviderURL(
      body.base_url ?? suppliedTokenBaseURL,
      "School URL",
    );
    if (!providerURLsMatch(suppliedBaseURL, suppliedTokenBaseURL)) {
      return json({ error: "School provider details do not match" }, 422);
    }

    const tokenBaseURL = canonicalSchoolBaseURL(suppliedTokenBaseURL);
    const baseURL = canonicalSchoolBaseURL(suppliedBaseURL);

    const tokenPayload = { ...body.token_payload, baseURL: tokenBaseURL };
    const providerUserID = canonicalSchoolProviderUserID(
      provider,
      body.provider_user_id,
      tokenPayload,
    );
    if (
      account.provider_user_id && providerUserID &&
      account.provider_user_id.trim() !== providerUserID
    ) {
      return json({
        error: "The refreshed credentials belong to a different school account",
      }, 422);
    }
    const { data, error } = await supabase.rpc(
      "relink_owned_school_link",
      {
        p_user_id: user.id,
        p_account_id: account.id,
        p_provider: provider,
        p_provider_user_id: providerUserID,
        p_base_url: baseURL,
        p_display_name: body.display_name || account.display_name,
        p_school_name: body.school_name ?? account.school_name,
        p_payload: tokenPayload,
        p_key: providerSecretKey(),
      },
    );
    if (error) throw error;
    if (!data) return json({ error: "Linked school account not found" }, 404);

    const { error: auditError } = await supabase.from("account_audit_logs")
      .insert({
        user_id: user.id,
        linked_account_id: data.id,
        event_name: "relinked_school_account",
        metadata: { provider: data.provider },
      });
    if (auditError) throw auditError;

    return json(toLinkedAccount(data));
  } catch (error) {
    return errorResponse(error, "Could not reconnect school account");
  }
});
