import { relinkSchoolAccountPatch } from "./relink-school-account.ts";

Deno.test("school reconnect updates the owned row in place and clears failure state", () => {
  const patch = relinkSchoolAccountPatch(
    {
      id: "existing-account-id",
      provider_user_id: "old-provider-user",
      display_name: "Existing student",
      school_name: "Existing school",
    },
    {
      provider_user_id: "refreshed-provider-user",
      display_name: "Refreshed student",
    },
    "new-secret-id",
    "https://school.example/",
    new Date("2026-07-18T12:00:00.000Z"),
  );

  assertEquals(patch, {
    provider_user_id: "refreshed-provider-user",
    base_url: "https://school.example/",
    display_name: "Refreshed student",
    school_name: "Existing school",
    status: "active",
    secret_id: "new-secret-id",
    failure_count: 0,
    action_required_reason: null,
    last_synced_at: "2026-07-18T12:00:00.000Z",
    next_poll_at: "2026-07-18T12:15:00.000Z",
    updated_at: "2026-07-18T12:00:00.000Z",
  });

  if ("id" in patch || "user_id" in patch || "provider" in patch) {
    throw new Error(
      "Reconnect patch must not replace ownership or row identity",
    );
  }
});

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
