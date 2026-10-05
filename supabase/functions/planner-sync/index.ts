import { requireUser } from "../_shared/client.ts";
import { handleOptions, json } from "../_shared/http.ts";
import { validatePlannerSync } from "../_shared/planner-sync.ts";

Deno.serve(async req => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const { supabase, user } = await requireUser(req);
    // Bound streamed bodies as well as requests with a declared content length.
    const reader = req.body?.getReader();
    if (!reader) return json({ error: "Missing body" }, 400);
    const chunks: Uint8Array[] = []; let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 512_000) { await reader.cancel(); return json({ error: "Request too large" }, 413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const body = validatePlannerSync(JSON.parse(new TextDecoder().decode(bytes)));
    const { data, error } = await supabase.rpc("planner_sync", { p_owner: user.id, p_changes: body.changes, p_cursor: body.cursor });
    if (error) return json({ error: "Planner sync could not complete" }, 409);
    const response = json(data);
    response.headers.set("Cache-Control", "no-store");
    return response;
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: "Invalid Planner sync request" }, 400);
  }
});
