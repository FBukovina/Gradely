import { adminClient, providerSecretKey } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
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
  quietHoursEnd,
  quietSummaryDispatchIdentity,
  retryDelayMilliseconds,
  stableNotificationEventOrder,
} from "../_shared/notification-delivery.ts";

interface EventRow extends NotificationEvent {
  delivery_attempt_count: number;
  quiet_hours_deferred_at?: string | null;
  quiet_delivery_key?: string | null;
  delivery_targets_created_at?: string | null;
}

interface DeviceRow {
  id: string;
  environment: string;
  token_secret_id: string;
  invalidated_at: string | null;
}

interface DeliveryRow {
  id: string;
  user_id: string;
  event_id: string;
  device_id: string;
  apns_id: string;
  delivery_due_at: string;
  delivery_attempt_count: number;
  last_attempt_at: string | null;
  last_delivery_error: string | null;
  accepted_at: string | null;
  suppressed_at: string | null;
  suppression_reason: string | null;
}

interface DeliveryCounters {
  claimed: number;
  sent: number;
  rescheduled: number;
  suppressed: number;
  retried: number;
  invalidatedTokens: number;
}

let cachedAPNSJWT: { value: string; expiresAt: number } | null = null;

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    assertInternalCaller(req);
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => ({}));
    const eventIDs = parseEventIDs(body?.eventIDs);
    if (eventIDs?.length === 0) return json(emptyCounters());

    const supabase = adminClient();
    const claimToken = crypto.randomUUID();
    const { data, error } = await supabase.rpc("claim_new_mark_events", {
      p_claim_token: claimToken,
      p_limit: eventIDs ? Math.min(eventIDs.length, 500) : 250,
      p_event_ids: eventIDs ?? null,
    });
    if (error) throw error;

    const events = (data ?? []) as EventRow[];
    const counters = emptyCounters();
    counters.claimed = events.length;

    for (const group of groupByUser(events).values()) {
      try {
        await dispatchUserEvents(supabase, claimToken, group, counters);
      } catch (error) {
        const message = error instanceof Error
          ? error.message
          : "dispatch_failed";
        await recoverDispatchError(
          supabase,
          claimToken,
          group,
          message,
          counters,
        );
      }
    }

    console.log(
      JSON.stringify({ event: "apns_dispatch_complete", ...counters }),
    );
    return json(counters);
  } catch (error) {
    return errorResponse(error, "Could not send APNs notifications");
  }
});

