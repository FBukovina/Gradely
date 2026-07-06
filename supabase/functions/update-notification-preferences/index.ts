import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const body = await req.json();
    const { error } = await supabase
      .from("notification_preferences")
      .upsert({
        user_id: user.id,
        new_marks_enabled: body.newMarksEnabled ?? body.new_marks_enabled ?? true,
        lock_screen_detail: body.lockScreenDetail ?? body.lock_screen_detail ?? "mark_and_subject",
        quiet_hours_enabled: body.quietHoursEnabled ?? body.quiet_hours_enabled ?? false,
        quiet_hours_start_minute: body.quietHoursStartMinute ?? body.quiet_hours_start_minute ?? 1320,
        quiet_hours_end_minute: body.quietHoursEndMinute ?? body.quiet_hours_end_minute ?? 360,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });
    if (error) throw error;

    return json({});
  } catch (error) {
    return errorResponse(error, "Could not update notification preferences");
  }
});
