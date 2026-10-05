import {
  isProviderAuthenticationError,
  parseBakalariTokenResponse,
  ProviderAuthenticationError,
  resolveBakalariPollingSecret,
} from "../_shared/bakalari-provider-session.ts";
import { adminClient, providerSecretKey } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { markCandidates } from "../_shared/marks.ts";
import { requireSafeProviderURL } from "../_shared/provider-url.ts";

const POLL_LEASE_MS = 10 * 60 * 1000;
const PROVIDER_REQUEST_BUDGET_MS = 30_000;
const POLL_BATCH_BUDGET_MS = 60_000;

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    assertCronSecret(req);
    const supabase = adminClient();
    const now = new Date();
    const batchDeadline = now.getTime() + POLL_BATCH_BUDGET_MS;

    const { data: accounts, error } = await supabase
      .from("linked_accounts")
      .select("*")
      .in("provider", ["bakalari", "eduPage"])
      .eq("status", "active")
      .or(`next_poll_at.is.null,next_poll_at.lte.${now.toISOString()}`)
      .limit(50);
    if (error) throw error;

    const outcomes = [];
    for (const account of accounts ?? []) {
      // Leave time for the final account to finish before the cron HTTP timeout.
      // Remaining accounts stay due for the next scheduled invocation.
      if (Date.now() >= batchDeadline) break;
      const leasedAccount = await leaseAccount(supabase, account);
      if (!leasedAccount) continue;
      outcomes.push(await pollAccount(supabase, leasedAccount));
    }

    return json({ polled: outcomes.length, outcomes });
  } catch (error) {
    return errorResponse(error, "Could not poll new marks");
  }
});

async function pollAccount(supabase: ReturnType<typeof adminClient>, account: Record<string, any>) {
  try {
    if (!account.secret_id) throw new Error("Missing provider secret");

    const { data: secret, error: secretError } = await supabase.rpc("read_provider_secret", {
      p_secret_id: account.secret_id,
      p_key: providerSecretKey(),
    });
    if (secretError) throw secretError;

    const marksResponse = await fetchMarks(
      supabase, account, secret, AbortSignal.timeout(PROVIDER_REQUEST_BUDGET_MS),
    );
    const subjects = marksResponse.Subjects ?? [];

    for (const subject of subjects) {
      await recordGradeHistory(supabase, account, subject);
    }

    // Fingerprints, notification events, and baseline completion must commit
    // together, including when the worker dies or the RPC response is lost.
    const { data: recorded, error: recordError } = await supabase.rpc("record_polled_marks", {
      p_account_id: account.id,
      p_secret_id: account.secret_id,
      p_candidates: await markCandidates(account.provider, account.id, subjects),
      p_next_poll_at: nextPollDate(new Date()).toISOString(),
    });
    if (recordError) throw recordError;
    const eventIDs: string[] = recorded.eventIDs;
    if (eventIDs.length > 0) {
      await invokeSendAPNS(eventIDs);
    }

    return { accountID: account.id, newMarks: eventIDs.length, baseline: recorded.baseline, skipped: recorded.skipped };
  } catch (error) {
    const failureCount = (account.failure_count ?? 0) + 1;
    const authenticationFailure = isProviderAuthenticationError(error);
    const requiresAction = authenticationFailure && failureCount >= 3;
    const { error: failureError } = await supabase
      .from("linked_accounts")
      .update({
        failure_count: failureCount,
        next_poll_at: backoffDate(failureCount).toISOString(),
        status: requiresAction ? "action_required" : account.status,
        action_required_reason: requiresAction
          ? "Provider session expired. Reconnect this account in Gradey."
          : account.action_required_reason,
      })
      .eq("id", account.id)
      .eq("secret_id", account.secret_id)
      .eq("status", "active");
    if (failureError) throw failureError;

    return { accountID: account.id, error: error instanceof Error ? error.message : "poll_failed" };
  }
}

/**
 * Overlapping cron runs must not poll the same account: both would redeem the
 * same single-use Bakaláři refresh token, and the loser breaks the chain.
 */
