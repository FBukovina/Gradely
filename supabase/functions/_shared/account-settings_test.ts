import {
  toLinkedAccount,
  toNotificationPreferences,
} from "./account-settings.ts";

Deno.test("linked account settings expose canonical fields without provider credentials", () => {
  const account = toLinkedAccount({
    id: "account-id",
    provider: "bakalari",
    provider_user_id: "provider-user",
    display_name: "Student",
    school_name: "School",
    status: "active",
    notifications_enabled: true,
    secret_id: "must-not-leak",
    base_url: "https://school.example/",
  });

  assertEquals(account, {
    id: "account-id",
    provider: "bakalari",
    providerUserID: "provider-user",
    displayName: "Student",
    schoolName: "School",
    canteenName: undefined,
    status: "active",
    notificationsEnabled: true,
    lastPolledAt: undefined,
    lastSyncedAt: undefined,
    actionRequiredReason: undefined,
  });
  if ("secretID" in account || "secret_id" in account || "baseURL" in account) {
    throw new Error(
      "Provider credential metadata leaked from the canonical account response",
    );
  }
});

Deno.test("canonical notification settings supply legacy defaults", () => {
  assertEquals(toNotificationPreferences({ new_marks_enabled: false }), {
    new_marks_enabled: false,
    lock_screen_detail: "mark_and_subject",
    quiet_hours_enabled: false,
    quiet_hours_start_minute: 1320,
    quiet_hours_end_minute: 360,
    quiet_hours_time_zone: "Europe/Prague",
    updated_at: null,
  });
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
