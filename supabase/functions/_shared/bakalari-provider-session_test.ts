import {
  bakalariSecretFromTokenResponse,
  parseBakalariTokenResponse,
  ProviderAuthenticationError,
  resolveBakalariPollingSecret,
  shouldRefreshBakalariAccessToken,
} from "./bakalari-provider-session.ts";

const now = new Date("2026-09-07T12:00:00.000Z");
const secret = {
  provider: "bakalari",
  baseURL: "https://school.example/",
  accessToken: "cloud-access",
  refreshToken: "cloud-refresh",
  expiresAt: "2026-09-07T13:00:00.000Z",
  pollingSessionEstablishedAt: "2026-09-07T11:00:00.000Z",
};
const tokens = {
  accessToken: "new-access",
  refreshToken: "new-refresh",
  tokenType: "Bearer",
  expiresIn: 3600,
};

Deno.test("fresh cloud access token is reused without a refresh", async () => {
  const resolved = await resolveBakalariPollingSecret(secret, {
    now,
    refresh: () => {
      throw new Error("Must not redeem a fresh token");
    },
  });
  assertEquals(resolved.didMutate, false);
  assertEquals(resolved.secret.accessToken, "cloud-access");
});

Deno.test("expiry and forced renewal redeem only the dedicated cloud token", async () => {
  for (const forceRefresh of [false, true]) {
    let received = "";
    const resolved = await resolveBakalariPollingSecret({
      ...secret,
      expiresAt: now.toISOString(),
    }, {
      now,
      forceRefresh,
      refresh: (token) => {
        received = token;
        return Promise.resolve(tokens);
      },
    });
    assertEquals(received, "cloud-refresh");
    assertEquals(resolved.didMutate, true);
    assertEquals(resolved.secret.refreshToken, "new-refresh");
  }
});

Deno.test("a forced refresh also renews a token before its advertised expiry", async () => {
  const resolved = await resolveBakalariPollingSecret(secret, {
    now,
    forceRefresh: true,
    refresh: () => Promise.resolve(tokens),
  });
  assertEquals(resolved.didMutate, true);
});

Deno.test("rejected refresh requires reconnect even if legacy passwords are present", async () => {
  const rejected = new ProviderAuthenticationError("bakalari_refresh_rejected");
  await expectError(() =>
    resolveBakalariPollingSecret({
      ...secret,
      expiresAt: now.toISOString(),
      bakalari: {
        username: "test-student",
        password: "legacy-school-password",
      },
    }, {
      now,
      refresh: () => {
        throw rejected;
      },
    }), rejected);
});

Deno.test("transient refresh failures stay transient", async () => {
  const networkError = new Error("network unavailable");
  await expectError(() =>
    resolveBakalariPollingSecret(secret, {
      now,
      forceRefresh: true,
      refresh: () => {
        throw networkError;
      },
    }), networkError);
});

Deno.test("unestablished legacy tokens are never redeemed from the device family", async () => {
  try {
    await resolveBakalariPollingSecret({
      ...secret,
      pollingSessionEstablishedAt: undefined,
    }, {
      now,
      refresh: () => {
        throw new Error("Device token must not be used");
      },
    });
    throw new Error("Expected a reconnect");
  } catch (error) {
    if (!(error instanceof ProviderAuthenticationError)) throw error;
  }
});

Deno.test("missing refresh token requires reconnect", async () => {
  try {
    await resolveBakalariPollingSecret({
      ...secret,
      refreshToken: "",
      expiresAt: now.toISOString(),
    }, {
      now,
      refresh: () => {
        throw new Error("Missing token must not be redeemed");
      },
    });
    throw new Error("Expected a reconnect");
  } catch (error) {
    if (!(error instanceof ProviderAuthenticationError)) throw error;
  }
});

Deno.test("fresh and renewed runtime secrets discard all legacy credentials", async () => {
  const legacy = {
    ...secret,
    password: "top-secret",
    bakalari: { username: "test-student", password: "nested-secret" },
  };
  const resolved = await resolveBakalariPollingSecret(legacy, {
    now,
    refresh: () => {
      throw new Error("Token remains valid");
    },
  });
  for (
    const value of [
      resolved.secret,
      bakalariSecretFromTokenResponse(legacy, tokens, now),
    ]
  ) {
    assertEquals(value.password, undefined);
    assertEquals(value.bakalari, undefined);
  }
});

Deno.test("access tokens are refreshed within the expiry skew or if expiry is invalid", () => {
  assertEquals(shouldRefreshBakalariAccessToken(secret, now.getTime()), false);
  assertEquals(
    shouldRefreshBakalariAccessToken(
      { expiresAt: "2026-09-07T12:04:00Z" },
      now.getTime(),
    ),
    true,
  );
  assertEquals(
    shouldRefreshBakalariAccessToken({ expiresAt: "invalid" }, now.getTime()),
    true,
  );
});

Deno.test("token parser accepts OAuth fields and rejects unusable responses", () => {
  assertEquals(
    parseBakalariTokenResponse({
      access_token: "a",
      refresh_token: "r",
      expires_in: 3600,
    }),
    {
      accessToken: "a",
      refreshToken: "r",
      tokenType: "Bearer",
      expiresIn: 3600,
    },
  );
  for (
    const input of [{}, {
      access_token: "a",
      refresh_token: "r",
      expires_in: -1,
    }]
  ) {
    let threw = false;
    try {
      parseBakalariTokenResponse(input);
    } catch {
      threw = true;
    }
    assertEquals(threw, true);
  }
});

async function expectError(operation: () => Promise<unknown>, expected: Error) {
  try {
    await operation();
  } catch (error) {
    if (error === expected) return;
    throw error;
  }
  throw new Error("Expected operation to reject");
}
function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("Assertion failed");
  }
}
