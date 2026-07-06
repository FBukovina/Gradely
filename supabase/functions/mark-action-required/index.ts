import { adminClient } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    assertServiceRole(req);
    const supabase = adminClient();
    const { linkedAccountID, reason } = await req.json();
    if (!linkedAccountID) return json({ error: "Missing linked account id" }, 422);

    const { error } = await supabase
      .from("linked_accounts")
      .update({
        status: "action_required",
        action_required_reason: reason || "Re-link this account in Gradey.",
        updated_at: new Date().toISOString(),
      })
      .eq("id", linkedAccountID);
    if (error) throw error;

    return json({});
  } catch (error) {
    return errorResponse(error, "Could not update linked account status");
  }
});

function assertServiceRole(req: Request) {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    throw new Response("Service role required", { status: 401 });
  }
}
