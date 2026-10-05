import { fetchAllOwnedRows, fetchWebAccountData } from "./account-export.ts";

type Call = { table: string; columns?: string; owner?: [string, string]; order?: string; cursor?: [string, string] };
function clientFixture(pages: (call: Call) => Record<string, unknown>[]) {
  const calls: Call[] = [];
  const client = { from(table: string) {
    const call: Call = { table }; calls.push(call);
    const query = {
      select(columns: string) { call.columns = columns; return query; },
      eq(column: string, value: string) { call.owner = [column,value]; return query; },
      order(column: string) { call.order = column; return query; },
      limit() { return query; },
      gt(column: string, value: string) { call.cursor = [column,value]; return query; },
      then(resolve: (value: unknown) => unknown) { return Promise.resolve({ data: pages(call), error: null }).then(resolve); },
    };
    return query;
  } } as unknown as Parameters<typeof fetchAllOwnedRows>[0];
  return { client, calls };
}
function assert(value: unknown, message: string) { if (!value) throw new Error(message); }

Deno.test("Planner export scopes every page by owner and retains tombstones with revisions", async () => {
  const initial = Array.from({length:500}, (_,i) => ({item_id:String(i).padStart(4,"0"),item:{id:String(i)},revision:i+1}));
  const final = {item_id:"0500",item:{id:"0500",deletedAt:"2026-10-05T10:00:00Z"},revision:501};
  const {client,calls} = clientFixture(call => call.cursor ? [final] : initial);
  const rows = await fetchAllOwnedRows(client,"planner_items","user-a","item_id,item,revision","owner_id","item_id");
  assert(rows.length === 501 && rows.at(-1) === final,"Export lost a page or tombstone");
  assert(calls.length === 2 && calls.every(call => JSON.stringify(call.owner) === JSON.stringify(["owner_id","user-a"]) && call.order === "item_id"),"A page escaped owner scope");
  assert(JSON.stringify(calls[1].cursor) === JSON.stringify(["item_id","0499"]),"Wrong Planner cursor");
});
Deno.test("Web export uses explicit safe columns and does not query credential tables",async()=>{
  const {client,calls} = clientFixture(()=>[]);
  const result = await fetchWebAccountData(client,"user-a");
  assert(JSON.stringify(Object.keys(result).sort()) === JSON.stringify(["plannerItems","webCalendarFeeds","webPushPreferences"]),"Missing web data collections");
  assert(calls.length === 3 && calls.every(call => call.owner?.[1] === "user-a"),"Wrong export owner");
  assert(calls.every(call=>!/(?:\*|token|endpoint|p256dh|auth|ciphertext|secret)/.test(call.columns || "")),"Secret column selected");
  assert(calls.map(call=>call.table).sort().join(",") === "planner_items,web_calendar_feeds,web_push_subscriptions","Unexpected table selected");
});
