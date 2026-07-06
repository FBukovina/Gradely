import { adminClient, providerSecretKey } from "../_shared/client.ts";
import { errorResponse, handleOptions, json } from "../_shared/http.ts";
import { markFingerprint, notificationBody } from "../_shared/marks.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    assertCronSecret(req);
    const supabase = adminClient();
    const now = new Date();

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
      outcomes.push(await pollAccount(supabase, account));
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

    const marksResponse = await fetchMarks(account.provider, secret);
    const newEvents = [];
    const isBaseline = !account.last_polled_at;

    for (const subject of marksResponse.Subjects ?? []) {
      await recordGradeHistory(supabase, account, subject);

      const subjectID = String(subject.Subject?.Id || "unknown-subject");
      for (const mark of subject.Marks ?? []) {
        const fingerprint = await markFingerprint(account.provider, account.id, subjectID, mark);

        const { data: insertedFingerprint, error: insertError } = await supabase
          .from("mark_fingerprints")
          .insert({
            user_id: account.user_id,
            linked_account_id: account.id,
            provider: account.provider,
            subject_id: subjectID,
            provider_mark_id: fingerprint.providerMarkID,
            fingerprint: fingerprint.fingerprint,
            source: fingerprint.source,
          })
          .select()
          .maybeSingle();

        if (insertError && insertError.code !== "23505") throw insertError;
        if (!insertedFingerprint || isBaseline) continue;

        const subjectAbbrev = subject.Subject?.Abbrev ?? null;
        const subjectName = subject.Subject?.Name ?? null;
        const markText = String(mark.MarkText || "");
        const { data: event, error: eventError } = await supabase
          .from("new_mark_events")
          .insert({
            user_id: account.user_id,
            linked_account_id: account.id,
            fingerprint_id: insertedFingerprint.id,
            provider: account.provider,
            subject_id: subjectID,
            subject_abbrev: subjectAbbrev,
            subject_name: subjectName,
            mark_text: markText,
            notification_title: "New mark",
            notification_body: notificationBody(markText, subjectAbbrev, subjectName),
          })
          .select()
          .single();
        if (eventError) throw eventError;

        newEvents.push(event);
      }
    }

    const nextPoll = nextPollDate(new Date());
    await supabase
      .from("linked_accounts")
      .update({
        last_polled_at: new Date().toISOString(),
        last_synced_at: new Date().toISOString(),
        next_poll_at: nextPoll.toISOString(),
        failure_count: 0,
      })
      .eq("id", account.id);

    if (newEvents.length > 0 && account.notifications_enabled) {
      await invokeSendAPNS(newEvents.map((event) => event.id));
    }

    return { accountID: account.id, newMarks: newEvents.length, baseline: isBaseline };
  } catch (error) {
    const failureCount = (account.failure_count ?? 0) + 1;
    await supabase
      .from("linked_accounts")
      .update({
        failure_count: failureCount,
        next_poll_at: backoffDate(failureCount).toISOString(),
        status: failureCount >= 3 ? "action_required" : account.status,
        action_required_reason: failureCount >= 3 ? "Provider session expired. Re-link this account in Gradey." : account.action_required_reason,
      })
      .eq("id", account.id);

    return { accountID: account.id, error: error instanceof Error ? error.message : "poll_failed" };
  }
}

async function fetchMarks(provider: string, secret: Record<string, any>) {
  if (provider === "bakalari") {
    const response = await fetch(new URL("api/3/marks", secret.baseURL).toString(), {
      headers: { Authorization: `${secret.tokenType || "Bearer"} ${secret.accessToken}`, Accept: "application/json" },
    });
    if (response.status === 401) throw new Error("bakalari_auth_failed");
    if (!response.ok) throw new Error(`bakalari_status_${response.status}`);
    return await response.json();
  }

  if (provider === "eduPage") {
    return await fetchEduPageMarks(secret);
  }

  throw new Error(`unsupported_provider_${provider}`);
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

async function fetchEduPageMarks(secret: Record<string, any>) {
  const eduPage = secret.eduPage;
  if (!eduPage?.sessionID) throw new Error("edupage_auth_failed");

  const url = new URL("znamky/", secret.baseURL);
  url.searchParams.set("barNoSkin", "1");
  const response = await fetch(url, {
    headers: {
      Accept: "text/html,application/xhtml+xml",
      Cookie: `PHPSESSID=${eduPage.sessionID}`,
    },
  });
  if (response.status === 401 || response.status === 403) throw new Error("edupage_auth_failed");
  if (!response.ok) throw new Error(`edupage_status_${response.status}`);

  const text = await response.text();
  if (text.includes("cmd=MainLogin") || (text.includes('name="username"') && text.includes('name="password"'))) {
    throw new Error("edupage_auth_failed");
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
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-apns`;
  await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ eventIDs }),
  });
}

function assertCronSecret(req: Request) {
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected) return;
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
