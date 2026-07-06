import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const { id } = await req.json();
    if (!id) return json({ error: "Missing linked account id" }, 422);

    const { data: account, error } = await supabase
      .from("linked_accounts")
      .select("*")
      .eq("id", id)
      .eq("user_id", user.id)
      .in("provider", ["bakalari", "eduPage"])
      .single();
    if (error) throw error;
    if (!account) return json({ error: "Linked account not found" }, 404);
    if (account.status !== "active") {
      return json({ error: "Linked account is not active" }, 409);
    }
    if (!account.secret_id) {
      return json({ error: "Linked account is missing provider credentials" }, 409);
    }

    const { data: tokenPayload, error: secretError } = await supabase.rpc("read_provider_secret", {
      p_secret_id: account.secret_id,
      p_key: providerSecretKey(),
    });
    if (secretError) throw secretError;

    const { error: profileError } = await supabase
      .from("profiles")
      .update({ active_school_account_id: account.id, updated_at: new Date().toISOString() })
      .eq("id", user.id);
    if (profileError) throw profileError;

    await supabase.from("account_audit_logs").insert({
      user_id: user.id,
      linked_account_id: account.id,
      event_name: "activated_school_account",
      metadata: { provider: account.provider },
    });

    return json({
      account: toLinkedAccount(account),
      token_payload: tokenPayload,
    });
  } catch (error) {
    return errorResponse(error, "Could not activate school account");
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
