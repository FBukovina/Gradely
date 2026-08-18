import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";
import { toNotificationPreferences } from "../_shared/account-settings.ts";
import { parseNotificationPreferences } from "../_shared/notification-delivery.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    const { supabase, user } = await requireUser(req);
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid notification preferences" }, 422);
    }

    const { data: current, error: currentError } = await supabase
      .from("notification_preferences")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();
    if (currentError) throw currentError;

    let preferences;
    try {
      preferences = parseNotificationPreferences(body, current ?? undefined);
    } catch (error) {
      return json({
        error: error instanceof Error
          ? error.message
          : "Invalid notification preferences",
      }, 422);
    }

    const { data, error } = await supabase
      .from("notification_preferences")
      .upsert({
        user_id: user.id,
        ...preferences,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" })
      .select("*")
      .single();
    if (error) throw error;

    return json({ notification_preferences: toNotificationPreferences(data) });
  } catch (error) {
    return errorResponse(error, "Could not update notification preferences");
  }
});
