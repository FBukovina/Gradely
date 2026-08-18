export type SchoolProvider = "bakalari" | "eduPage";

type UnknownRecord = Record<string, unknown>;

/**
 * Returns the provider-side student identity represented by the credentials.
 * EduPage parent sessions must be scoped to the selected child; otherwise
 * linking two children from the same parent would incorrectly converge.
 */
export function canonicalSchoolProviderUserID(
  provider: SchoolProvider,
  suppliedProviderUserID: unknown,
  tokenPayload: UnknownRecord,
) {
  if (provider === "eduPage") {
    const eduPage = recordValue(tokenPayload.eduPage);
    const activeStudent = recordValue(eduPage?.activeStudent);
    return nonEmptyString(activeStudent?.id) ??
      nonEmptyString(suppliedProviderUserID) ??
      nonEmptyString(eduPage?.userID) ?? null;
  }

  return nonEmptyString(suppliedProviderUserID) ?? null;
}

/** Matches the canonicalization performed by school_account_identity_key(). */
export function canonicalSchoolBaseURL(baseURL: string) {
  const url = new URL(baseURL.trim());
  const normalizedPath = url.pathname.replace(/\/{2,}/g, "/");
  url.pathname = normalizedPath.endsWith("/")
    ? normalizedPath
    : `${normalizedPath}/`;
  return url.toString();
}

export async function schoolAccountIdentityKey(
  provider: SchoolProvider,
  baseURL: string,
  providerUserID: string | null,
) {
  const separator = String.fromCharCode(31);
  const material = [
    provider,
    canonicalSchoolBaseURL(baseURL).replace(/\/+$/, ""),
    providerUserID?.trim() || "__unknown__",
  ].join(separator);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(material),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function recordValue(value: unknown): UnknownRecord | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as UnknownRecord
    : null;
}

function nonEmptyString(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
