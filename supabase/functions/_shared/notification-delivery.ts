export const DEFAULT_QUIET_HOURS_TIME_ZONE = "Europe/Prague";

export const LOCK_SCREEN_DETAILS = [
  "private_summary",
  "mark_and_subject",
  "full_details",
] as const;

export type LockScreenDetail = typeof LOCK_SCREEN_DETAILS[number];

export interface NotificationPreferencesRow {
  new_marks_enabled: boolean;
  lock_screen_detail: LockScreenDetail;
  quiet_hours_enabled: boolean;
  quiet_hours_start_minute: number;
  quiet_hours_end_minute: number;
  quiet_hours_time_zone: string;
}

export interface NotificationEvent {
  id: string;
  user_id: string;
  linked_account_id: string;
  subject_abbrev?: string | null;
  subject_name?: string | null;
  mark_text: string;
}

export interface NotificationCopy {
  title: string;
  body: string;
}

export interface APNSDispatchIdentity {
  apnsID: string;
  collapseID: string;
}

export interface LinkedAccountAlertState {
  status: string;
  notifications_enabled: boolean;
}

export const defaultNotificationPreferences: NotificationPreferencesRow = {
  new_marks_enabled: true,
  lock_screen_detail: "mark_and_subject",
  quiet_hours_enabled: false,
  quiet_hours_start_minute: 22 * 60,
  quiet_hours_end_minute: 6 * 60,
  quiet_hours_time_zone: DEFAULT_QUIET_HOURS_TIME_ZONE,
};

export function parseNotificationPreferences(
  input: Record<string, unknown>,
  current: Partial<NotificationPreferencesRow> = defaultNotificationPreferences,
): NotificationPreferencesRow {
  const base = { ...defaultNotificationPreferences, ...current };
  const newMarksEnabled = booleanField(
    input,
    "newMarksEnabled",
    "new_marks_enabled",
    base.new_marks_enabled,
  );
  const quietHoursEnabled = booleanField(
    input,
    "quietHoursEnabled",
    "quiet_hours_enabled",
    base.quiet_hours_enabled,
  );
  const startMinute = minuteField(
    input,
    "quietHoursStartMinute",
    "quiet_hours_start_minute",
    base.quiet_hours_start_minute,
  );
  const endMinute = minuteField(
    input,
    "quietHoursEndMinute",
    "quiet_hours_end_minute",
    base.quiet_hours_end_minute,
  );
  const detailValue =
    aliasedField(input, "lockScreenDetail", "lock_screen_detail") ??
      base.lock_screen_detail;
  if (
    typeof detailValue !== "string" ||
    !LOCK_SCREEN_DETAILS.includes(detailValue as LockScreenDetail)
  ) {
    throw new Error("Lock-screen detail is invalid");
  }

  const timeZoneValue = aliasedField(
    input,
    "quietHoursTimeZoneIdentifier",
    "quiet_hours_time_zone",
  ) ??
    aliasedField(
      input,
      "quietHoursTimeZone",
      "quietHoursTimeZoneIdentifier",
    ) ??
    base.quiet_hours_time_zone;
  if (typeof timeZoneValue !== "string" || !isValidTimeZone(timeZoneValue)) {
    throw new Error("Quiet-hours time zone is invalid");
  }

  return {
    new_marks_enabled: newMarksEnabled,
    lock_screen_detail: detailValue as LockScreenDetail,
    quiet_hours_enabled: quietHoursEnabled,
    quiet_hours_start_minute: startMinute,
    quiet_hours_end_minute: endMinute,
    quiet_hours_time_zone: timeZoneValue,
  };
}

export function isValidTimeZone(value: string) {
  const containsControlCharacter = Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint < 32 || codePoint === 127;
  });
  if (value.length < 1 || value.length > 128 || containsControlCharacter) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format(new Date(0));
    return true;
  } catch {
    return false;
  }
}

export function notificationSuppressionReason(
  preferences: NotificationPreferencesRow,
  account?: LinkedAccountAlertState | null,
) {
  if (!preferences.new_marks_enabled) return "global_notifications_disabled";
  if (
    !account || account.status !== "active" || !account.notifications_enabled
  ) {
    return "linked_account_notifications_disabled";
  }
  return null;
}

/**
 * Returns the next instant at which an active quiet-hours window ends.
 * `null` means the supplied instant is not currently inside quiet hours.
 */