async function dispatchUserEvents(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  claimedEvents: EventRow[],
  counters: DeliveryCounters,
) {
  const userID = claimedEvents[0].user_id;
  const [preferencesResult, accountsResult] = await Promise.all([
    supabase
      .from("notification_preferences")
      .select("*")
      .eq("user_id", userID)
      .maybeSingle(),
    supabase
      .from("linked_accounts")
      .select("id,status,notifications_enabled")
      .eq("user_id", userID)
      .in(
        "id",
        Array.from(
          new Set(claimedEvents.map((event) => event.linked_account_id)),
        ),
      ),
  ]);
  if (preferencesResult.error) throw preferencesResult.error;
  if (accountsResult.error) throw accountsResult.error;

  const preferences = {
    ...defaultNotificationPreferences,
    ...(preferencesResult.data ?? {}),
  } as NotificationPreferencesRow;
  if (
    notificationSuppressionReason(preferences, {
      status: "active",
      notifications_enabled: true,
    })
  ) {
    await terminateEvents(
      supabase,
      claimToken,
      claimedEvents,
      "global_notifications_disabled",
      counters,
    );
    return;
  }

  const accounts = new Map(
    (accountsResult.data ?? []).map((account) => [account.id, account]),
  );
  const disabledEvents = claimedEvents.filter((event) => {
    const account = accounts.get(event.linked_account_id);
    return notificationSuppressionReason(preferences, account) != null;
  });
  if (disabledEvents.length > 0) {
    await terminateEvents(
      supabase,
      claimToken,
      disabledEvents,
      "linked_account_notifications_disabled",
      counters,
    );
  }

  const events = claimedEvents.filter((event) =>
    !disabledEvents.includes(event)
  );
  if (events.length === 0) return;

  const now = new Date();
  const quietEnd = quietHoursEnd(now, preferences);
  if (quietEnd) {
    await rescheduleForQuietHours(
      supabase,
      claimToken,
      events,
      now,
      quietEnd,
      counters,
    );
    return;
  }

  // Quiet events intentionally seal their device snapshot only when the
  // window ends, so devices registered during quiet hours receive the queued
  // summary. Once sealed, retries keep the same target rows.
  const targetedEvents = await ensureDeliveryTargets(
    supabase,
    claimToken,
    userID,
    events,
    counters,
  );
  if (targetedEvents.length === 0) return;

  const eventIDs = targetedEvents.map((event) => event.id);
  const { data: deliveryData, error: deliveryError } = await supabase
    .from("new_mark_event_deliveries")
    .select(
      "id,user_id,event_id,device_id,apns_id,delivery_due_at,delivery_attempt_count,last_attempt_at,last_delivery_error,accepted_at,suppressed_at,suppression_reason",
    )
    .eq("user_id", userID)
    .in("event_id", eventIDs);
  if (deliveryError) throw deliveryError;

  const deliveries = (deliveryData ?? []) as DeliveryRow[];
  const eventsWithRows = new Set(
    deliveries.map((delivery) => delivery.event_id),
  );
  const eventsWithoutRows = targetedEvents.filter((event) =>
    !eventsWithRows.has(event.id)
  );
  if (eventsWithoutRows.length > 0) {
    await suppressEvents(
      supabase,
      claimToken,
      eventsWithoutRows,
      "no_active_device",
      counters,
    );
  }

  const eventsByID = new Map(targetedEvents.map((event) => [event.id, event]));
  const pendingDeliveries = deliveries.filter((delivery) =>
    delivery.accepted_at == null && delivery.suppressed_at == null
  );
  const deviceIDs = Array.from(
    new Set(pendingDeliveries.map((delivery) => delivery.device_id)),
  );
  const devicesByID = new Map<string, DeviceRow>();
  if (deviceIDs.length > 0) {
    const { data: devices, error: deviceError } = await supabase
      .from("device_push_tokens")
      .select("id,environment,token_secret_id,invalidated_at")
      .eq("user_id", userID)
      .in("id", deviceIDs);
    if (deviceError) throw deviceError;
    for (const device of (devices ?? []) as DeviceRow[]) {
      devicesByID.set(device.id, device);
    }
  }

  const unavailable = pendingDeliveries.filter((delivery) => {
    const device = devicesByID.get(delivery.device_id);
    return !device || device.invalidated_at != null;
  });
  if (unavailable.length > 0) {
    counters.suppressed += await suppressDeliveryRows(
      supabase,
      unavailable,
      "device_unavailable",
    );
  }

  const dueByDevice = new Map<string, DeliveryRow[]>();
  const currentTime = Date.now();
  for (const delivery of pendingDeliveries) {
    const device = devicesByID.get(delivery.device_id);
    if (
      !device || device.invalidated_at != null ||
      new Date(delivery.delivery_due_at).getTime() > currentTime
    ) {
      continue;
    }
    const group = dueByDevice.get(delivery.device_id) ?? [];
    group.push(delivery);
    dueByDevice.set(delivery.device_id, group);
  }

  for (const [deviceID, deviceDeliveries] of dueByDevice) {
    const device = devicesByID.get(deviceID);
    if (!device) continue;
    const batchableEvents = stableNotificationEventOrder(
      deviceDeliveries.flatMap((delivery) => {
        const event = eventsByID.get(delivery.event_id);
        return event ? [event] : [];
      }),
    );
    const deliveriesByEventID = new Map(
      deviceDeliveries.map((delivery) => [delivery.event_id, delivery]),
    );

    for (const eventBatch of deliveryBatches(batchableEvents)) {
      const deliveryBatch = eventBatch.flatMap((event) => {
        const delivery = deliveriesByEventID.get(event.id);
        return delivery ? [delivery] : [];
      });
      if (deliveryBatch.length === 0) continue;

      const invalidated = await deliverDeviceBatch(
        supabase,
        userID,
        eventBatch,
        deliveryBatch,
        device,
        preferences,
        counters,
      );
      if (invalidated) {
        counters.suppressed += await suppressDeliveryRows(
          supabase,
          pendingDeliveries.filter((delivery) =>
            delivery.device_id === deviceID
          ),
          "device_token_rejected",
        );
        break;
      }
    }
  }

  await finalizeParentDeliveries(
    supabase,
    claimToken,
    Array.from(eventsWithRows),
  );
}

