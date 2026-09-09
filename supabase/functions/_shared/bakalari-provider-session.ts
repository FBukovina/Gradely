import { sanitizeProviderSecret } from "./provider-secret.ts";

export class ProviderAuthenticationError extends Error {}

export interface BakalariTokenResponse {
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  expiresIn: number;
}

const ACCESS_TOKEN_REFRESH_SKEW_MS = 5 * 60 * 1000;

export function shouldEstablishBakalariPollingSession(
  secret: Record<string, unknown>,
) {
  return stringValue(secret.pollingSessionEstablishedAt).length === 0;
}

export function shouldRefreshBakalariAccessToken(
  secret: Record<string, unknown>,
  now = Date.now(),
) {
  const expiresAt = Date.parse(String(secret.expiresAt ?? ""));
  return !Number.isFinite(expiresAt) ||
    expiresAt <= now + ACCESS_TOKEN_REFRESH_SKEW_MS;
}

export function bakalariSecretFromTokenResponse(
  secret: Record<string, unknown>,
  tokens: BakalariTokenResponse,
  now: Date,
): Record<string, unknown> {
  return {
    ...sanitizeProviderSecret(secret),
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    tokenType: tokens.tokenType || "Bearer",
    expiresAt: new Date(now.getTime() + tokens.expiresIn * 1000).toISOString(),
    pollingSessionEstablishedAt: now.toISOString(),
  };
}

export function parseBakalariTokenResponse(
  tokens: unknown,
): BakalariTokenResponse {
  const record = recordValue(tokens) ?? {};
  const accessToken = stringValue(record.access_token ?? record.accessToken);
  const refreshToken = stringValue(record.refresh_token ?? record.refreshToken);
  const tokenType = stringValue(record.token_type ?? record.tokenType) ||
    "Bearer";
  const expiresIn = numberValue(record.expires_in ?? record.expiresIn);
  if (!accessToken || !refreshToken || expiresIn == null || expiresIn <= 0) {
    throw new Error("bakalari_refresh_response_invalid");
  }
  return { accessToken, refreshToken, tokenType, expiresIn };
}

/**
 * Picks a poller-owned Bakaláři token family.
 *
 * The app establishes a separate session directly with the school before linking.
 * Rejected cloud tokens require an on-device reconnect; passwords never reach here.
 */
export async function resolveBakalariPollingSecret(
  secret: Record<string, unknown>,
  options: {
    now?: Date;
    forceRefresh?: boolean;
    refresh: (refreshToken: string) => Promise<BakalariTokenResponse>;
  },
): Promise<{ secret: Record<string, unknown>; didMutate: boolean }> {
  const now = options.now ?? new Date();
  secret = sanitizeProviderSecret(secret);
  const establish = shouldEstablishBakalariPollingSession(secret);
  const accessNeedsRefresh = shouldRefreshBakalariAccessToken(
    secret,
    now.getTime(),
  );
  // Legacy unestablished secrets may share the device's rotating token. Do not
  // redeem that token: reconnect from an updated client to create a separate one.
  if (establish) {
    throw new ProviderAuthenticationError(
      "bakalari_polling_reconnect_required",
    );
  }
  const needsNewTokens = options.forceRefresh === true || accessNeedsRefresh;

  if (!needsNewTokens) {
    return { secret, didMutate: false };
  }

  const apply = async (tokens: BakalariTokenResponse) => ({
    secret: bakalariSecretFromTokenResponse(secret, tokens, now),
    didMutate: true,
  });

  const refreshToken = stringValue(secret.refreshToken);
  if (!refreshToken) {
    throw new ProviderAuthenticationError("bakalari_refresh_token_missing");
  }

  return await apply(await options.refresh(refreshToken));
}

export function isProviderAuthenticationError(error: unknown) {
  return error instanceof ProviderAuthenticationError ||
    (error instanceof Error && error.message === "edupage_auth_failed");
}

function recordValue(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}

function numberValue(value: unknown) {
  if (typeof value === "number") return value;
  const normalized = stringValue(value).replace(",", ".");
  if (!normalized) return null;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
}
