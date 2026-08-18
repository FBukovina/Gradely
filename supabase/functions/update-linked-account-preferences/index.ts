import { toLinkedAccount } from "../_shared/account-settings.ts";
import { requireUser } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";

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
    if (typeof body.notificationsEnabled !== "boolean") {
      return json({ error: "notificationsEnabled must be a boolean" }, 422);
    }

    const { data, error } = await supabase
      .from("linked_accounts")
      .update({
        notifications_enabled: body.notificationsEnabled,
        updated_at: new Date().toISOString(),
      })
      .eq("id", body.id)
      .eq("user_id", user.id)
      .in("provider", ["bakalari", "eduPage"])
      .select("*")
      .maybeSingle();
    if (error) throw error;
    if (!data) return json({ error: "Linked school account not found" }, 404);

    await supabase.from("account_audit_logs").insert({
      user_id: user.id,
      linked_account_id: data.id,
      event_name: "updated_linked_account_notifications",
      metadata: { notificationsEnabled: data.notifications_enabled },
    });

    return json(toLinkedAccount(data));
  } catch (error) {
    return errorResponse(error, "Could not update linked account preferences");
  }
});