async function leaseAccount(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
) {
  const now = new Date();
  const { data, error } = await supabase
    .from("linked_accounts")
    .update({ next_poll_at: new Date(now.getTime() + POLL_LEASE_MS).toISOString() })
    .eq("id", account.id)
    .eq("secret_id", account.secret_id)
    .eq("status", "active")
    .or(`next_poll_at.is.null,next_poll_at.lte.${now.toISOString()}`)
    .select("*")
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function fetchMarks(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
  secret: Record<string, any>,
  signal: AbortSignal,
) {
  const baseURL = requireSafeProviderURL(secret.baseURL, "Stored school URL");

  if (account.provider === "bakalari") {
    return await fetchBakalariMarks(supabase, account, secret, baseURL, signal);
  }

  if (account.provider === "eduPage") {
    return await fetchEduPageMarks(secret, baseURL, signal);
  }

  throw new Error(`unsupported_provider_${account.provider}`);
}

async function fetchBakalariMarks(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
  secret: Record<string, any>,
  baseURL: string,
  signal: AbortSignal,
) {
  const resolved = await resolveAndPersistBakalariSecret(supabase, account, secret, baseURL, signal);
  let activeSecret = resolved.secret;
  let response = await requestBakalariMarks(activeSecret, baseURL, signal);

  if (response.status === 401 && !resolved.didMutate) {
    activeSecret = (await resolveAndPersistBakalariSecret(
      supabase,
      account,
      activeSecret,
      baseURL,
      signal,
      true,
    )).secret;
    response = await requestBakalariMarks(activeSecret, baseURL, signal);
  }

  if (response.status === 401) throw new ProviderAuthenticationError("bakalari_auth_failed");
  if (!response.ok) throw new Error(`bakalari_status_${response.status}`);
  return await response.json();
}

// Deno's fetch sends `Accept-Language: *` by default. Bakaláři's IIS servers
// cannot map `*` to a culture and answer every request with HTTP 500.
const BAKALARI_ACCEPT_LANGUAGE = "cs-CZ";

function requestBakalariMarks(secret: Record<string, any>, baseURL: string, signal: AbortSignal) {
  return fetch(new URL("api/3/marks", baseURL).toString(), {
    headers: {
      Authorization: `${secret.tokenType || "Bearer"} ${secret.accessToken}`,
      Accept: "application/json",
      "Accept-Language": BAKALARI_ACCEPT_LANGUAGE,
    },
    redirect: "error",
    signal,
  });
}

async function resolveAndPersistBakalariSecret(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
  secret: Record<string, any>,
  baseURL: string,
  signal: AbortSignal,
  forceRefresh = false,
) {
  const resolved = await resolveBakalariPollingSecret(secret, {
    forceRefresh,
    refresh: (refreshToken) => requestBakalariTokens(baseURL, {
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }, signal),
  });
  if (!resolved.didMutate) {
    return { secret: resolved.secret as Record<string, any>, didMutate: false };
  }
  return {
    secret: await persistProviderSecret(supabase, account, resolved.secret),
    didMutate: true,
  };
}

async function requestBakalariTokens(baseURL: string, fields: Record<string, string>, signal: AbortSignal) {
  const body = new URLSearchParams({
    client_id: "ANDR",
    ...fields,
  });
  const response = await fetch(new URL("api/login", baseURL).toString(), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Accept-Language": BAKALARI_ACCEPT_LANGUAGE,
      "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
    },
    body,
    redirect: "error",
    signal,
  });

  if (response.status === 400 || response.status === 401) {
    throw new ProviderAuthenticationError(
      "bakalari_refresh_rejected",
    );
  }
  if (!response.ok) throw new Error(`bakalari_token_status_${response.status}`);
  return parseBakalariTokenResponse(await response.json());
}

async function persistProviderSecret(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
  secret: Record<string, unknown>,
) {
  const { data: updated, error } = await supabase.rpc("update_provider_secret", {
    p_secret_id: account.secret_id,
    p_user_id: account.user_id,
    p_payload: secret,
    p_key: providerSecretKey(),
  });
  if (error) throw error;
  if (updated !== true) throw new Error("provider_secret_update_failed");
  return secret as Record<string, any>;
}

