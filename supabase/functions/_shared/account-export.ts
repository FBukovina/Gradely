import type { adminClient } from "./client.ts";

type ExportClient = ReturnType<typeof adminClient>;

export async function fetchAllOwnedRows(
  supabase: ExportClient,
  table: string,
  userID: string,
  columns: string,
  ownerColumn = "user_id",
  cursorColumn = "id",
) {
  const rows: Record<string, unknown>[] = [];
  let cursor: string | null = null;
  while (true) {
    let query = supabase.from(table).select(columns).eq(ownerColumn, userID)
      .order(cursorColumn, { ascending: true }).limit(500);
    if (cursor) query = query.gt(cursorColumn, cursor);
    const { data, error } = await query;
    if (error) throw error;
    const page = (data ?? []) as unknown as Record<string, unknown>[];
    rows.push(...page);
    if (page.length < 500) break;
    const nextCursor = page.at(-1)?.[cursorColumn];
    if (typeof nextCursor !== "string" || nextCursor === cursor) {
      throw new Error(`Could not paginate ${table}`);
    }
    cursor = nextCursor;
  }
  return rows;
}

export async function fetchWebAccountData(supabase: ExportClient, userID: string) {
  const [plannerItems, webCalendarFeeds, webPushPreferences] = await Promise.all([
    fetchAllOwnedRows(supabase, "planner_items", userID, "item_id,item,revision", "owner_id", "item_id"),
    fetchAllOwnedRows(supabase, "web_calendar_feeds", userID, "created_at", "user_id", "user_id"),
    fetchAllOwnedRows(supabase, "web_push_subscriptions", userID, "id,planner_reminders,reminder_minute,time_zone,created_at"),
  ]);
  // No provider vault, calendar token hashes, push endpoints, or encryption keys.
  return { plannerItems, webCalendarFeeds, webPushPreferences };
}