async function ensureDeliveryTargets(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  userID: string,
  events: EventRow[],
  counters: DeliveryCounters,
) {
  const unsealed = events.filter((event) =>
    event.delivery_targets_created_at == null
  );
  if (unsealed.length === 0) return events;

  const unsealedIDs = unsealed.map((event) => event.id);
  const { data: existingRows, error: existingError } = await supabase
    .from("new_mark_event_deliveries")
    .select("event_id")
    .eq("user_id", userID)
    .in("event_id", unsealedIDs);
  if (existingError) throw existingError;
  const alreadySeededIDs = new Set(
    (existingRows ?? []).map((row) => row.event_id as string),
  );
  const needingTargets = unsealed.filter((event) =>
    !alreadySeededIDs.has(event.id)
  );

  const { data: devices, error: deviceError } = await supabase
    .from("device_push_tokens")
    .select("id")
    .eq("user_id", userID)
    .is("invalidated_at", null);
  if (deviceError) throw deviceError;
  const activeDeviceIDs = (devices ?? []).map((device) => device.id as string);

  let withoutTargets: EventRow[] = [];
  if (needingTargets.length > 0 && activeDeviceIDs.length === 0) {
    withoutTargets = needingTargets;
    await suppressEvents(
      supabase,
      claimToken,
      withoutTargets,
      "no_active_device",
      counters,
    );
  } else if (needingTargets.length > 0) {
    const rows = needingTargets.flatMap((event) =>
      activeDeviceIDs.map((deviceID) => ({
        user_id: userID,
        event_id: event.id,
        device_id: deviceID,
      }))
    );
    const { error } = await supabase
      .from("new_mark_event_deliveries")
      .upsert(rows, {
        onConflict: "event_id,device_id",
        ignoreDuplicates: true,
      });
    if (error) throw error;
  }

  const sealedIDs = unsealedIDs.filter((id) =>
    !withoutTargets.some((event) => event.id === id)
  );
  if (sealedIDs.length > 0) {
    const now = new Date().toISOString();
    const { error } = await supabase
      .from("new_mark_events")
      .update({ delivery_targets_created_at: now })
      .eq("claim_token", claimToken)
      .is("delivery_targets_created_at", null)
      .in("id", sealedIDs);
    if (error) throw error;
  }

  const excluded = new Set(withoutTargets.map((event) => event.id));
  return events.filter((event) => !excluded.has(event.id));
}

async function deliverDeviceBatch(
  supabase: ReturnType<typeof adminClient>,
  userID: string,
  events: EventRow[],
  deliveries: DeliveryRow[],
  device: DeviceRow,
  preferences: NotificationPreferencesRow,
  counters: DeliveryCounters,
) {
  const copy = notificationCopy(events, preferences.lock_screen_detail);
  const payload = {
    aps: {
      alert: copy,
      sound: "default",
    },
    url: deliveryDeepLink(events),
    eventID: events.length === 1 ? events[0].id : undefined,
    summaryID: events.length > 1 ? events[0].id : undefined,
    summaryCount: events.length > 1 ? events.length : undefined,
  };

  let apnsID = deliveries[0].apns_id;
  let collapseID = `gradey-mark-${events[0].id}`;
  if (events.length > 1) {
    const quietKey = events[0].quiet_delivery_key;
    if (
      !quietKey || events.some((event) => event.quiet_delivery_key !== quietKey)
    ) {
      throw new Error("Quiet summary events must share a delivery key");
    }
    const identity = await quietSummaryDispatchIdentity(quietKey, device.id);
    apnsID = identity.apnsID;
    collapseID = identity.collapseID;
  }

  let response: Response;
  try {
    const token = await readDeviceToken(supabase, device.token_secret_id);
    response = await sendAPNS(
      token,
      device.environment,
      payload,
      apnsID,
      collapseID,
    );
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "apns_network_error";
    await retryDeliveryRows(supabase, deliveries, message, counters);
    return false;
  }

  const reason = await apnsReason(response);
  if (response.ok) {
    const now = new Date().toISOString();
    const { data, error } = await supabase
      .from("new_mark_event_deliveries")
      .update({
        delivery_attempt_count: nextDeliveryAttempt(deliveries),
        last_attempt_at: now,
        last_delivery_error: null,
        accepted_at: now,
        updated_at: now,
      })
      .in("id", deliveries.map((delivery) => delivery.id))
      .eq("user_id", userID)
      .eq("device_id", device.id)
      .is("accepted_at", null)
      .is("suppressed_at", null)
      .select("id");
    if (error) throw error;
    counters.sent += data?.length ?? 0;
    return false;
  }

  const failure = (reason ?? `apns_status_${response.status}`).slice(0, 500);
  if (isRejectedDeviceToken(response.status, reason)) {
    const now = new Date().toISOString();
    const { data: invalidated, error } = await supabase
      .from("device_push_tokens")
      .update({ invalidated_at: now })
      .eq("id", device.id)
      .eq("user_id", userID)
      .is("invalidated_at", null)
      .select("id");
    if (error) throw error;
    counters.invalidatedTokens += invalidated?.length ?? 0;
    counters.suppressed += await suppressDeliveryRows(
      supabase,
      deliveries,
      `device_token_rejected:${failure}`,
      true,
    );
    return true;
  }

  if (isTransientAPNSStatus(response.status)) {
    await retryDeliveryRows(supabase, deliveries, failure, counters);
    return false;
  }

  counters.suppressed += await suppressDeliveryRows(
    supabase,
    deliveries,
    `permanent_apns_error:${failure}`,
    true,
  );
  return false;
}

