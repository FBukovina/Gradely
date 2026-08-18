import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    const { supabase, user } = await requireUser(req);
    const { id } = await req.json();
    if (typeof id !== "string" || id.length === 0) {
      return json({ error: "Missing linked account id" }, 422);
    }

    const { data, error } = await supabase.rpc("unlink_owned_account", {
      p_user_id: user.id,
      p_account_id: id,
    });
    if (error) throw error;
    if (!data) return json({ error: "Linked account not found" }, 404);

    return json({});
  } catch (error) {
    return errorResponse(error, "Could not unlink account");
  }
});
