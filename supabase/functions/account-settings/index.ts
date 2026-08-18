import {
  toLinkedAccount,
  toNotificationPreferences,
} from "../_shared/account-settings.ts";
import { requireUser } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { defaultNotificationPreferences } from "../_shared/notification-delivery.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    if (req.method !== "GET") return json({ error: "Method not allowed" }, 405);
    const { supabase, user } = await requireUser(req);

    const [profileResult, accountsResult, preferencesResult] = await Promise
      .all([
        supabase
          .from("profiles")
          .select(
            "id,email,full_name,avatar_url,active_school_account_id,created_at,updated_at",
          )
          .eq("id", user.id)
          .maybeSingle(),
        supabase
          .from("linked_accounts")
          .select(
            "id,provider,provider_user_id,display_name,school_name,canteen_name,status,notifications_enabled,last_polled_at,last_synced_at,action_required_reason,created_at",
          )
          .eq("user_id", user.id)
          .order("created_at", { ascending: true }),
        supabase
          .from("notification_preferences")
          .select("*")
          .eq("user_id", user.id)
          .maybeSingle(),
      ]);

    if (profileResult.error) throw profileResult.error;
    if (accountsResult.error) throw accountsResult.error;
    if (preferencesResult.error) throw preferencesResult.error;

    let preferences = preferencesResult.data;
    if (!preferences) {
      const { data, error } = await supabase
        .from("notification_preferences")
        .upsert({ user_id: user.id, ...defaultNotificationPreferences }, {
          onConflict: "user_id",
        })
        .select("*")
        .single();
      if (error) throw error;
      preferences = data;
    }

    return json({
      profile: profileResult.data,
      active_school_account_id: profileResult.data?.active_school_account_id ??
        null,
      linked_accounts: (accountsResult.data ?? []).map(toLinkedAccount),
      notification_preferences: toNotificationPreferences(preferences),
    });
  } catch (error) {
    return errorResponse(error, "Could not load account settings");
  }
});
