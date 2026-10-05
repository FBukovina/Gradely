const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const types = new Set(["homework", "test", "presentation", "note", "task"]);
const allowed = new Set(["id", "title", "notes", "type", "subject", "lesson", "linkedDate", "dueDate", "dueHasTime", "isCompleted", "createdAt", "updatedAt", "timeZoneIdentifier", "deletedAt"]);

export function validatePlannerSync(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid sync request");
  const body = value as Record<string, unknown>;
  const cursor = body.cursor ?? 0;
  if (!Number.isSafeInteger(cursor) || Number(cursor) < 0 || !Array.isArray(body.changes) || body.changes.length > 100) throw new Error("Invalid sync batch");
  const ids = new Set<string>();
  const mutations = new Set<string>();
  const changes = body.changes.map((raw: unknown) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("Invalid change");
    const change = raw as Record<string, unknown>;
    if (!Number.isSafeInteger(change.baseRevision) || Number(change.baseRevision) < 0 || typeof change.mutationId !== "string" || !uuid.test(change.mutationId)) throw new Error("Invalid revision or mutation ID");
    if (!change.item || typeof change.item !== "object" || Array.isArray(change.item)) throw new Error("Invalid item");
    const item = { ...(change.item as Record<string, unknown>) };
    if (Object.keys(item).some(key => !allowed.has(key))) throw new Error("Unsupported item field");
    if (typeof item.id !== "string" || !uuid.test(item.id)) throw new Error("Invalid item ID");
    item.id = item.id.toLowerCase();
    const mutationId = change.mutationId.toLowerCase();
    if (ids.has(item.id as string) || mutations.has(mutationId)) throw new Error("Duplicate item or mutation");
    ids.add(item.id as string); mutations.add(mutationId);
    if (typeof item.title !== "string" || item.title.length > 500 || (item.deletedAt == null && !item.title.trim())) throw new Error("Invalid title");
    if (item.notes != null && (typeof item.notes !== "string" || item.notes.length > 20_000)) throw new Error("Invalid notes");
    if (typeof item.type !== "string" || !types.has(item.type) || typeof item.dueHasTime !== "boolean" || typeof item.isCompleted !== "boolean") throw new Error("Invalid item content");
    if (typeof item.timeZoneIdentifier !== "string" || item.timeZoneIdentifier.length > 100) throw new Error("Invalid time zone");
    try { new Intl.DateTimeFormat("en", { timeZone: item.timeZoneIdentifier as string }); } catch { throw new Error("Invalid time zone"); }
    for (const key of ["createdAt", "updatedAt", "linkedDate", "dueDate", "deletedAt"]) {
      if ((key === "createdAt" || key === "updatedAt") && item[key] == null) throw new Error("Missing timestamp");
      if (item[key] != null && (typeof item[key] !== "string" || !/^\d{4}-\d\d-\d\dT/.test(item[key] as string) || !Number.isFinite(Date.parse(item[key] as string)))) throw new Error("Invalid timestamp");
    }
    for (const key of ["subject", "lesson"]) {
      const ref = item[key] as Record<string, unknown> | null | undefined;
      if (ref == null) continue;
      if (typeof ref !== "object" || Array.isArray(ref) || JSON.stringify(ref).length > 8_000) throw new Error("Invalid school reference");
      const scope = ref.scope as Record<string, unknown> | undefined;
      if (!scope || typeof scope.rawValue !== "string" || !scope.rawValue || scope.rawValue.length > 160) throw new Error("Invalid school scope");
      const required = key === "subject" ? ["id", "name"] : ["lessonID", "dayKey", "hourCaption"];
      if (required.some(field => typeof ref[field] !== "string" || (ref[field] as string).length > 500)) throw new Error("Invalid school reference fields");
      const optional = key === "subject" ? ["abbreviation"] : ["subjectID", "teacher", "room"];
      if (optional.some(field => ref[field] != null && (typeof ref[field] !== "string" || (ref[field] as string).length > 500))) throw new Error("Invalid school reference fields");
      if (key === "lesson") {
        if (!Number.isSafeInteger(ref.hourID) || !Array.isArray(ref.groupIDs) || ref.groupIDs.length > 100 || ref.groupIDs.some(id => typeof id !== "string" || id.length > 500)) throw new Error("Invalid lesson reference");
        for (const field of ["start", "end"]) if (ref[field] != null && (typeof ref[field] !== "string" || !/^\d{4}-\d\d-\d\dT/.test(ref[field] as string) || !Number.isFinite(Date.parse(ref[field] as string)))) throw new Error("Invalid lesson timestamp");
      }
    }
    if (JSON.stringify(item).length > 40_000) throw new Error("Item too large");
    return { item, baseRevision: change.baseRevision as number, mutationId };
  });
  return { changes, cursor: cursor as number };
}