async function recordGradeHistory(
  supabase: ReturnType<typeof adminClient>,
  account: Record<string, any>,
  subject: Record<string, any>,
) {
  const subjectID = String(subject.Subject?.Id || "unknown-subject");
  const subjectAbbrev = subject.Subject?.Abbrev ?? null;
  const subjectName = subject.Subject?.Name ?? null;
  const averageValue = subjectAverageValue(subject);
  const markCount = Array.isArray(subject.Marks) ? subject.Marks.length : 0;

  const { data: previous, error: previousError } = await supabase
    .from("grade_history_events")
    .select("average_value,mark_count")
    .eq("linked_account_id", account.id)
    .eq("subject_id", subjectID)
    .order("captured_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (previousError) throw previousError;

  const hasPrevious = previous != null;
  const previousAverage = numberValue(previous?.average_value);
  const previousMarkCount = Number(previous?.mark_count ?? 0);
  const averageChanged = !numbersEqual(previousAverage, averageValue);
  const markCountChanged = previousMarkCount !== markCount;

  if (hasPrevious && !averageChanged && !markCountChanged) return;

  const { error } = await supabase.from("grade_history_events").insert({
    user_id: account.user_id,
    linked_account_id: account.id,
    provider: account.provider,
    subject_id: subjectID,
    subject_abbrev: subjectAbbrev,
    subject_name: subjectName,
    average_value: averageValue,
    mark_count: markCount,
    average_delta: hasPrevious && previousAverage != null && averageValue != null ? averageValue - previousAverage : null,
    mark_count_delta: hasPrevious ? markCount - previousMarkCount : 0,
    event_type: hasPrevious ? "changed" : "baseline",
  });
  if (error) throw error;
}

function subjectAverageValue(subject: Record<string, any>) {
  const explicit = numberValue(subject.AverageText);
  if (explicit != null) return explicit;

  let weightedSum = 0;
  let totalWeight = 0;
  for (const mark of subject.Marks ?? []) {
    if (mark.IsPoints === true) continue;
    const value = numberValue(mark.CalculatedMarkText ?? mark.MarkText);
    if (value == null || value < 1 || value > 5) continue;
    const weight = Math.max(1, numberValue(mark.Weight) ?? 1);
    weightedSum += value * weight;
    totalWeight += weight;
  }
  return totalWeight > 0 ? Number((weightedSum / totalWeight).toFixed(4)) : null;
}

function numbersEqual(first: number | null, second: number | null) {
  if (first == null || second == null) return first == second;
  return Math.abs(first - second) < 0.0001;
}

async function fetchEduPageMarks(secret: Record<string, any>, baseURL: string, signal: AbortSignal) {
  const eduPage = secret.eduPage;
  if (!eduPage?.sessionID) throw new ProviderAuthenticationError("edupage_auth_failed");

  const url = new URL("znamky/", baseURL);
  url.searchParams.set("barNoSkin", "1");
  const response = await fetch(url, {
    headers: {
      Accept: "text/html,application/xhtml+xml",
      Cookie: `PHPSESSID=${eduPage.sessionID}`,
    },
    redirect: "error",
    signal,
  });
  if (response.status === 401 || response.status === 403) {
    throw new ProviderAuthenticationError("edupage_auth_failed");
  }
  if (!response.ok) throw new Error(`edupage_status_${response.status}`);

  const text = await response.text();
  if (text.includes("cmd=MainLogin") || (text.includes('name="username"') && text.includes('name="password"'))) {
    throw new ProviderAuthenticationError("edupage_auth_failed");
  }

  const root = firstJSONObject(text, "vsetkyZnamky");
  const rawGrades = Array.isArray(root?.vsetkyZnamky) ? root.vsetkyZnamky : null;
  if (!rawGrades) throw new Error("edupage_missing_grade_data");

  const events = root?.vsetkyUdalosti?.edupage ?? {};
  const subjects = new Map((eduPage.subjects ?? []).map((subject: Record<string, unknown>) => [stringValue(subject.id), subject]));
  const grouped = new Map<string, Record<string, unknown>[]>();

  for (const rawGrade of rawGrades) {
    const eventID = stringValue(rawGrade?.udalostid);
    const details = events[eventID];
    const subjectID = stringValue(details?.PredmetID);
    if (!eventID || !details || !subjectID || subjectID === "vsetky") continue;

    const rawValue = stringValue(rawGrade?.data);
    const valueParts = rawValue.split(" (");
    const markText = (valueParts[0] || rawValue).trim();
    const comment = valueParts.length > 1
      ? valueParts.slice(1).join(" (").replace(/\)+$/g, "").trim()
      : null;
    const gradeType = stringValue(details.p_typ_udalosti) || "1";
    const isPoints = gradeType === "2" || gradeType === "3";
    const parsedMark = numberValue(markText);
    const isSupportedCzechGrade = gradeType === "1" && parsedMark != null && parsedMark >= 1 && parsedMark <= 5;
    const rawWeight = numberValue(details.p_vaha);
    const maximum = gradeType === "2" ? numberValue(details.p_vaha) : (gradeType === "3" ? numberValue(details.p_vaha_body) : null);

    const marks = grouped.get(subjectID) ?? [];
    marks.push({
      MarkDate: stringValue(rawGrade?.datum),
      Caption: stringValue(details.p_meno) || null,
      Theme: comment,
      MarkText: markText,
      TeacherId: stringValue(details.UcitelID) || null,
      Type: isPoints ? "points" : (isSupportedCzechGrade ? "grade" : "unsupported"),
      TypeNote: gradeType === "3" ? "%" : null,
      Weight: isPoints ? null : (rawWeight == null ? null : rawWeight / 20.0),
      SubjectId: subjectID,
      IsPoints: isPoints,
      Id: eventID,
      PointsText: isPoints ? markText : null,
      MaxPoints: maximum == null ? null : Math.round(maximum),
    });
    grouped.set(subjectID, marks);
  }

  return {
    Subjects: Array.from(grouped.entries()).map(([subjectID, marks]) => {
      const profile = subjects.get(subjectID) as Record<string, unknown> | undefined;
      const fallbackName = stringValue(profile?.name) || stringValue(profile?.shortName) || subjectID;
      return {
        Subject: {
          Id: subjectID,
          Abbrev: stringValue(profile?.shortName) || fallbackName,
          Name: fallbackName,
        },
        Marks: marks,
        PointsOnly: marks.length > 0 && marks.every((mark) => mark.IsPoints === true),
        MarkPredictionEnabled: false,
      };
    }),
  };
}