export function quietHoursEnd(
  instant: Date,
  preferences: NotificationPreferencesRow,
): Date | null {
  if (!preferences.quiet_hours_enabled) return null;

  const start = preferences.quiet_hours_start_minute;
  const end = preferences.quiet_hours_end_minute;
  if (start === end) return null;

  const timeZone = isValidTimeZone(preferences.quiet_hours_time_zone)
    ? preferences.quiet_hours_time_zone
    : DEFAULT_QUIET_HOURS_TIME_ZONE;
  const local = zonedParts(instant, timeZone);
  const minute = local.hour * 60 + local.minute;

  let targetDate = { year: local.year, month: local.month, day: local.day };
  if (start < end) {
    if (minute < start || minute >= end) return null;
  } else {
    if (minute >= start) {
      targetDate = addLocalDays(targetDate, 1);
    } else if (minute >= end) {
      return null;
    }
  }

  return wallTimeToInstant(
    {
      ...targetDate,
      hour: Math.floor(end / 60),
      minute: end % 60,
    },
    timeZone,
    instant,
  );
}

export function notificationCopy(
  events: NotificationEvent[],
  detail: LockScreenDetail,
): NotificationCopy {
  if (events.length === 0) {
    throw new Error("At least one notification event is required");
  }

  if (events.length === 1) {
    const event = events[0];
    if (detail === "private_summary") {
      return { title: "New mark", body: "Open Gradey to view it." };
    }

    const subject = detail === "full_details"
      ? event.subject_name || event.subject_abbrev || "school"
      : event.subject_abbrev || "school";
    return {
      title: "New mark",
      body: `${clipped(event.mark_text, 32)} · ${clipped(subject, 96)}`,
    };
  }

  const title = `${events.length} new marks`;
  if (detail === "private_summary") {
    return { title, body: "Open Gradey to view the details." };
  }

  const subjects = uniqueSubjects(events, detail === "full_details");
  if (subjects.length === 0) {
    return { title, body: "Open Gradey to view the details." };
  }
  if (subjects.length === 1) return { title, body: `In ${subjects[0]}` };

  const visible = subjects.slice(0, 2).join(", ");
  const remainder = subjects.length - 2;
  return {
    title,
    body: remainder > 0
      ? `In ${visible} and ${remainder} more`
      : `In ${visible}`,
  };
}

export function deliveryDeepLink(events: NotificationEvent[]) {
  if (events.length === 1) {
    return `gradey://marks?event=${encodeURIComponent(events[0].id)}`;
  }
  return `gradey://marks?summary=${encodeURIComponent(events[0].id)}`;
}

export function stableNotificationEventOrder<Event extends { id: string }>(
  events: Event[],
) {
  return [...events].sort((first, second) =>
    first.id === second.id ? 0 : first.id < second.id ? -1 : 1
  );
}

export function deliveryBatches<
  Event extends {
    quiet_hours_deferred_at?: string | null;
    quiet_delivery_key?: string | null;
  },
>(events: Event[]) {
  const deferredGroups = new Map<string, Event[]>();
  const deferredWithoutKey: Event[] = [];
  const immediate = events.filter((event) =>
    event.quiet_hours_deferred_at == null
  );

  for (const event of events) {
    if (event.quiet_hours_deferred_at == null) continue;
    const key = event.quiet_delivery_key?.trim();
    if (!key) {
      // A legacy deferred event has no stable summary identity, so keep it as
      // an individual push rather than combining unrelated quiet windows.
      deferredWithoutKey.push(event);
      continue;
    }
    const group = deferredGroups.get(key) ?? [];
    group.push(event);
    deferredGroups.set(key, group);
  }

  return [
    ...deferredGroups.values(),
    ...deferredWithoutKey.map((event) => [event]),
    ...immediate.map((event) => [event]),
  ];
}

/**
 * Derives a repeatable APNs request/collapse identity for a quiet-hours
 * summary. A worker crash after APNs accepts the request can therefore retry
 * with the same identity. Delivery remains at-least-once because APNs does not
 * provide a transactional acknowledgement with our database.
 */
export async function quietSummaryDispatchIdentity(
  quietDeliveryKey: string,
  deviceID: string,
): Promise<APNSDispatchIdentity> {
  if (!quietDeliveryKey.trim() || !deviceID.trim()) {
    throw new Error("Quiet delivery key and device ID are required");
  }

  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        `gradey-quiet-summary\u001f${quietDeliveryKey}\u001f${deviceID}`,
      ),
    ),
  );
  const uuidBytes = digest.slice(0, 16);
  uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50;
  uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80;
  const hex = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const uuidHex = Array.from(
    uuidBytes,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");

  return {
    apnsID: [
      uuidHex.slice(0, 8),
      uuidHex.slice(8, 12),
      uuidHex.slice(12, 16),
      uuidHex.slice(16, 20),
      uuidHex.slice(20),
    ].join("-"),
    collapseID: `gradey-q-${hex.slice(0, 55)}`,
  };
}

