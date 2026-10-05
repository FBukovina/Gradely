-- Run after migrations against a disposable test database; all fixtures roll back.
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
do $$
declare
  owner uuid := '11111111-1111-4111-8111-111111111111';
  other_owner uuid := '22222222-2222-4222-8222-222222222222';
  item jsonb := '{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","title":"Read","type":"task","dueHasTime":false,"isCompleted":false,"createdAt":"2026-10-05T00:00:00Z","updatedAt":"2026-10-05T00:00:00Z","timeZoneIdentifier":"Europe/Prague"}';
  changes jsonb; result jsonb; first_revision bigint;
begin
  changes := jsonb_build_array(jsonb_build_object('item',item,'baseRevision',0,'mutationId','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));
  result := public.planner_sync(owner, changes, 0);
  first_revision := (result->>'cursor')::bigint;
  if jsonb_array_length(result->'items') <> 1 or jsonb_array_length(result->'acceptedMutationIds') <> 1 then raise exception 'create failed'; end if;
  result := public.planner_sync(owner, changes, 0);
  if (result->>'cursor')::bigint <> first_revision then raise exception 'retry allocated a revision'; end if;
  begin
    perform public.planner_sync(owner, jsonb_set(changes, '{0,item,title}', '"Changed retry"'), 0);
    raise exception 'reused mutation accepted';
  exception when others then if SQLERRM = 'reused mutation accepted' then raise; end if; end;
  result := public.planner_sync(owner, jsonb_set(changes, '{0,mutationId}', '"cccccccc-cccc-4ccc-8ccc-cccccccccccc"'), first_revision);
  if jsonb_array_length(result->'conflicts') <> 1 then raise exception 'stale revision accepted'; end if;
  result := public.planner_sync(other_owner, '[]', 0);
  if jsonb_array_length(result->'items') <> 0 then raise exception 'cross-account read'; end if;
  item := item || '{"deletedAt":"2026-10-05T01:00:00Z","title":""}';
  changes := jsonb_build_array(jsonb_build_object('item',item,'baseRevision',first_revision,'mutationId','dddddddd-dddd-4ddd-8ddd-dddddddddddd'));
  result := public.planner_sync(owner, changes, first_revision);
  if result->'items'->0->'item'->>'deletedAt' is null then raise exception 'tombstone lost'; end if;
  changes := jsonb_build_array(jsonb_build_object('item',item - 'deletedAt','baseRevision',(result->>'cursor')::bigint,'mutationId','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'));
  result := public.planner_sync(owner, changes, 0);
  if jsonb_array_length(result->'conflicts') <> 1 then raise exception 'deleted ID resurrected'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
do $$ begin
  if exists(select 1 from public.planner_items) then raise exception 'RLS leaked another account'; end if;
  begin
    perform public.planner_sync('11111111-1111-4111-8111-111111111111','[]',0);
    raise exception 'authenticated user called privileged sync';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.planner_items;
    raise exception 'direct writes bypassed sync';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
