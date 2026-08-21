import {
  bakalariCredentialsFromSecret,
  bakalariSecretFromTokenResponse,
  parseBakalariTokenResponse,
  ProviderAuthenticationError,
  resolveBakalariPollingSecret,
  shouldEstablishBakalariPollingSession,
  shouldRefreshBakalariAccessToken,
} from "./bakalari-provider-session.ts";

Deno.test("bakalari credentials are read from the nested payload", () => {
  const credentials = bakalariCredentialsFromSecret({
    accessToken: "access",
    bakalari: { username: "filip", password: "secret" },
  });
  assertEquals(credentials, { username: "filip", password: "secret" });
});

Deno.test("eduPage-style secrets do not look like bakalari credentials", () => {
  const credentials = bakalariCredentialsFromSecret({
    eduPage: { username: "student", gsecHash: "hash" },
  });
  if (credentials != null) {
    throw new Error("Expected EduPage secrets not to expose Bakalari credentials");
  }
});

Deno.test("a missing pollingSessionEstablishedAt still needs a poller-owned family", () => {
  if (!shouldEstablishBakalariPollingSession({ accessToken: "access" })) {
    throw new Error("Expected a new secret to establish a polling session");
  }
  if (shouldEstablishBakalariPollingSession({ pollingSessionEstablishedAt: "2026-08-21T10:00:00.000Z" })) {
    throw new Error("Expected an established polling session to be reused");
  }
});

Deno.test("access tokens are refreshed only near expiry", () => {
  const now = Date.parse("2026-08-21T12:00:00.000Z");
  if (
    shouldRefreshBakalariAccessToken({
      expiresAt: "2026-08-21T13:00:00.000Z",
    }, now)
  ) {
    throw new Error("Expected a fresh access token to be reused");
  }
  if (
    !shouldRefreshBakalariAccessToken({
      expiresAt: "2026-08-21T12:04:00.000Z",
    }, now)
  ) {
    throw new Error("Expected an almost-expired access token to refresh");
  }
});

Deno.test("first poll with credentials logs in instead of redeeming the app refresh token", async () => {
  const calls: string[] = [];
  const resolved = await resolveBakalariPollingSecret({
    accessToken: "app-access",
    refreshToken: "app-refresh",
    bakalari: { username: "filip", password: "secret" },
  }, {
    now: new Date("2026-08-21T12:00:00.000Z"),
    login: async () => {
      calls.push("login");
      return {
        accessToken: "poller-access",
        refreshToken: "poller-refresh",
        tokenType: "Bearer",
        expiresIn: 3600,
      };
    },
    refresh: async () => {
      calls.push("refresh");
      throw new Error("refresh should not run when credentials can mint a new family");
    },
  });

  assertEquals(calls, ["login"]);
  assertEquals(resolved.didMutate, true);
  assertEquals(resolved.secret.accessToken, "poller-access");
  assertEquals(resolved.secret.refreshToken, "poller-refresh");
  assertEquals(resolved.secret.pollingSessionEstablishedAt, "2026-08-21T12:00:00.000Z");
});

Deno.test("established poller chain refreshes and falls back to password login", async () => {
  const calls: string[] = [];
  const resolved = await resolveBakalariPollingSecret({
    accessToken: "old-access",
    refreshToken: "old-refresh",
    expiresAt: "2026-08-21T12:00:00.000Z",
    pollingSessionEstablishedAt: "2026-08-21T10:00:00.000Z",
    bakalari: { username: "filip", password: "secret" },
  }, {
    now: new Date("2026-08-21T12:00:00.000Z"),
    login: async () => {
      calls.push("login");
      return {
        accessToken: "login-access",
        refreshToken: "login-refresh",
        tokenType: "Bearer",
        expiresIn: 3600,
      };
    },
    refresh: async () => {
      calls.push("refresh");
      throw new ProviderAuthenticationError("bakalari_refresh_rejected");
    },
  });

  assertEquals(calls, ["refresh", "login"]);
  assertEquals(resolved.secret.accessToken, "login-access");
});

Deno.test("legacy secrets without credentials still refresh to split the chain", async () => {
  const calls: string[] = [];
  const resolved = await resolveBakalariPollingSecret({
    accessToken: "app-access",
    refreshToken: "app-refresh",
    expiresAt: "2026-08-21T18:00:00.000Z",
  }, {
    now: new Date("2026-08-21T12:00:00.000Z"),
    login: async () => {
      calls.push("login");
      throw new Error("login should not run without credentials");
    },
    refresh: async (refreshToken) => {
      calls.push(`refresh:${refreshToken}`);
      return {
        accessToken: "split-access",
        refreshToken: "split-refresh",
        tokenType: "Bearer",
        expiresIn: 3600,
      };
    },
  });

  assertEquals(calls, ["refresh:app-refresh"]);
  assertEquals(resolved.secret.refreshToken, "split-refresh");
});

Deno.test("valid established access tokens are reused", async () => {
  const resolved = await resolveBakalariPollingSecret({
    accessToken: "poller-access",
    refreshToken: "poller-refresh",
    expiresAt: "2026-08-21T18:00:00.000Z",
    pollingSessionEstablishedAt: "2026-08-21T10:00:00.000Z",
    bakalari: { username: "filip", password: "secret" },
  }, {
    now: new Date("2026-08-21T12:00:00.000Z"),
    login: async () => {
      throw new Error("login should not run for a valid poller session");
    },
    refresh: async () => {
      throw new Error("refresh should not run for a valid poller session");
    },
  });

  assertEquals(resolved.didMutate, false);
  assertEquals(resolved.secret.accessToken, "poller-access");
});

Deno.test("token responses keep credentials already stored on the secret", () => {
  const updated = bakalariSecretFromTokenResponse(
    {
      bakalari: { username: "filip", password: "secret" },
      refreshToken: "old",
    },
    {
      accessToken: "new-access",
      refreshToken: "new-refresh",
      tokenType: "Bearer",
      expiresIn: 120,
    },
    new Date("2026-08-21T12:00:00.000Z"),
  );

  assertEquals(updated.bakalari, { username: "filip", password: "secret" });
  assertEquals(updated.expiresAt, "2026-08-21T12:02:00.000Z");
});

Deno.test("token parser accepts snake_case OAuth fields", () => {
  const tokens = parseBakalariTokenResponse({
    access_token: "a",
    refresh_token: "r",
    token_type: "Bearer",
    expires_in: 3600,
  });
  assertEquals(tokens.accessToken, "a");
  assertEquals(tokens.refreshToken, "r");
  assertEquals(tokens.expiresIn, 3600);
});

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`,
    );
  }
}
