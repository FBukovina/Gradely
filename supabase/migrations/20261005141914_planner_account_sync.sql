-- Planner content is account-owned. EventKit identifiers and export state never leave a device.
create table public.planner_items (
  owner_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null,
  item jsonb not null check (jsonb_typeof(item) = 'object' and (item->>'id')::uuid = item_id),
  revision bigint not null check (revision > 0),
  primary key (owner_id, item_id)
);
create index planner_items_owner_revision on public.planner_items(owner_id, revision);
alter table public.planner_items enable row level security;
create policy planner_read_own on public.planner_items for select to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on public.planner_items from anon, authenticated;
grant select on public.planner_items to authenticated;
grant all on public.planner_items to service_role;

create table public.planner_sync_clock (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 0 check (revision >= 0 and revision <= 9007199254740991)
);
insert into public.planner_sync_clock values (true, 0);
alter table public.planner_sync_clock enable row level security;
revoke all on public.planner_sync_clock from anon, authenticated;
grant all on public.planner_sync_clock to service_role;

create table public.planner_mutations (
  owner_id uuid not null references auth.users(id) on delete cascade,
  mutation_id uuid not null,
  request jsonb not null,
  primary key (owner_id, mutation_id)
);
alter table public.planner_mutations enable row level security;
revoke all on public.planner_mutations from anon, authenticated;
grant all on public.planner_mutations to service_role;

-- Only the authenticated edge gateway may call this function. It derives p_owner from
-- auth.getUser(), never from the request body. SECURITY INVOKER retains the role boundary.
create function public.planner_sync(p_owner uuid, p_changes jsonb, p_cursor bigint default 0)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  clock_value bigint; change jsonb; remote public.planner_items%rowtype;
  item_id_value uuid; mutation_id_value uuid; prior_request jsonb;
  accepted jsonb := '[]'::jsonb; conflicts jsonb := '[]'::jsonb; changes_out jsonb;
begin
  if p_owner is null or p_cursor < 0 or jsonb_typeof(p_changes) <> 'array'
     or jsonb_array_length(p_changes) > 100 then raise exception 'Invalid Planner sync'; end if;
  -- A transactional counter (not nextval) serializes commit order. A client cursor can
  -- never skip an earlier allocated revision whose transaction has not committed yet.
  select revision into clock_value from public.planner_sync_clock where singleton for update;
  if p_cursor > clock_value then raise exception 'Invalid Planner cursor'; end if;
  for change in select value from jsonb_array_elements(p_changes) loop
    item_id_value := (change->'item'->>'id')::uuid;
    mutation_id_value := (change->>'mutationId')::uuid;
    if item_id_value is null or mutation_id_value is null or (change->>'baseRevision')::bigint < 0 then
      raise exception 'Invalid Planner change';
    end if;
    select request into prior_request from public.planner_mutations
      where owner_id = p_owner and mutation_id = mutation_id_value;
    if found then
      if prior_request <> change then raise exception 'Mutation ID reused with different content'; end if;
      accepted := accepted || jsonb_build_array(change->>'mutationId');
      continue;
    end if;
    select * into remote from public.planner_items where owner_id = p_owner and item_id = item_id_value;
    if coalesce(remote.revision, 0) <> (change->>'baseRevision')::bigint
       or (remote.item->>'deletedAt' is not null) then
      conflicts := conflicts || jsonb_build_array(jsonb_build_object('itemId', item_id_value,
        'remote', case when remote.revision is null then null else jsonb_build_object('item', remote.item, 'revision', remote.revision) end));
      continue;
    end if;
    clock_value := clock_value + 1;
    insert into public.planner_items(owner_id, item_id, item, revision)
      values (p_owner, item_id_value, change->'item', clock_value)
      on conflict (owner_id, item_id) do update set item = excluded.item, revision = excluded.revision;
    insert into public.planner_mutations(owner_id, mutation_id, request) values (p_owner, mutation_id_value, change);
    accepted := accepted || jsonb_build_array(change->>'mutationId');
  end loop;
  update public.planner_sync_clock set revision = clock_value where singleton;
  select coalesce(jsonb_agg(jsonb_build_object('item', item, 'revision', revision) order by revision), '[]'::jsonb)
    into changes_out from public.planner_items where owner_id = p_owner and revision > p_cursor;
  return jsonb_build_object('items', changes_out, 'conflicts', conflicts, 'cursor', clock_value, 'acceptedMutationIds', accepted);
end;
$$;
revoke all on function public.planner_sync(uuid, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.planner_sync(uuid, jsonb, bigint) to service_role;
