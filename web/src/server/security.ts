import {
  createCipheriv,
  createDecipheriv,
  createHash,
  hkdfSync,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

// MARK: - Cryptographic Tokens & Constant-Time Verification

export function generateOpaqueToken(byteLength = 32): string {
  return randomBytes(byteLength).toString("base64url");
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function safeCompareHex(firstHex: string, secondHex: string): boolean {
  if (
    typeof firstHex !== "string" ||
    typeof secondHex !== "string" ||
    firstHex.length === 0 ||
    firstHex.length !== secondHex.length
  ) {
    return false;
  }
  const a = Buffer.from(firstHex, "utf8");
  const b = Buffer.from(secondHex, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export function safeCompareTokenToHash(rawToken: string | undefined | null, expectedHexHash: string): boolean {
  if (!rawToken || typeof rawToken !== "string" || !expectedHexHash) return false;
  const computed = sha256Hex(rawToken);
  return safeCompareHex(computed, expectedHexHash);
}

// MARK: - AES-256-GCM Provider Secret Encryption (At-Rest Protection)

function deriveEncryptionKey(masterSecret: string): Buffer {
  if (!masterSecret || masterSecret.length < 32) {
    throw new Error("PROVIDER_SECRET_KEY must be set and at least 32 characters long");
  }
  return Buffer.from(
    hkdfSync(
      "sha256",
      Buffer.from(masterSecret, "utf8"),
      Buffer.from("gradey-web-provider-secret-salt-v1", "utf8"),
      Buffer.from("gradey-web-aes-256-gcm", "utf8"),
      32,
    ),
  );
}

export function encryptProviderSecret(
  payload: Record<string, unknown>,
  masterSecret: string,
): Buffer {
  const sanitized = sanitizeProviderSecret(payload);
  const key = deriveEncryptionKey(masterSecret);
  const iv = randomBytes(12); // 96-bit GCM nonce
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const plaintext = Buffer.from(JSON.stringify(sanitized), "utf8");
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();
  // Binary envelope: [version=1 (1B)] [iv (12B)] [tag (16B)] [ciphertext]
  return Buffer.concat([Buffer.from([1]), iv, authTag, encrypted]);
}

export function decryptProviderSecret(
  envelope: Buffer | Uint8Array,
  masterSecret: string,
): Record<string, unknown> {
  const buf = Buffer.from(envelope);
  if (buf.length < 1 + 12 + 16 || buf[0] !== 1) {
    throw new Error("Invalid encrypted secret envelope");
  }
  const key = deriveEncryptionKey(masterSecret);
  const iv = buf.subarray(1, 13);
  const authTag = buf.subarray(13, 29);
  const ciphertext = buf.subarray(29);
  const decipher = createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(authTag);
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  const parsed = JSON.parse(decrypted.toString("utf8"));
  return sanitizeProviderSecret(parsed);
}

// MARK: - Provider Secret Boundary (1:1 with supabase/functions/_shared/provider-secret.ts)

const TOKEN_FIELDS = [
  "provider",
  "baseURL",
  "accessToken",
  "refreshToken",
  "tokenType",
  "expiresAt",
  "pollingSessionEstablishedAt",
  "webSessionEstablishedAt",
];

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asRecords(value: unknown): Array<Record<string, unknown>> {
  return Array.isArray(value) ? value.map(asRecord) : [];
}

function pickStrings(
  source: Record<string, unknown>,
  keys: string[],
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof source[key] === "string") {
      out[key] = source[key];
    }
  }
  return out;
}

export function sanitizeProviderSecret(payload: unknown): Record<string, unknown> {
  const rec = asRecord(payload);
  const result = pickStrings(rec, TOKEN_FIELDS);
  if (rec.provider === "eduPage") {
    const eduPage = asRecord(rec.eduPage);
    const sanitizedEdu = pickStrings(eduPage, [
      "sessionID",
      "username",
      "gsecHash",
      "userID",
    ]);
    const studentFields = ["id", "fullName", "classID", "className"];
    if (eduPage.activeStudent != null) {
      sanitizedEdu.activeStudent = pickStrings(asRecord(eduPage.activeStudent), studentFields);
    }
    sanitizedEdu.linkedStudents = asRecords(eduPage.linkedStudents).map((s) =>
      pickStrings(s, studentFields),
    );
    sanitizedEdu.subjects = asRecords(eduPage.subjects).map((s) =>
      pickStrings(s, ["id", "name", "shortName"]),
    );
    result.eduPage = sanitizedEdu;
  }
  return result;
}

export function containsProviderPassword(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsProviderPassword);
  const rec = asRecord(value);
  return Object.entries(rec).some(
    ([key, child]) =>
      /password|passwd|passphrase/i.test(key) || containsProviderPassword(child),
  );
}

export function hasDedicatedBakalariWebSession(payload: unknown): boolean {
  const rec = asRecord(payload);
  return (
    typeof rec.accessToken === "string" &&
    rec.accessToken.trim().length > 0 &&
    typeof rec.refreshToken === "string" &&
    rec.refreshToken.trim().length > 0 &&
    typeof rec.webSessionEstablishedAt === "string" &&
    Number.isFinite(Date.parse(rec.webSessionEstablishedAt))
  );
}

// MARK: - SSRF-Safe School URL Validation (1:1 with supabase/functions/_shared/provider-url.ts)

const FORBIDDEN_HOST_SUFFIXES = [
  ".localhost",
  ".local",
  ".internal",
  ".home",
  ".lan",
  ".test",
  ".invalid",
];

function isForbiddenIPv4(hostname: string): boolean {
  const parts = hostname.split(".");
  if (parts.length !== 4 || parts.some((p) => !/^\d{1,3}$/.test(p))) return false;
  const octets = parts.map(Number);
  if (octets.some((o) => o < 0 || o > 255)) return true;
  const [first = 0, second = 0, third = 0] = octets;
  return (
    first === 0 ||
    first === 10 ||
    first === 127 ||
    first >= 224 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168) ||
    (first === 192 && second === 0 && (third === 0 || third === 2)) ||
    (first === 198 && (second === 18 || second === 19)) ||
    (first === 198 && second === 51 && third === 100) ||
    (first === 203 && second === 0 && third === 113)
  );
}