async function retryDeliveryRows(
  supabase: ReturnType<typeof adminClient>,
  deliveries: DeliveryRow[],
  message: string,
  counters: DeliveryCounters,
) {
  const attemptCount = nextDeliveryAttempt(deliveries);
  const now = new Date().toISOString();
  if (attemptCount >= 5) {
    const { data, error } = await supabase
      .from("new_mark_event_deliveries")
      .update({
        delivery_attempt_count: 5,
        last_attempt_at: now,
        last_delivery_error: message.slice(0, 500),
        suppressed_at: now,
        suppression_reason: "retry_limit_reached",
        updated_at: now,
      })
      .in("id", deliveries.map((delivery) => delivery.id))
      .is("accepted_at", null)
      .is("suppressed_at", null)
      .select("id");
    if (error) throw error;
    counters.suppressed += data?.length ?? 0;
    return;
  }

  const { data, error } = await supabase
    .from("new_mark_event_deliveries")
    .update({
      delivery_attempt_count: attemptCount,
      last_attempt_at: now,
      last_delivery_error: message.slice(0, 500),
      delivery_due_at: new Date(
        Date.now() + retryDelayMilliseconds(attemptCount),
      ).toISOString(),
      updated_at: now,
    })
    .in("id", deliveries.map((delivery) => delivery.id))
    .is("accepted_at", null)
    .is("suppressed_at", null)
    .select("id");
  if (error) throw error;
  counters.retried += data?.length ?? 0;
}

async function suppressDeliveryRows(
  supabase: ReturnType<typeof adminClient>,
  deliveries: DeliveryRow[],
  reason: string,
  attempted = false,
) {
  if (deliveries.length === 0) return 0;
  const now = new Date().toISOString();
  const patch: Record<string, unknown> = {
    suppressed_at: now,
    suppression_reason: reason.slice(0, 500),
    updated_at: now,
  };
  if (attempted) {
    patch.delivery_attempt_count = nextDeliveryAttempt(deliveries);
    patch.last_attempt_at = now;
    patch.last_delivery_error = reason.slice(0, 500);
  }
  const { data, error } = await supabase
    .from("new_mark_event_deliveries")
    .update(patch)
    .in("id", deliveries.map((delivery) => delivery.id))
    .is("accepted_at", null)
    .is("suppressed_at", null)
    .select("id");
  if (error) throw error;
  return data?.length ?? 0;
}

async function rescheduleForQuietHours(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  events: EventRow[],
  now: Date,
  quietEnd: Date,
  counters: DeliveryCounters,
) {
  const eventIDs = events.map((event) => event.id);
  const quietEndISO = quietEnd.toISOString();
  const nowISO = now.toISOString();
  const { error: deliveryError } = await supabase
    .from("new_mark_event_deliveries")
    .update({ delivery_due_at: quietEndISO, updated_at: nowISO })
    .eq("user_id", events[0].user_id)
    .in("event_id", eventIDs)
    .is("accepted_at", null)
    .is("suppressed_at", null);
  if (deliveryError) throw deliveryError;

  const { data: rescheduled, error } = await supabase
    .from("new_mark_events")
    .update({
      delivery_due_at: quietEndISO,
      quiet_hours_deferred_at: nowISO,
      quiet_delivery_key: quietEndISO,
      claim_token: null,
      claimed_at: null,
      claim_expires_at: null,
      last_delivery_error: null,
    })
    .eq("claim_token", claimToken)
    .in("id", eventIDs)
    .select("id");
  if (error) throw error;
  counters.rescheduled += rescheduled?.length ?? 0;
}

