import { requireUser } from "../_shared/client.ts";
import { fetchAllOwnedRows, fetchWebAccountData } from "../_shared/account-export.ts";
import {
  corsHeaders,
  errorResponse,
  handleOptions,
  json,
} from "../_shared/http.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    const { supabase, user } = await requireUser(req);

    const [
      profile,
      preferences,
      linkedAccounts,
      markFingerprints,
      newMarkEvents,
      gradeHistory,
      auditLogs,
      webData,
    ] = await Promise.all([
      supabase
        .from("profiles")
        .select(
          "id,email,full_name,avatar_url,active_school_account_id,created_at,updated_at",
        )
        .eq("id", user.id)
        .maybeSingle(),
      supabase
        .from("notification_preferences")
        .select("*")
        .eq("user_id", user.id)
        .maybeSingle(),
      fetchAllOwnedRows(
        supabase,
        "linked_accounts",
        user.id,
        "id,user_id,provider,provider_user_id,base_url,display_name,school_name,canteen_name,status,notifications_enabled,last_polled_at,last_synced_at,next_poll_at,failure_count,action_required_reason,created_at,updated_at",
      ),
      fetchAllOwnedRows(
        supabase,
        "mark_fingerprints",
        user.id,
        "id,user_id,linked_account_id,provider,subject_id,provider_mark_id,fingerprint,source,first_seen_at",
      ),
      fetchAllOwnedRows(
        supabase,
        "new_mark_events",
        user.id,
        "id,user_id,linked_account_id,fingerprint_id,provider,subject_id,subject_abbrev,subject_name,mark_text,notification_title,notification_body,created_at,delivered_at,delivery_due_at,quiet_hours_deferred_at,quiet_delivery_key,delivery_targets_created_at,delivery_attempt_count,last_attempt_at,last_delivery_error,suppressed_at,suppression_reason",
      ),
      fetchAllOwnedRows(
        supabase,
        "grade_history_events",
        user.id,
        "id,user_id,linked_account_id,provider,subject_id,subject_abbrev,subject_name,average_value,mark_count,average_delta,mark_count_delta,event_type,captured_at,created_at",
      ),
      fetchAllOwnedRows(
        supabase,
        "account_audit_logs",
        user.id,
        "id,user_id,linked_account_id,event_name,metadata,created_at",
      ),
      fetchWebAccountData(supabase, user.id),
    ]);

    if (profile.error) throw profile.error;
    if (preferences.error) throw preferences.error;

    const payload = {
      schemaVersion: 3,
      exportedAt: new Date().toISOString(),
      profile: profile.data,
      linkedAccounts,
      notificationPreferences: preferences.data,
      markFingerprints,
      newMarkEvents,
      gradeHistoryEvents: gradeHistory,
      accountAuditLogs: auditLogs,
      ...webData,
    };

    return new Response(JSON.stringify(payload, null, 2), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json; charset=utf-8",
        "Content-Disposition": `attachment; filename="gradey-data-${
          new Date().toISOString().slice(0, 10)
        }.json"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    return errorResponse(error, "Could not export Gradey account data");
  }
});
