import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const { id } = await req.json();
    if (!id) return json({ error: "Missing linked account id" }, 422);

    const { error } = await supabase
      .from("linked_accounts")
      .delete()
      .eq("id", id)
      .eq("user_id", user.id);
    if (error) throw error;

    await supabase.from("account_audit_logs").insert({
      user_id: user.id,
      linked_account_id: id,
      event_name: "unlinked_account",
      metadata: {},
    });

    return json({});
  } catch (error) {
    return errorResponse(error, "Could not unlink account");
  }
});
