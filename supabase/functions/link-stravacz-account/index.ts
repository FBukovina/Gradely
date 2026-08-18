import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";
import { requireSafeProviderURL } from "../_shared/provider-url.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const body = await req.json();
    const serviceURL = requireSafeProviderURL(body.service_url, "StravaCZ service URL");

    const { data: secretID, error: secretError } = await supabase.rpc("store_provider_secret", {
      p_user_id: user.id,
      p_payload: {
        provider: "stravaCZ",
        serviceURL,
        sessionID: body.session_id,
        canteenNumber: body.canteen_number,
        username: body.username,
      },
      p_key: providerSecretKey(),
    });
    if (secretError) throw secretError;

    const { data, error } = await supabase
      .from("linked_accounts")
      .insert({
        user_id: user.id,
        provider: "stravaCZ",
        provider_user_id: body.username,
        display_name: body.display_name || body.username,
        canteen_name: body.canteen_name,
        status: "active",
        notifications_enabled: false,
        secret_id: secretID,
        last_synced_at: new Date().toISOString(),
      })
      .select()
      .single();
    if (error) throw error;

    await supabase.from("account_audit_logs").insert({
      user_id: user.id,
      linked_account_id: data.id,
      event_name: "linked_stravacz_account",
      metadata: {},
    });

    return json({
      id: data.id,
      provider: data.provider,
      providerUserID: data.provider_user_id,
      displayName: data.display_name,
      schoolName: null,
      canteenName: data.canteen_name,
      status: data.status,
      notificationsEnabled: data.notifications_enabled,
      lastPolledAt: data.last_polled_at,
      lastSyncedAt: data.last_synced_at,
      actionRequiredReason: data.action_required_reason,
    });
  } catch (error) {
    return errorResponse(error, "Could not link StravaCZ account");
  }
});
