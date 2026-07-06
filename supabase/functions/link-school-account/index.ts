import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const body = await req.json();
    const provider = body.provider;
    if (provider !== "bakalari" && provider !== "eduPage") {
      return json({ error: "Unsupported school provider" }, 422);
    }

    const { data: secretID, error: secretError } = await supabase.rpc("store_provider_secret", {
      p_user_id: user.id,
      p_payload: body.token_payload,
      p_key: providerSecretKey(),
    });
    if (secretError) throw secretError;

    const { data, error } = await supabase
      .from("linked_accounts")
      .insert({
        user_id: user.id,
        provider,
        provider_user_id: body.provider_user_id,
        base_url: body.base_url,
        display_name: body.display_name || provider,
        school_name: body.school_name,
        status: "active",
        notifications_enabled: true,
        secret_id: secretID,
        last_synced_at: new Date().toISOString(),
        next_poll_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      })
      .select()
      .single();
    if (error) throw error;

    await supabase
      .from("profiles")
      .update({ active_school_account_id: data.id, updated_at: new Date().toISOString() })
      .eq("id", user.id)
      .is("active_school_account_id", null);

    await supabase.from("account_audit_logs").insert({
      user_id: user.id,
      linked_account_id: data.id,
      event_name: "linked_school_account",
      metadata: { provider },
    });

    return json(toLinkedAccount(data));
  } catch (error) {
    return errorResponse(error, "Could not link school account");
  }
});

function toLinkedAccount(row: Record<string, unknown>) {
  return {
    id: row.id,
    provider: row.provider,
    providerUserID: row.provider_user_id,
    displayName: row.display_name,
    schoolName: row.school_name,
    canteenName: row.canteen_name,
    status: row.status,
    notificationsEnabled: row.notifications_enabled,
    lastPolledAt: row.last_polled_at,
    lastSyncedAt: row.last_synced_at,
    actionRequiredReason: row.action_required_reason,
  };
}
