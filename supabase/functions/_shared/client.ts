import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service role configuration");
  return createClient(url, key, { auth: { persistSession: false } });
}

export async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Response("Missing Authorization header", { status: 401 });

  const supabase = adminClient();
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data.user) throw new Response("Invalid Gradey ID session", { status: 401 });
  return { supabase, user: data.user };
}

export function providerSecretKey() {
  const key = Deno.env.get("PROVIDER_SECRET_KEY");
  if (!key) throw new Error("Missing PROVIDER_SECRET_KEY");
  return key;
}
