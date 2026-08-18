import {
  defaultNotificationPreferences,
  deliveryBatches,
  deliveryDeepLink,
  isRejectedDeviceToken,
  isTransientAPNSStatus,
  notificationCopy,
  type NotificationEvent,
  type NotificationPreferencesRow,
  notificationSuppressionReason,
  parseNotificationPreferences,
  quietHoursEnd,
  quietSummaryDispatchIdentity,
  retryDelayMilliseconds,
  stableNotificationEventOrder,
} from "./notification-delivery.ts";

const event = (
  overrides: Partial<NotificationEvent> = {},
): NotificationEvent => ({
  id: "00000000-0000-4000-8000-000000000001",
  user_id: "00000000-0000-4000-8000-000000000010",
  linked_account_id: "00000000-0000-4000-8000-000000000020",
  subject_abbrev: "MAT",
  subject_name: "Mathematics",
  mark_text: "1",
  ...overrides,
});

function quietPreferences(
  overrides: Partial<NotificationPreferencesRow> = {},
): NotificationPreferencesRow {
  return {
    ...defaultNotificationPreferences,
    quiet_hours_enabled: true,
    ...overrides,
  };
}

Deno.test("legacy notification preferences gain the Prague time-zone default", () => {
  const result = parseNotificationPreferences({
    new_marks_enabled: false,
    quiet_hours_start_minute: 1200,
    quiet_hours_end_minute: 420,
  });
  assertEquals(result.quiet_hours_time_zone, "Europe/Prague");
  assertEquals(result.new_marks_enabled, false);
  assertEquals(result.quiet_hours_start_minute, 1200);
});

Deno.test("notification preference validation rejects invalid canonical values", () => {
  assertThrows(() =>
    parseNotificationPreferences({ quietHoursStartMinute: 1440 })
  );
  assertThrows(() =>
    parseNotificationPreferences({ quietHoursEndMinute: 1.5 })
  );
  assertThrows(() =>
    parseNotificationPreferences({ lockScreenDetail: "everything" })
  );
  assertThrows(() =>
    parseNotificationPreferences({
      quietHoursTimeZoneIdentifier: "Mars/Olympus",
    })
  );
  assertThrows(() => parseNotificationPreferences({ newMarksEnabled: "yes" }));
});

Deno.test("same-day quiet hours end at the configured local minute", () => {
  const result = quietHoursEnd(
    new Date("2026-07-18T20:30:00.000Z"),
    quietPreferences({
      quiet_hours_start_minute: 22 * 60,
      quiet_hours_end_minute: 23 * 60,
    }),
  );
  assertEquals(result?.toISOString(), "2026-07-18T21:00:00.000Z");
});

Deno.test("overnight quiet hours carry their end onto the next local day", () => {
  const result = quietHoursEnd(
    new Date("2026-07-18T21:15:00.000Z"),
    quietPreferences(),
  );
  assertEquals(result?.toISOString(), "2026-07-19T04:00:00.000Z");

  const outside = quietHoursEnd(
    new Date("2026-07-18T12:00:00.000Z"),
    quietPreferences(),
  );
  assertEquals(outside, null);
});

Deno.test("spring DST gaps deliver at the first representable wall minute", () => {
  const result = quietHoursEnd(
    new Date("2026-03-29T00:30:00.000Z"),
    quietPreferences({ quiet_hours_end_minute: 2 * 60 + 30 }),
  );
  assertEquals(result?.toISOString(), "2026-03-29T01:00:00.000Z");
});

Deno.test("fall DST folds choose the first future occurrence of the end time", () => {
  const result = quietHoursEnd(
    new Date("2026-10-25T00:15:00.000Z"),
    quietPreferences({ quiet_hours_end_minute: 2 * 60 + 30 }),
  );
  assertEquals(result?.toISOString(), "2026-10-25T00:30:00.000Z");
});

Deno.test("privacy copy never leaks details in private mode", () => {
  const single = notificationCopy([event()], "private_summary");
  assertEquals(single, { title: "New mark", body: "Open Gradey to view it." });

  const summary = notificationCopy([
    event(),
    event({ id: "2", mark_text: "5" }),
  ], "private_summary");
  assertEquals(summary, {
    title: "2 new marks",
    body: "Open Gradey to view the details.",
  });
});

Deno.test("global and per-account notification switches suppress delivery", () => {
  assertEquals(
    notificationSuppressionReason(
      { ...defaultNotificationPreferences, new_marks_enabled: false },
      { status: "active", notifications_enabled: true },
    ),
    "global_notifications_disabled",
  );
  assertEquals(
    notificationSuppressionReason(defaultNotificationPreferences, {
      status: "active",
      notifications_enabled: false,
    }),
    "linked_account_notifications_disabled",
  );
  assertEquals(
    notificationSuppressionReason(defaultNotificationPreferences, {
      status: "active",
      notifications_enabled: true,
    }),
    null,
  );
});

