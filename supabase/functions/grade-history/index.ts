import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const days = boundedDays(body.days);
    const linkedAccountID = await selectedLinkedAccountID(supabase, user.id, body.linked_account_id);
    if (!linkedAccountID) {
      return json({ events: [], recentNewMarkEvents: [] });
    }

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
    const [history, recentMarks] = await Promise.all([
      supabase
        .from("grade_history_events")
        .select("*")
        .eq("user_id", user.id)
        .eq("linked_account_id", linkedAccountID)
        .gte("captured_at", cutoff)
        .order("captured_at", { ascending: true })
        .limit(1000),
      supabase
        .from("new_mark_events")
        .select("*")
        .eq("user_id", user.id)
        .eq("linked_account_id", linkedAccountID)
        .order("created_at", { ascending: false })
        .limit(50),
    ]);

    if (history.error) throw history.error;
    if (recentMarks.error) throw recentMarks.error;

    return json({
      events: history.data ?? [],
      recentNewMarkEvents: recentMarks.data ?? [],
    });
  } catch (error) {
    return errorResponse(error, "Could not load grade history");
  }
});

function boundedDays(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) return 90;
  return Math.max(1, Math.min(400, Math.round(parsed)));
}

async function selectedLinkedAccountID(
  supabase: any,
  userID: string,
  requestedID: unknown,
) {
  if (typeof requestedID === "string" && requestedID.trim()) {
    const { data, error } = await supabase
      .from("linked_accounts")
      .select("id")
      .eq("id", requestedID)
      .eq("user_id", userID)
      .in("provider", ["bakalari", "eduPage"])
      .maybeSingle();
    if (error) throw error;
    return data?.id ?? null;
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("active_school_account_id")
    .eq("id", userID)
    .maybeSingle();
  if (profileError) throw profileError;
  if (profile?.active_school_account_id) return profile.active_school_account_id;

  const { data: account, error } = await supabase
    .from("linked_accounts")
    .select("id")
    .eq("user_id", userID)
    .in("provider", ["bakalari", "eduPage"])
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return account?.id ?? null;
}