async function terminateEvents(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  events: EventRow[],
  reason: string,
  counters: DeliveryCounters,
) {
  if (events.length === 0) return;
  const eventIDs = events.map((event) => event.id);
  const { data: childRows, error } = await supabase
    .from("new_mark_event_deliveries")
    .select(
      "id,user_id,event_id,device_id,apns_id,delivery_due_at,delivery_attempt_count,last_attempt_at,last_delivery_error,accepted_at,suppressed_at,suppression_reason",
    )
    .eq("user_id", events[0].user_id)
    .in("event_id", eventIDs);
  if (error) throw error;
  const deliveries = (childRows ?? []) as DeliveryRow[];
  counters.suppressed += await suppressDeliveryRows(
    supabase,
    deliveries,
    reason,
  );

  const childEventIDs = Array.from(
    new Set(deliveries.map((delivery) => delivery.event_id)),
  );
  if (childEventIDs.length > 0) {
    await finalizeParentDeliveries(supabase, claimToken, childEventIDs);
  }
  const childEvents = new Set(childEventIDs);
  await suppressEvents(
    supabase,
    claimToken,
    events.filter((event) => !childEvents.has(event.id)),
    reason,
    counters,
  );
}

async function finalizeParentDeliveries(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  eventIDs: string[],
) {
  if (eventIDs.length === 0) return;
  const { error } = await supabase.rpc("finalize_new_mark_event_deliveries", {
    p_event_ids: eventIDs,
    p_claim_token: claimToken,
  });
  if (error) throw error;
}

async function recoverDispatchError(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  events: EventRow[],
  message: string,
  counters: DeliveryCounters,
) {
  const eventIDs = events.map((event) => event.id);
  const { data, error } = await supabase
    .from("new_mark_event_deliveries")
    .select("id,event_id,accepted_at,suppressed_at")
    .eq("user_id", events[0].user_id)
    .in("event_id", eventIDs);
  if (error) throw error;
  const childRows = data ?? [];
  const unfinishedIDs = childRows.filter((row) =>
    row.accepted_at == null && row.suppressed_at == null
  ).map((row) => row.id as string);
  if (unfinishedIDs.length > 0) {
    const now = new Date().toISOString();
    const { error: recoveryError } = await supabase
      .from("new_mark_event_deliveries")
      .update({
        delivery_due_at: new Date(Date.now() + 60_000).toISOString(),
        last_delivery_error: message.slice(0, 500),
        updated_at: now,
      })
      .in("id", unfinishedIDs)
      .is("accepted_at", null)
      .is("suppressed_at", null);
    if (recoveryError) throw recoveryError;
  }

  const childEventIDs = Array.from(
    new Set(childRows.map((row) => row.event_id as string)),
  );
  if (childEventIDs.length > 0) {
    await finalizeParentDeliveries(supabase, claimToken, childEventIDs);
  }
  const withChildren = new Set(childEventIDs);
  await retryEvents(
    supabase,
    claimToken,
    events.filter((event) => !withChildren.has(event.id)),
    message,
    counters,
  );
}

async function retryEvents(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  events: EventRow[],
  message: string,
  counters: DeliveryCounters,
) {
  if (events.length === 0) return;
  const attemptCount = nextAttemptCount(events);
  if (attemptCount >= 5) {
    const { data, error } = await supabase
      .from("new_mark_events")
      .update({
        delivery_attempt_count: 5,
        last_attempt_at: new Date().toISOString(),
        last_delivery_error: message.slice(0, 500),
        suppressed_at: new Date().toISOString(),
        suppression_reason: "retry_limit_reached",
        claim_token: null,
        claimed_at: null,
        claim_expires_at: null,
      })
      .eq("claim_token", claimToken)
      .in("id", events.map((event) => event.id))
      .select("id");
    if (error) throw error;
    counters.suppressed += data?.length ?? 0;
    return;
  }

  const { data, error } = await supabase
    .from("new_mark_events")
    .update({
      delivery_attempt_count: attemptCount,
      last_attempt_at: new Date().toISOString(),
      last_delivery_error: message.slice(0, 500),
      delivery_due_at: new Date(
        Date.now() + retryDelayMilliseconds(attemptCount),
      ).toISOString(),
      claim_token: null,
      claimed_at: null,
      claim_expires_at: null,
    })
    .eq("claim_token", claimToken)
    .in("id", events.map((event) => event.id))
    .select("id");
  if (error) throw error;
  counters.retried += data?.length ?? 0;
}