function nextPollDate(now: Date) {
  const pragueHour = Number(new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Prague",
    hour: "numeric",
    hour12: false,
  }).format(now));
  const minutes = pragueHour >= 6 && pragueHour < 22 ? 15 : 60;
  const jitter = Math.floor(Math.random() * 120);
  return new Date(now.getTime() + minutes * 60 * 1000 + jitter * 1000);
}

function backoffDate(failureCount: number) {
  const minutes = Math.min(120, 15 * failureCount);
  return new Date(Date.now() + minutes * 60 * 1000);
}

async function invokeSendAPNS(eventIDs: string[]) {
  try {
    const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-apns`;
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ eventIDs }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      console.error(JSON.stringify({ event: "send_apns_immediate_failed", status: response.status, eventIDs }));
    }
  } catch (error) {
    console.error(JSON.stringify({
      event: "send_apns_immediate_failed",
      error: error instanceof Error ? error.message : "request_failed",
      eventIDs,
    }));
  }
}

function assertCronSecret(req: Request) {
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected) throw new Error("Missing CRON_SECRET");
  if (req.headers.get("x-cron-secret") !== expected) {
    throw new Response("Invalid cron secret", { status: 401 });
  }
}

function firstJSONObject(text: string, containingKey: string): Record<string, any> | null {
  let index = 0;
  while (index < text.length) {
    const start = text.indexOf("{", index);
    if (start === -1) return null;
    const jsonText = balancedJSONObject(text, start);
    if (jsonText?.includes(`"${containingKey}"`)) {
      try {
        const object = JSON.parse(jsonText);
        if (object?.[containingKey] != null) return object;
      } catch {
        // Keep scanning; EduPage pages often contain several object literals.
      }
    }
    index = start + 1;
  }
  return null;
}

function balancedJSONObject(text: string, start: number) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < text.length; index += 1) {
    const character = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
    } else if (character === '"') {
      inString = true;
    } else if (character === "{") {
      depth += 1;
    } else if (character === "}") {
      depth -= 1;
      if (depth === 0) return text.slice(start, index + 1);
    }
  }
  return null;
}

function stringValue(value: unknown) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}

function numberValue(value: unknown) {
  if (typeof value === "number") return value;
  const normalized = stringValue(value).replace(",", ".");
  if (!normalized) return null;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
}
