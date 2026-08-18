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
    const { error } = await supabase.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({});
  } catch (error) {
    return errorResponse(error, "Could not delete Gradey account");
  }
});
