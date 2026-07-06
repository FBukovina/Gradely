import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const [profile, linkedAccounts, preferences, events, gradeHistory] = await Promise.all([
      supabase.from("profiles").select("*").eq("id", user.id).single(),
      supabase.from("linked_accounts").select("*").eq("user_id", user.id),
      supabase.from("notification_preferences").select("*").eq("user_id", user.id).single(),
      supabase.from("new_mark_events").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(500),
      supabase.from("grade_history_events").select("*").eq("user_id", user.id).order("captured_at", { ascending: false }).limit(2000),
    ]);

    return json({
      profile: profile.data,
      linkedAccounts: linkedAccounts.data ?? [],
      notificationPreferences: preferences.data,
      recentNewMarkEvents: events.data ?? [],
      gradeHistoryEvents: gradeHistory.data ?? [],
    });
  } catch (error) {
    return errorResponse(error, "Could not export Gradey account data");
  }
});
