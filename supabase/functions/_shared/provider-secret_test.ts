import {
  containsProviderPassword,
  hasDedicatedBakalariPollingSession,
  providerSecretForActivation,
  sanitizeProviderSecret,
} from "./provider-secret.ts";

Deno.test("Bakalari storage allowlist drops legacy credentials and unexpected containers", () => {
  const result = sanitizeProviderSecret({
    provider: "bakalari",
    baseURL: "https://school.example/",
    accessToken: "access",
    refreshToken: "refresh",
    username: "student",
    password: "secret",
    bakalari: { username: "student", password: "secret" },
    unexpected: { schoolPassword: "secret" },
    eduPage: { password: "secret" },
  });
  assertEquals(result, {
    provider: "bakalari",
    baseURL: "https://school.example/",
    accessToken: "access",
    refreshToken: "refresh",
  });
});

Deno.test("malformed fields cannot hide credential objects inside allowed scalar keys", () => {
  const result = sanitizeProviderSecret({
    provider: "bakalari",
    accessToken: { password: "secret" },
    refreshToken: ["secret"],
  });
  assertEquals(result, { provider: "bakalari" });
});

Deno.test("EduPage retains session and child context while stripping nested passwords", () => {
  const result = sanitizeProviderSecret({
    provider: "eduPage",
    accessToken: "session",
    eduPage: {
      sessionID: "session",
      username: "parent",
      gsecHash: "hash",
      userID: "user",
      password: "secret",
      activeStudent: {
        id: "child",
        fullName: "Test Child",
        password: "secret",
      },
      linkedStudents: [{
        id: "child",
        fullName: "Test Child",
        credentials: { password: "secret" },
      }],
      subjects: [{
        id: "math",
        name: "Math",
        shortName: "M",
        password: "secret",
      }],
    },
  });
  assertEquals(containsProviderPassword(result), false);
  const eduPage = result.eduPage as Record<string, unknown>;
  assertEquals(eduPage.sessionID, "session");
  assertEquals(eduPage.activeStudent, { id: "child", fullName: "Test Child" });
  assertEquals(eduPage.linkedStudents, [{
    id: "child",
    fullName: "Test Child",
  }]);
});

Deno.test("canteen sessions and APNs tokens survive the shared storage sanitizer", () => {
  const canteen = {
    provider: "stravaCZ",
    serviceURL: "https://canteen.example/",
    sessionID: "session",
    canteenNumber: "001",
    username: "student",
  };
  assertEquals(
    sanitizeProviderSecret({ ...canteen, password: "secret" }),
    canteen,
  );
  assertEquals(sanitizeProviderSecret({ token: "apns-device-token" }), {
    token: "apns-device-token",
  });
});

Deno.test("legacy request passwords are detected anywhere in the JSON body", () => {
  for (
    const value of [
      { password: "secret" },
      { token_payload: { bakalari: { password: "secret" } } },
      { data: [{ schoolPassword: "secret" }] },
      { Password: null },
    ]
  ) {
    assertEquals(containsProviderPassword(value), true);
  }
  assertEquals(
    containsProviderPassword({ accessToken: "a", refreshToken: "r" }),
    false,
  );
});

Deno.test("activation never returns a password or the poller refresh token", () => {
  assertEquals(
    providerSecretForActivation({
      provider: "bakalari",
      accessToken: "access",
      refreshToken: "cloud-refresh",
      pollingSessionEstablishedAt: "2026-09-07T12:00:00Z",
      bakalari: { password: "secret" },
    }),
    {
      provider: "bakalari",
      accessToken: "access",
    },
  );
});

Deno.test("only marked token families can be linked for background polling", () => {
  assertEquals(
    hasDedicatedBakalariPollingSession({ refreshToken: "r" }),
    false,
  );
  assertEquals(
    hasDedicatedBakalariPollingSession({
      refreshToken: "r",
      pollingSessionEstablishedAt: "invalid",
    }),
    false,
  );
  assertEquals(
    hasDedicatedBakalariPollingSession({
      refreshToken: "r",
      pollingSessionEstablishedAt: "2026-09-07T12:00:00Z",
    }),
    true,
  );
});

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("Assertion failed");
  }
}
