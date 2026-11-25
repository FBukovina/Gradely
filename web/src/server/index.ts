import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import {
  createGradeyWebApp,
  createSupabaseMobileVerifier,
} from "./app.ts";
import { SqliteWebDeviceStore, SupabaseWebDeviceStore, type WebDeviceStore } from "./store.ts";

const isProduction = process.env.NODE_ENV === "production";
const port = Number(process.env.PORT ?? process.env.GRADEY_WEB_API_PORT ?? "8787");
const providerSecretKey = process.env.PROVIDER_SECRET_KEY ?? "";
const supabaseUrl = process.env.SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY ?? "";
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

if (!providerSecretKey || providerSecretKey.length < 32) {
  throw new Error(
    "PROVIDER_SECRET_KEY (>= 32 random characters) is required to run Gradey for Web.",
  );
}

if (!supabaseUrl || (!supabaseAnonKey && !supabaseServiceRoleKey)) {
  throw new Error(
    "SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY) are required to verify mobile Gradey ID sessions.",
  );
}

const store: WebDeviceStore = supabaseServiceRoleKey
  ? new SupabaseWebDeviceStore(supabaseUrl, supabaseServiceRoleKey, providerSecretKey)
  : new SqliteWebDeviceStore(
      process.env.GRADEY_WEB_SQLITE_PATH ?? resolve(process.cwd(), ".gradey-data/web-sessions.sqlite"),
      providerSecretKey,
    );

const allowedOrigins = (process.env.GRADEY_WEB_ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const app = createGradeyWebApp({
  store,
  csrfSecret: process.env.GRADEY_WEB_CSRF_SECRET ?? providerSecretKey,
  verifyMobileToken: createSupabaseMobileVerifier(
    supabaseUrl,
    supabaseAnonKey || supabaseServiceRoleKey,
  ),
  allowedOrigins,
  forceSecureCookies: isProduction ? true : undefined,
});

// Serve compiled frontend assets on the exact same origin in production.
const clientDist = resolve(process.cwd(), "dist/client");
if (existsSync(clientDist)) {
  app.use("/*", serveStatic({ root: "./dist/client" }));
  app.get("*", (c) => {
    if (c.req.path.startsWith("/api/")) {
      return c.json({ error: "Not found" }, 404);
    }
    const indexHtml = readFileSync(resolve(clientDist, "index.html"), "utf8");
    return c.html(indexHtml);
  });
}

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`Gradey for Web server listening on http://127.0.0.1:${info.port}`);
});
