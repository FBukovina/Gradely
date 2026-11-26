import { serve } from "@hono/node-server";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  createGradeyWebApp,
  createSupabaseMobileVerifier,
} from "./app.ts";
import {
  SqliteWebDeviceStore,
  SupabaseEdgeWebDeviceStore,
  SupabaseWebDeviceStore,
  type WebDeviceStore,
} from "./store.ts";

const envPath = resolve(process.cwd(), ".env");
if (existsSync(envPath) && typeof process.loadEnvFile === "function") {
  process.loadEnvFile(envPath);
}

const isProduction = process.env.NODE_ENV === "production";
const port = Number(process.env.PORT ?? process.env.GRADEY_WEB_API_PORT ?? "8787");
const providerSecretKey = process.env.PROVIDER_SECRET_KEY ?? "";
const gatewaySecret = process.env.WEB_BFF_GATEWAY_SECRET ?? "";
const csrfSecret =
  process.env.GRADEY_WEB_CSRF_SECRET ?? (gatewaySecret || providerSecretKey);
const supabaseUrl = process.env.SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY ?? "";
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

if (!csrfSecret || csrfSecret.length < 32) {
  throw new Error(
    "GRADEY_WEB_CSRF_SECRET, WEB_BFF_GATEWAY_SECRET, or PROVIDER_SECRET_KEY (>= 32 characters) is required.",
  );
}

if (!supabaseUrl || (!supabaseAnonKey && !supabaseServiceRoleKey)) {
  throw new Error(
    "SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY) are required to verify mobile Gradey ID sessions.",
  );
}

let store: WebDeviceStore;
let storeMode: string;

if (supabaseUrl && supabaseAnonKey && gatewaySecret.length >= 32) {
  store = new SupabaseEdgeWebDeviceStore(supabaseUrl, supabaseAnonKey, gatewaySecret);
  storeMode = "supabase-edge-gateway";
} else if (supabaseServiceRoleKey && providerSecretKey.length >= 32) {
  store = new SupabaseWebDeviceStore(supabaseUrl, supabaseServiceRoleKey, providerSecretKey);
  storeMode = "supabase-postgres";
} else if (providerSecretKey.length >= 32) {
  store = new SqliteWebDeviceStore(
    process.env.GRADEY_WEB_SQLITE_PATH ?? resolve(process.cwd(), ".gradey-data/web-sessions.sqlite"),
    providerSecretKey,
  );
  storeMode = "sqlite";
} else {
  throw new Error(
    "Configure WEB_BFF_GATEWAY_SECRET (recommended; keeps PROVIDER_SECRET_KEY inside Supabase) or PROVIDER_SECRET_KEY (>= 32 characters).",
  );
}

const allowedOrigins = (process.env.GRADEY_WEB_ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const app = createGradeyWebApp({
  store,
  csrfSecret,
  verifyMobileToken: createSupabaseMobileVerifier(
    supabaseUrl,
    supabaseAnonKey || supabaseServiceRoleKey,
  ),
  allowedOrigins,
  forceSecureCookies: isProduction ? true : undefined,
});

const clientDist = resolve(process.cwd(), "dist/client");
const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ttf": "font/ttf",
  ".txt": "text/plain; charset=utf-8",
};

if (existsSync(clientDist)) {
  app.get("*", (c) => {
    const pathname = new URL(c.req.url).pathname;
    if (pathname.startsWith("/api/")) {
      return c.json({ error: "Not found" }, 404);
    }
    const safeRel = pathname.replace(/^\/+/, "");
    if (safeRel && !safeRel.includes("..")) {
      const candidate = resolve(clientDist, safeRel);
      if (existsSync(candidate) && !candidate.endsWith("/")) {
        const dotIdx = candidate.lastIndexOf(".");
        const ext = dotIdx >= 0 ? candidate.slice(dotIdx) : "";
        const body = readFileSync(candidate);
        return new Response(body, {
          status: 200,
          headers: { "Content-Type": MIME[ext] ?? "application/octet-stream" },
        });
      }
    }
    const indexHtml = readFileSync(resolve(clientDist, "index.html"), "utf8");
    return c.html(indexHtml);
  });
}

serve({ fetch: app.fetch, port }, (info) => {
  console.log(
    `Gradey for Web listening on http://127.0.0.1:${info.port} [store=${storeMode}]`,
  );
});