Deno.test("abbreviated and full privacy levels format the expected subject", () => {
  assertEquals(notificationCopy([event()], "mark_and_subject").body, "1 · MAT");
  assertEquals(
    notificationCopy([event()], "full_details").body,
    "1 · Mathematics",
  );
  assertEquals(
    notificationCopy([event({ subject_abbrev: null })], "mark_and_subject")
      .body,
    "1 · school",
  );

  const events = [
    event(),
    event({ id: "2", subject_abbrev: "ENG", subject_name: "English" }),
  ];
  assertEquals(
    notificationCopy(events, "mark_and_subject").body,
    "In MAT, ENG",
  );
  assertEquals(
    notificationCopy(events, "full_details").body,
    "In Mathematics, English",
  );
});

Deno.test("delivery helpers provide bounded retries, invalid-token handling, and marks deep links", () => {
  assertEquals(retryDelayMilliseconds(1), 60_000);
  assertEquals(retryDelayMilliseconds(5), 10_800_000);
  assertEquals(retryDelayMilliseconds(99), 10_800_000);
  assertEquals(isTransientAPNSStatus(429), true);
  assertEquals(isTransientAPNSStatus(503), true);
  assertEquals(isTransientAPNSStatus(400), false);
  assertEquals(isRejectedDeviceToken(410, "Unregistered"), true);
  assertEquals(isRejectedDeviceToken(400, "BadDeviceToken"), true);
  assertEquals(
    deliveryDeepLink([event()]),
    "gradey://marks?event=00000000-0000-4000-8000-000000000001",
  );
  assertEquals(
    deliveryDeepLink([event(), event({ id: "2" })]),
    "gradey://marks?summary=00000000-0000-4000-8000-000000000001",
  );
});

Deno.test("only quiet-hours events are summarized into a delivery batch", () => {
  const batches = deliveryBatches([
    {
      id: "quiet-1",
      quiet_hours_deferred_at: "2026-07-18T20:00:00Z",
      quiet_delivery_key: "2026-07-19T04:00:00Z",
    },
    {
      id: "quiet-2",
      quiet_hours_deferred_at: "2026-07-18T20:01:00Z",
      quiet_delivery_key: "2026-07-19T04:00:00Z",
    },
    { id: "immediate-1", quiet_hours_deferred_at: null },
    { id: "immediate-2" },
  ]);
  assertEquals(batches.map((batch) => batch.map((item) => item.id)), [
    ["quiet-1", "quiet-2"],
    ["immediate-1"],
    ["immediate-2"],
  ]);
});

Deno.test("quiet summaries never combine different delivery windows", () => {
  const batches = deliveryBatches([
    {
      id: "first-window-1",
      quiet_hours_deferred_at: "2026-07-18T20:00:00Z",
      quiet_delivery_key: "2026-07-19T04:00:00Z",
    },
    {
      id: "second-window",
      quiet_hours_deferred_at: "2026-07-19T20:00:00Z",
      quiet_delivery_key: "2026-07-20T04:00:00Z",
    },
    {
      id: "first-window-2",
      quiet_hours_deferred_at: "2026-07-18T20:01:00Z",
      quiet_delivery_key: "2026-07-19T04:00:00Z",
    },
    {
      id: "legacy-no-key",
      quiet_hours_deferred_at: "2026-07-18T20:02:00Z",
    },
  ]);
  assertEquals(batches.map((batch) => batch.map((item) => item.id)), [
    ["first-window-1", "first-window-2"],
    ["second-window"],
    ["legacy-no-key"],
  ]);
});

Deno.test("quiet summary identities are stable per window and device", async () => {
  const first = await quietSummaryDispatchIdentity(
    "2026-07-19T04:00:00.000Z",
    "00000000-0000-4000-8000-000000000099",
  );
  const retry = await quietSummaryDispatchIdentity(
    "2026-07-19T04:00:00.000Z",
    "00000000-0000-4000-8000-000000000099",
  );
  const otherDevice = await quietSummaryDispatchIdentity(
    "2026-07-19T04:00:00.000Z",
    "00000000-0000-4000-8000-000000000100",
  );
  const otherWindow = await quietSummaryDispatchIdentity(
    "2026-07-20T04:00:00.000Z",
    "00000000-0000-4000-8000-000000000099",
  );

  assertEquals(retry, first);
  assertEquals(otherDevice.apnsID === first.apnsID, false);
  assertEquals(otherDevice.collapseID === first.collapseID, false);
  assertEquals(otherWindow.apnsID === first.apnsID, false);
  assertEquals(otherWindow.collapseID === first.collapseID, false);
  assertEquals(
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(
        first.apnsID,
      ),
    true,
  );
  assertEquals(first.collapseID.length <= 64, true);
});

Deno.test("notification event ordering stabilizes summary payload seeds", () => {
  const second = event({ id: "00000000-0000-4000-8000-000000000002" });
  const first = event({ id: "00000000-0000-4000-8000-000000000001" });
  const ordered = stableNotificationEventOrder([second, first]);

  assertEquals(ordered.map((item) => item.id), [first.id, second.id]);
  assertEquals(
    deliveryDeepLink(ordered),
    "gradey://marks?summary=00000000-0000-4000-8000-000000000001",
  );
  assertEquals([second, first].map((item) => item.id), [second.id, first.id]);
});

function assertThrows(action: () => unknown) {
  let threw = false;
  try {
    action();
  } catch {
    threw = true;
  }
  if (!threw) throw new Error("Expected function to throw");
}

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
