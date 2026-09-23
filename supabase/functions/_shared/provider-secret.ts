type Secret = Record<string, unknown>;

const tokenFields = [
  "provider",
  "baseURL",
  "accessToken",
  "refreshToken",
  "tokenType",
  "expiresAt",
  "pollingSessionEstablishedAt",
];

/** Only supported session fields may cross the encrypted-storage boundary. */
export function sanitizeProviderSecret(payload: Secret): Secret {
  // APNs device tokens use the same encrypted table and RPCs.
  if (payload.provider == null && typeof payload.token === "string") {
    return pickStrings(payload, ["token"]);
  }
  if (payload.provider === "stravaCZ") {
    return pickStrings(payload, [
      "provider",
      "serviceURL",
      "sessionID",
      "canteenNumber",
      "username",
    ]);
  }
  const result = pickStrings(payload, tokenFields);
  if (payload.provider === "eduPage") {
    const eduPage = record(payload.eduPage);
    const sanitized = pickStrings(eduPage, [
      "sessionID",
      "username",
      "gsecHash",
      "userID",
    ]);
    const studentFields = ["id", "fullName", "classID", "className"];
    if (eduPage.activeStudent != null) {
      sanitized.activeStudent = pickStrings(
        record(eduPage.activeStudent),
        studentFields,
      );
    }
    sanitized.linkedStudents = records(eduPage.linkedStudents).map((student) =>
      pickStrings(student, studentFields)
    );
    sanitized.subjects = records(eduPage.subjects).map((subject) =>
      pickStrings(subject, ["id", "name", "shortName"])
    );
    result.eduPage = sanitized;
  }
  return result;
}

/** Reject legacy uploads rather than silently accepting passwords and discarding them. */
export function containsProviderPassword(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsProviderPassword);
  return Object.entries(record(value)).some(([key, child]) =>
    /password|passwd|passphrase/i.test(key) || containsProviderPassword(child)
  );
}

export function hasDedicatedBakalariPollingSession(payload: Secret): boolean {
  return typeof payload.refreshToken === "string" &&
    payload.refreshToken.length > 0 &&
    typeof payload.pollingSessionEstablishedAt === "string" &&
    Number.isFinite(Date.parse(payload.pollingSessionEstablishedAt));
}

/** The rotating Bakaláři refresh token is exclusively owned by the cloud poller. */
export function providerSecretForActivation(payload: Secret): Secret {
  const result = sanitizeProviderSecret(payload);
  if (payload.provider === "bakalari") {
    delete result.refreshToken;
    delete result.pollingSessionEstablishedAt;
  }
  return result;
}

function pickStrings(value: Secret, keys: string[]): Secret {
  return Object.fromEntries(
    keys.flatMap((key) =>
      typeof value[key] === "string" ? [[key, value[key]]] : []
    ),
  );
}

function record(value: unknown): Secret {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Secret
    : {};
}

function records(value: unknown): Secret[] {
  return Array.isArray(value) ? value.map(record) : [];
}
