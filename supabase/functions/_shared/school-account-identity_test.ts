import {
  canonicalSchoolBaseURL,
  canonicalSchoolProviderUserID,
  schoolAccountIdentityKey,
} from "./school-account-identity.ts";

Deno.test("EduPage identity prefers the active child represented by credentials", () => {
  const token = {
    eduPage: {
      userID: "parent-1",
      activeStudent: { id: "child-2" },
    },
  };
  assertEquals(
    canonicalSchoolProviderUserID("eduPage", "parent-1", token),
    "child-2",
  );
});

Deno.test("EduPage identity falls back through supplied user and session user", () => {
  assertEquals(
    canonicalSchoolProviderUserID("eduPage", " child-1 ", { eduPage: {} }),
    "child-1",
  );
  assertEquals(
    canonicalSchoolProviderUserID("eduPage", null, {
      eduPage: { userID: "parent-1" },
    }),
    "parent-1",
  );
});

Deno.test("school identity is stable across a trailing URL slash", async () => {
  const first = await schoolAccountIdentityKey(
    "eduPage",
    "https://school.edupage.org/",
    "child-1",
  );
  const second = await schoolAccountIdentityKey(
    "eduPage",
    "https://school.edupage.org",
    "child-1",
  );
  assertEquals(first, second);
});

Deno.test("school identity canonicalizes equivalent URL spelling", async () => {
  const first = await schoolAccountIdentityKey(
    "bakalari",
    "https://SCHOOL.example.cz//bakalari///",
    "student-1",
  );
  const second = await schoolAccountIdentityKey(
    "bakalari",
    "https://school.example.cz/bakalari",
    "student-1",
  );
  assertEquals(first, second);
});

Deno.test("canonical school URLs retain directory resolution semantics", () => {
  const baseURL = canonicalSchoolBaseURL(
    "https://school.example.cz//bakalari",
  );
  assertEquals(baseURL, "https://school.example.cz/bakalari/");
  assertEquals(
    new URL("api/3/marks", baseURL).toString(),
    "https://school.example.cz/bakalari/api/3/marks",
  );
});

Deno.test("different EduPage children retain independent links", async () => {
  const first = await schoolAccountIdentityKey(
    "eduPage",
    "https://school.edupage.org",
    "child-1",
  );
  const second = await schoolAccountIdentityKey(
    "eduPage",
    "https://school.edupage.org",
    "child-2",
  );
  assertNotEquals(first, second);
});

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}

function assertNotEquals(actual: unknown, expected: unknown) {
  if (actual === expected) {
    throw new Error(`Expected values to differ, received ${String(actual)}`);
  }
}