async function suppressEvents(
  supabase: ReturnType<typeof adminClient>,
  claimToken: string,
  events: EventRow[],
  reason: string,
  counters: DeliveryCounters,
) {
  if (events.length === 0) return;
  const { data, error } = await supabase
    .from("new_mark_events")
    .update({
      suppressed_at: new Date().toISOString(),
      suppression_reason: reason,
      claim_token: null,
      claimed_at: null,
      claim_expires_at: null,
    })
    .eq("claim_token", claimToken)
    .in("id", events.map((event) => event.id))
    .select("id");
  if (error) throw error;
  counters.suppressed += data?.length ?? 0;
}

async function readDeviceToken(
  supabase: ReturnType<typeof adminClient>,
  secretID: string,
) {
  const { data, error } = await supabase.rpc("read_provider_secret", {
    p_secret_id: secretID,
    p_key: providerSecretKey(),
  });
  if (error) throw error;
  if (typeof data?.token !== "string" || data.token.length === 0) {
    throw new Error("Missing device token");
  }
  return data.token;
}

async function sendAPNS(
  token: string,
  environment: string,
  payload: unknown,
  apnsID: string,
  collapseID: string,
) {
  const topic = Deno.env.get("APNS_TOPIC");
  if (!topic) throw new Error("Missing APNS_TOPIC");
  const jwt = await apnsJWT();
  const host = environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  return await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-id": apnsID,
      "apns-collapse-id": collapseID.slice(0, 64),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(15_000),
  });
}

async function apnsReason(response: Response) {
  try {
    const body = await response.json();
    return typeof body?.reason === "string" ? body.reason : null;
  } catch {
    return null;
  }
}

async function apnsJWT() {
  if (cachedAPNSJWT && cachedAPNSJWT.expiresAt > Date.now()) {
    return cachedAPNSJWT.value;
  }

  const teamID = Deno.env.get("APNS_TEAM_ID");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY_P8");
  if (!teamID || !keyID || !privateKey) {
    throw new Error("Missing APNs credentials");
  }

  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64URL(
    JSON.stringify({ iss: teamID, iat: Math.floor(Date.now() / 1000) }),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const value = `${header}.${claims}.${base64URL(new Uint8Array(signature))}`;
  cachedAPNSJWT = { value, expiresAt: Date.now() + 50 * 60 * 1000 };
  return value;
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem.replace(
    /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,
    "",
  );
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
}

function base64URL(value: string | Uint8Array) {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

function assertInternalCaller(req: Request) {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cronSecret = Deno.env.get("CRON_SECRET");
  const isServiceRole = serviceRoleKey != null &&
    req.headers.get("Authorization") === `Bearer ${serviceRoleKey}`;
  const isCron = cronSecret != null &&
    req.headers.get("x-cron-secret") === cronSecret;
  if (!isServiceRole && !isCron) {
    throw new Response("Internal dispatcher credentials required", {
      status: 401,
    });
  }
}

function parseEventIDs(value: unknown): string[] | null {
  if (value === undefined || value === null) return null;
  if (
    !Array.isArray(value) || value.length > 500 ||
    value.some((item) => typeof item !== "string")
  ) {
    throw new Response("Invalid event IDs", { status: 422 });
  }
  return Array.from(new Set(value));
}

function groupByUser(events: EventRow[]) {
  const groups = new Map<string, EventRow[]>();
  for (const event of events) {
    const group = groups.get(event.user_id) ?? [];
    group.push(event);
    groups.set(event.user_id, group);
  }
  return groups;
}

function nextAttemptCount(events: EventRow[]) {
  return Math.min(
    5,
    Math.max(...events.map((event) => event.delivery_attempt_count ?? 0)) + 1,
  );
}

function nextDeliveryAttempt(deliveries: DeliveryRow[]) {
  return Math.min(
    5,
    Math.max(
      ...deliveries.map((delivery) => delivery.delivery_attempt_count ?? 0),
    ) + 1,
  );
}

function emptyCounters(): DeliveryCounters {
  return {
    claimed: 0,
    sent: 0,
    rescheduled: 0,
    suppressed: 0,
    retried: 0,
    invalidatedTokens: 0,
  };
}
