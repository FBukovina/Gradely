import { serve } from "@hono/node-server";
import { resolve } from "node:path";
import { randomBytes } from "node:crypto";
import {
  createGradeyWebApp,
  createSupabaseMobileVerifier,
} from "./app.ts";
import { SqliteWebDeviceStore, SupabaseWebDeviceStore, type WebDeviceStore } from "./store.ts";

const port = Number(process.env.GRADEY_WEB_API_PORT ?? "8787");
const providerSecretKey =
  process.env.PROVIDER_SECRET_KEY ??
  `dev-ephemeral-${randomBytes(24).toString("hex")}`;

const supabaseUrl = process.env.SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY ?? "";
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

const store: WebDeviceStore =
  supabaseUrl && supabaseServiceRoleKey
    ? new SupabaseWebDeviceStore(supabaseUrl, supabaseServiceRoleKey, providerSecretKey)
    : new SqliteWebDeviceStore(
        process.env.GRADEY_WEB_SQLITE_PATH ??
          resolve(process.cwd(), ".gradey-data/dev-sessions.sqlite"),
        providerSecretKey,
      );

const verifyMobileToken =
  supabaseUrl && (supabaseAnonKey || supabaseServiceRoleKey)
    ? createSupabaseMobileVerifier(supabaseUrl, supabaseAnonKey || supabaseServiceRoleKey)
    : async () => null;

const app = createGradeyWebApp({
  store,
  csrfSecret: process.env.GRADEY_WEB_CSRF_SECRET ?? providerSecretKey,
  verifyMobileToken,
  allowedOrigins: ["http://localhost:5173", "http://127.0.0.1:5173"],
  forceSecureCookies: false,
});

serve({ fetch: app.fetch, port }, (info) => {
  console.log(
    `Gradey for Web BFF (dev) listening on http://127.0.0.1:${info.port}` +
      (supabaseUrl ? ` [Supabase: ${supabaseUrl}]` : " [Configure SUPABASE_URL & SUPABASE_ANON_KEY to verify mobile QR scans]"),
  );
});
