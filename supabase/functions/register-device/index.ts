import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { providerSecretKey, requireUser } from "../_shared/client.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { supabase, user } = await requireUser(req);
    const body = await req.json();
    if (!body.token || !body.platform || !body.environment) {
      return json({ error: "Missing push token, platform, or environment" }, 422);
    }

    const tokenHash = await sha256(body.token);
    const { data: tokenSecretID, error: secretError } = await supabase.rpc("store_provider_secret", {
      p_user_id: user.id,
      p_payload: { token: body.token },
      p_key: providerSecretKey(),
    });
    if (secretError) throw secretError;

    const { error } = await supabase
      .from("device_push_tokens")
      .upsert({
        user_id: user.id,
        platform: body.platform,
        environment: body.environment,
        token_hash: tokenHash,
        token_secret_id: tokenSecretID,
        last_seen_at: new Date().toISOString(),
        invalidated_at: null,
      }, { onConflict: "token_hash" });
    if (error) throw error;

    return json({});
  } catch (error) {
    return errorResponse(error, "Could not register device");
  }
});

async function sha256(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