function isForbiddenIPv6(hostname: string): boolean {
  if (!hostname.includes(":")) return false;
  const normalized = hostname.toLowerCase();
  return (
    normalized === "::" ||
    normalized === "::1" ||
    normalized.startsWith("::ffff:") ||
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    /^fe[89ab]/.test(normalized) ||
    normalized.startsWith("fec") ||
    normalized.startsWith("fed") ||
    normalized.startsWith("fee") ||
    normalized.startsWith("fef")
  );
}

export function requireSafeProviderURL(value: unknown, label = "Provider URL"): string {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > 2048) {
    throw new Error(`${label} is invalid`);
  }
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new Error(`${label} is invalid`);
  }
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    (url.port && url.port !== "443") ||
    url.search ||
    url.hash
  ) {
    throw new Error(`${label} must be a credential-free HTTPS URL`);
  }
  const hostname = url.hostname
    .toLowerCase()
    .replace(/^\[/, "")
    .replace(/\]$/, "")
    .replace(/\.$/, "");
  if (
    !hostname ||
    hostname === "localhost" ||
    FORBIDDEN_HOST_SUFFIXES.some((s) => hostname.endsWith(s)) ||
    isForbiddenIPv4(hostname) ||
    isForbiddenIPv6(hostname) ||
    (!hostname.includes(".") && !hostname.includes(":"))
  ) {
    throw new Error(`${label} must use a public host`);
  }
  return url.toString();
}

export function providerURLsMatch(first: string, second: string): boolean {
  const a = new URL(first);
  const b = new URL(second);
  const norm = (p: string) => p.replace(/\/{2,}/g, "/").replace(/\/+$/, "") || "/";
  return a.origin === b.origin && norm(a.pathname) === norm(b.pathname);
}

// MARK: - User-Agent & Device Metadata Parser

export interface BrowserDeviceInfo {
  browserName: string;
  osName: string;
  deviceLabel: string;
  userAgentFamily: string;
}

export function parseBrowserDeviceMetadata(headers: Headers): BrowserDeviceInfo {
  const ua = (headers.get("user-agent") ?? "").slice(0, 512);
  const chUa = (headers.get("sec-ch-ua") ?? "").slice(0, 256);

  let browserName = "Web Browser";
  if (/Arc\//i.test(ua) || /"Arc"/i.test(chUa)) {
    browserName = "Arc";
  } else if (/Brave/i.test(ua) || /"Brave"/i.test(chUa)) {
    browserName = "Brave";
  } else if (/Edg\//i.test(ua) || /"Microsoft Edge"/i.test(chUa)) {
    browserName = "Edge";
  } else if (/OPR\//i.test(ua) || /Opera/i.test(ua)) {
    browserName = "Opera";
  } else if (/Firefox\//i.test(ua) || /Zen\//i.test(ua)) {
    browserName = /Zen\//i.test(ua) ? "Zen Browser" : "Firefox";
  } else if (/Chrome\//i.test(ua) || /CriOS\//i.test(ua)) {
    browserName = "Chrome";
  } else if (/Safari\//i.test(ua) && /Version\//i.test(ua)) {
    browserName = "Safari";
  }

  let osName = "Desktop";
  if (/iPad/i.test(ua)) {
    osName = "iPadOS";
  } else if (/iPhone|iPod/i.test(ua)) {
    osName = "iOS";
  } else if (/Macintosh|Mac OS X/i.test(ua)) {
    osName = "macOS";
  } else if (/Windows NT/i.test(ua)) {
    osName = "Windows";
  } else if (/CrOS/i.test(ua)) {
    osName = "ChromeOS";
  } else if (/Android/i.test(ua)) {
    osName = "Android";
  } else if (/Linux/i.test(ua)) {
    osName = "Linux";
  }

  const deviceLabel = `${browserName} · ${osName}`;
  const userAgentFamily = `${browserName.toLowerCase()}:${osName.toLowerCase()}`;
  return { browserName, osName, deviceLabel, userAgentFamily };
}

