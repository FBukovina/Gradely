export async function markFingerprint(provider: string, linkedAccountID: string, subjectID: string, mark: Record<string, unknown>) {
  const providerMarkID = stringValue(mark.Id ?? mark.id);
  if (providerMarkID) {
    return {
      subjectID,
      providerMarkID,
      source: "provider_id",
      fingerprint: [provider, linkedAccountID, subjectID, "provider", providerMarkID].join(":"),
    };
  }

  const content = [
    provider,
    linkedAccountID,
    subjectID,
    stringValue(mark.MarkDate),
    stringValue(mark.EditDate),
    stringValue(mark.MarkText),
    stringValue(mark.Caption),
    stringValue(mark.Theme),
    stringValue(mark.Type),
    stringValue(mark.TypeNote),
    stringValue(mark.Weight),
    stringValue(mark.PointsText),
    stringValue(mark.MaxPoints),
  ].join("\u001f");

  return {
    subjectID,
    providerMarkID: null,
    source: "content_hash",
    fingerprint: [provider, linkedAccountID, subjectID, "content", await sha256(content)].join(":"),
  };
}

export interface MarkCandidate {
  subjectID: string;
  providerMarkID: string | null;
  source: string;
  fingerprint: string;
  subjectAbbrev: string | null;
  subjectName: string | null;
  markText: string;
}

/** Fingerprints every mark in a provider response once, in response order. */
export async function markCandidates(
  provider: string,
  linkedAccountID: string,
  subjects: Record<string, any>[],
): Promise<MarkCandidate[]> {
  const seen = new Set<string>();
  const candidates: MarkCandidate[] = [];
  for (const subject of subjects) {
    const subjectID = String(subject.Subject?.Id || "unknown-subject");
    for (const mark of subject.Marks ?? []) {
      const fingerprint = await markFingerprint(provider, linkedAccountID, subjectID, mark);
      if (seen.has(fingerprint.fingerprint)) continue;
      seen.add(fingerprint.fingerprint);
      candidates.push({
        ...fingerprint,
        subjectAbbrev: subject.Subject?.Abbrev ?? null,
        subjectName: subject.Subject?.Name ?? null,
        markText: String(mark.MarkText || ""),
      });
    }
  }
  return candidates;
}

export function notificationBody(markText: string, subjectAbbrev?: string | null, subjectName?: string | null) {
  return `${markText} from ${subjectAbbrev || subjectName || "school"}`;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value.trim() : value == null ? "" : String(value);
}

async function sha256(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
