import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validatePlannerSync } from "./planner-sync.ts";

const item = { id: "AABBAABB-0000-4000-8000-000000000001", title: "Study", type: "task", dueHasTime: false,
  isCompleted: false, createdAt: "2026-10-05T10:00:00.000Z", updatedAt: "2026-10-05T10:00:00Z", timeZoneIdentifier: "Europe/Prague" };
const change = { item, baseRevision: 0, mutationId: "AABBAABB-0000-4000-8000-000000000002" };
Deno.test("normalizes native UUIDs and accepts ISO fractions", () => {
  const result = validatePlannerSync({ changes: [change] });
  assertEquals(result.cursor, 0); assertEquals(result.changes[0].item.id, item.id.toLowerCase());
  assertEquals(result.changes[0].mutationId, change.mutationId.toLowerCase());
});
Deno.test("rejects calendar identifiers, oversized content and invalid revisions", () => {
  for (const patch of [{ calendarEventIdentifier: "private" }, { title: "x".repeat(501) }, { dueDate: "tomorrow" }, { timeZoneIdentifier: "bad/zone" }]) {
    assertThrows(() => validatePlannerSync({ changes: [{ ...change, item: { ...item, ...patch } }] }));
  }
  assertThrows(() => validatePlannerSync({ changes: [{ ...change, baseRevision: -1 }] }));
  assertThrows(() => validatePlannerSync({ changes: [], cursor: Number.MAX_SAFE_INTEGER + 1 }));
});
Deno.test("rejects duplicate IDs and batches above bound", () => {
  assertThrows(() => validatePlannerSync({ changes: [change, change] }));
  assertThrows(() => validatePlannerSync({ changes: Array(101).fill(change) }));
});
Deno.test("retains tombstone with stripped private content", () => {
  assertEquals(validatePlannerSync({ changes: [{ ...change, item: { ...item, title: "", deletedAt: "2026-10-05T10:00:00Z" } }] }).changes.length, 1);
  assertThrows(() => validatePlannerSync({ changes: [{ ...change, item: { ...item, title: "" } }] }));
});