export function retryDelayMilliseconds(attemptCount: number) {
  const minutes = [1, 5, 15, 60, 180];
  const index = Math.max(0, Math.min(minutes.length - 1, attemptCount - 1));
  return minutes[index] * 60 * 1000;
}

export function isTransientAPNSStatus(status: number) {
  return status === 429 || status >= 500;
}

export function isRejectedDeviceToken(status: number, reason: string | null) {
  return status === 410 ||
    (status === 400 &&
      ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(
        reason ?? "",
      ));
}

function aliasedField(
  input: Record<string, unknown>,
  camel: string,
  snake: string,
) {
  if (Object.prototype.hasOwnProperty.call(input, camel)) return input[camel];
  if (Object.prototype.hasOwnProperty.call(input, snake)) return input[snake];
  return undefined;
}

function booleanField(
  input: Record<string, unknown>,
  camel: string,
  snake: string,
  fallback: boolean,
) {
  const value = aliasedField(input, camel, snake);
  if (value === undefined) return fallback;
  if (typeof value !== "boolean") throw new Error(`${camel} must be a boolean`);
  return value;
}

function minuteField(
  input: Record<string, unknown>,
  camel: string,
  snake: string,
  fallback: number,
) {
  const value = aliasedField(input, camel, snake);
  if (value === undefined) return fallback;
  if (!Number.isInteger(value) || Number(value) < 0 || Number(value) > 1439) {
    throw new Error(`${camel} must be an integer between 0 and 1439`);
  }
  return Number(value);
}

function uniqueSubjects(events: NotificationEvent[], useFullName: boolean) {
  return Array.from(
    new Set(
      events.map((event) => {
        const value = useFullName
          ? event.subject_name || event.subject_abbrev
          : event.subject_abbrev;
        return value ? clipped(value.trim(), 72) : null;
      }).filter((value): value is string => value != null),
    ),
  );
}

function clipped(value: string, maximumLength: number) {
  if (value.length <= maximumLength) return value;
  return `${value.slice(0, Math.max(1, maximumLength - 1)).trimEnd()}…`;
}

interface WallParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

function zonedParts(instant: Date, timeZone: string): WallParts {
  const formatter = new Intl.DateTimeFormat("en-GB-u-ca-gregory-nu-latn", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const values = Object.fromEntries(
    formatter.formatToParts(instant)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  );
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour,
    minute: values.minute,
  };
}

function addLocalDays(
  date: Pick<WallParts, "year" | "month" | "day">,
  count: number,
) {
  const result = new Date(
    Date.UTC(date.year, date.month - 1, date.day + count),
  );
  return {
    year: result.getUTCFullYear(),
    month: result.getUTCMonth() + 1,
    day: result.getUTCDate(),
  };
}

function wallSerial(parts: WallParts) {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
  );
}

function sameLocalDate(first: WallParts, second: WallParts) {
  return first.year === second.year && first.month === second.month &&
    first.day === second.day;
}

/** Converts an IANA-zone wall time to an instant without assuming a fixed UTC
 * offset. Exact matches handle DST folds; for a skipped spring-forward time,
 * the first representable wall minute after the requested time is used. */
function wallTimeToInstant(target: WallParts, timeZone: string, after: Date) {
  const targetSerial = wallSerial(target);
  let guess = targetSerial;

  for (let iteration = 0; iteration < 4; iteration += 1) {
    const represented = zonedParts(new Date(guess), timeZone);
    const delta = targetSerial - wallSerial(represented);
    if (delta === 0) break;
    guess += delta;
  }

  const searchStart = guess - 4 * 60 * 60 * 1000;
  const searchEnd = guess + 4 * 60 * 60 * 1000;
  let firstAfterGap: Date | null = null;

  for (let value = searchStart; value <= searchEnd; value += 60 * 1000) {
    if (value <= after.getTime()) continue;
    const candidate = new Date(value);
    const represented = zonedParts(candidate, timeZone);
    if (!sameLocalDate(represented, target)) continue;
    const representedSerial = wallSerial(represented);
    if (representedSerial === targetSerial) return candidate;
    if (representedSerial > targetSerial && firstAfterGap == null) {
      firstAfterGap = candidate;
    }
  }

  if (firstAfterGap) return firstAfterGap;
  throw new Error(`Could not resolve quiet-hours end in ${timeZone}`);
}