// MARK: - Cookie Handling (HttpOnly, Secure, SameSite=Lax, __Host- support)

export function parseCookies(cookieHeader: string | null): Record<string, string> {
  if (!cookieHeader) return {};
  const result: Record<string, string> = {};
  for (const pair of cookieHeader.split(";")) {
    const idx = pair.indexOf("=");
    if (idx <= 0) continue;
    const rawKey = pair.slice(0, idx).trim();
    const rawVal = pair.slice(idx + 1).trim();
    if (!rawKey) continue;
    try {
      result[rawKey] = decodeURIComponent(rawVal);
    } catch {
      result[rawKey] = rawVal;
    }
  }
  return result;
}

export interface CookieOptions {
  secure: boolean;
  maxAgeSeconds: number;
  path?: string;
  sameSite?: "Lax" | "Strict";
}

export function sessionCookieName(secure: boolean): string {
  return secure ? "__Host-gradey_session" : "gradey_session";
}

export function pairingCookieName(secure: boolean): string {
  return secure ? "__Host-gradey_qr" : "gradey_qr";
}

export function serializeHttpOnlyCookie(
  name: string,
  value: string,
  options: CookieOptions,
): string {
  // RFC 6265bis: __Host- cookies MUST have Secure, Path=/, and NO Domain attribute.
  const path = name.startsWith("__Host-") ? "/" : (options.path ?? "/");
  const parts = [
    `${name}=${encodeURIComponent(value)}`,
    `Path=${path}`,
    `Max-Age=${Math.max(0, Math.floor(options.maxAgeSeconds))}`,
    "HttpOnly",
    `SameSite=${options.sameSite ?? "Lax"}`,
  ];
  if (options.secure || name.startsWith("__Host-")) {
    parts.push("Secure");
  }
  return parts.join("; ");
}

export function isSecureRequest(req: Request, forceSecureCookies?: boolean): boolean {
  if (forceSecureCookies === true) return true;
  if (forceSecureCookies === false) return false;
  const proto = req.headers.get("x-forwarded-proto")?.split(",")[0]?.trim().toLowerCase();
  if (proto === "https") return true;
  try {
    return new URL(req.url).protocol === "https:";
  } catch {
    return process.env.NODE_ENV === "production";
  }
}

// MARK: - CSRF & Origin Verification

export function verifySameOriginRequest(req: Request, allowedOrigins: Set<string>): boolean {
  const secFetchSite = req.headers.get("sec-fetch-site")?.toLowerCase();
  if (secFetchSite && secFetchSite !== "same-origin" && secFetchSite !== "none") {
    return false;
  }

  const origin = req.headers.get("origin");
  if (origin) {
    if (allowedOrigins.size > 0 && allowedOrigins.has(origin)) return true;
    try {
      const reqUrl = new URL(req.url);
      const fwdHost = req.headers.get("x-forwarded-host") ?? req.headers.get("host");
      const fwdProto = req.headers.get("x-forwarded-proto")?.split(",")[0]?.trim() ?? reqUrl.protocol.replace(":", "");
      const expectedOrigin = fwdHost ? `${fwdProto}://${fwdHost}` : reqUrl.origin;
      return origin === expectedOrigin || origin === reqUrl.origin;
    } catch {
      return false;
    }
  }

  // Browser state-changing fetch calls from same-origin always send Origin or custom header.
  return req.headers.get("x-gradey-client") === "web-v1";
}

// MARK: - Sliding-Window Rate Limiter

export class SlidingWindowRateLimiter {
  private readonly buckets = new Map<string, number[]>();

  constructor(
    private readonly maxRequests: number,
    private readonly windowMs: number,
  ) {}

  allow(key: string, nowMs = Date.now()): boolean {
    const cutoff = nowMs - this.windowMs;
    const timestamps = (this.buckets.get(key) ?? []).filter((t) => t > cutoff);
    if (timestamps.length >= this.maxRequests) {
      this.buckets.set(key, timestamps);
      return false;
    }
    timestamps.push(nowMs);
    this.buckets.set(key, timestamps);
    if (this.buckets.size > 5000) {
      for (const [k, list] of this.buckets) {
        if (list.every((t) => t <= cutoff)) this.buckets.delete(k);
      }
    }
    return true;
  }
}

export function clientIpHash(req: Request): string {
  const raw =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip")?.trim() ??
    "local";
  return sha256Hex(`gradey-ip-salt-v1:${raw}`).slice(0, 32);
}
