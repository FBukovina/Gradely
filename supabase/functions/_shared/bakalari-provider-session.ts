export class ProviderAuthenticationError extends Error {}

export interface BakalariCredentials {
  username: string;
  password: string;
}

export interface BakalariTokenResponse {
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  expiresIn: number;
}

const ACCESS_TOKEN_REFRESH_SKEW_MS = 5 * 60 * 1000;

export function bakalariCredentialsFromSecret(
  secret: Record<string, unknown>,
): BakalariCredentials | null {
  const nested = recordValue(secret.bakalari);
  const username = stringValue(nested?.username ?? secret.username);
  const password = stringValue(nested?.password ?? secret.password);
  if (!username || !password) return null;
  return { username, password };
}

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
  return !Number.isFinite(expiresAt) || expiresAt <= now + ACCESS_TOKEN_REFRESH_SKEW_MS;
}

export function bakalariSecretFromTokenResponse(
  secret: Record<string, unknown>,
  tokens: BakalariTokenResponse,
  now: Date,
): Record<string, unknown> {
  return {
    ...secret,
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    tokenType: tokens.tokenType || "Bearer",
    expiresAt: new Date(now.getTime() + tokens.expiresIn * 1000).toISOString(),
    pollingSessionEstablishedAt: now.toISOString(),
  };
}

export function parseBakalariTokenResponse(tokens: unknown): BakalariTokenResponse {
  const record = recordValue(tokens) ?? {};
  const accessToken = stringValue(record.access_token ?? record.accessToken);
  const refreshToken = stringValue(record.refresh_token ?? record.refreshToken);
  const tokenType = stringValue(record.token_type ?? record.tokenType) || "Bearer";
  const expiresIn = numberValue(record.expires_in ?? record.expiresIn);
  if (!accessToken || !refreshToken || expiresIn == null || expiresIn <= 0) {
    throw new Error("bakalari_refresh_response_invalid");
  }
  return { accessToken, refreshToken, tokenType, expiresIn };
}

/**
 * Picks a poller-owned Bakaláři token family.
 *
 * Prefer password login when credentials exist so the poller never redeems the
 * refresh-token chain the app and watch are using. Fall back to refresh, then
 * to login, when a previously established poller chain needs renewal.
 */
export async function resolveBakalariPollingSecret(
  secret: Record<string, unknown>,
  options: {
    now?: Date;
    forceRefresh?: boolean;
    login: (credentials: BakalariCredentials) => Promise<BakalariTokenResponse>;
    refresh: (refreshToken: string) => Promise<BakalariTokenResponse>;
  },
): Promise<{ secret: Record<string, unknown>; didMutate: boolean }> {
  const now = options.now ?? new Date();
  const credentials = bakalariCredentialsFromSecret(secret);
  const establish = shouldEstablishBakalariPollingSession(secret);
  const accessNeedsRefresh = shouldRefreshBakalariAccessToken(secret, now.getTime());
  const needsNewTokens = options.forceRefresh === true || establish || accessNeedsRefresh;

  if (!needsNewTokens) {
    return { secret, didMutate: false };
  }

  const apply = async (tokens: BakalariTokenResponse) => ({
    secret: bakalariSecretFromTokenResponse(secret, tokens, now),
    didMutate: true,
  });

  if (establish && credentials) {
    return await apply(await options.login(credentials));
  }

  const refreshToken = stringValue(secret.refreshToken);
  if (!refreshToken) {
    if (credentials) return await apply(await options.login(credentials));
    throw new ProviderAuthenticationError("bakalari_refresh_token_missing");
  }

  try {
    return await apply(await options.refresh(refreshToken));
  } catch (error) {
    if (isProviderAuthenticationError(error) && credentials) {
      return await apply(await options.login(credentials));
    }
    throw error;
  }
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
