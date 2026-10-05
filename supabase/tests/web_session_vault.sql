-- Run only against an isolated local database after the web_session_vault migration.
begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222') on conflict do nothing;
do $$
declare
  owner uuid := '11111111-1111-4111-8111-111111111111';
  other_owner uuid := '22222222-2222-4222-8222-222222222222';
  lease uuid := '33333333-3333-4333-8333-333333333333';
  other_lease uuid := '44444444-4444-4444-8444-444444444444';
  session_id text := repeat('a',64);
  guest_id text := repeat('b',64);
  function_row record;
begin
  if not public.gradey_web_session_put(session_id,owner,'synthetic-ciphertext',now()+interval '1 day') then raise exception 'initial insert failed'; end if;
  if public.gradey_web_session_put(session_id,other_owner,'replacement',now()+interval '1 day') then raise exception 'unleased overwrite allowed'; end if;
  if public.gradey_web_session_lock(session_id,other_owner,lease) then raise exception 'cross-account lease allowed'; end if;
  if public.gradey_web_session_lock(session_id,null,lease) then raise exception 'guest adopted account session'; end if;
  if not public.gradey_web_session_lock(session_id,owner,lease) then raise exception 'owner lease failed'; end if;
  if public.gradey_web_session_lock(session_id,owner,other_lease) then raise exception 'parallel lease allowed'; end if;
  if public.gradey_web_session_put(session_id,owner,'bad-write',now()+interval '1 day',other_lease) then raise exception 'stale write allowed'; end if;
  perform public.gradey_web_session_unlock(session_id,other_lease);
  if public.gradey_web_session_lock(session_id,owner,other_lease) then raise exception 'foreign unlock released lease'; end if;
  if not public.gradey_web_session_put(session_id,owner,'rotated-session',now()+interval '1 day',lease) then raise exception 'owned write failed'; end if;
  if public.gradey_web_session_get(session_id)->>'ciphertext' <> 'rotated-session' then raise exception 'ciphertext mismatch'; end if;
  perform public.gradey_web_session_unlock(session_id,lease);
  if not public.gradey_web_session_lock(session_id,owner,other_lease) then raise exception 'lease release failed'; end if;
  update gradey_private.web_sessions set lease_until=now()-interval '1 second' where id=session_id;
  if public.gradey_web_session_put(session_id,owner,'expired-owner',now()+interval '1 day',other_lease) then raise exception 'expired lease write allowed'; end if;
  if not public.gradey_web_session_lock(session_id,owner,lease) then raise exception 'expired lease recovery failed'; end if;
  if not public.gradey_web_session_put(guest_id,null,'guest-ciphertext',now()+interval '1 day') then raise exception 'guest insert failed'; end if;
  if public.gradey_web_session_lock(guest_id,owner,lease) then raise exception 'account adopted guest session'; end if;
  if not public.gradey_web_session_lock(guest_id,null,lease) then raise exception 'guest lease failed'; end if;
  if not public.gradey_web_session_put(guest_id,null,'guest-rotated',now()+interval '1 day',lease) then raise exception 'guest session write failed'; end if;
  if not public.gradey_web_rate_limit(repeat('c',64),2,60) or not public.gradey_web_rate_limit(repeat('c',64),2,60) or public.gradey_web_rate_limit(repeat('c',64),2,60) then raise exception 'rate limit failed'; end if;
  for function_row in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'gradey_web_%' loop
    if has_function_privilege('anon',function_row.oid,'EXECUTE') or has_function_privilege('authenticated',function_row.oid,'EXECUTE') then raise exception 'browser can call vault RPC'; end if;
    if not has_function_privilege('service_role',function_row.oid,'EXECUTE') then raise exception 'service cannot call vault RPC'; end if;
  end loop;
  if has_schema_privilege('anon','gradey_private','USAGE') or has_schema_privilege('authenticated','gradey_private','USAGE') then raise exception 'browser has private schema access'; end if;
  update gradey_private.web_sessions set expires_at=now()-interval '1 second' where id=guest_id;
  if public.gradey_web_session_get(guest_id) is not null then raise exception 'expired guest read allowed'; end if;
  perform public.gradey_web_cleanup_sessions();
  if exists(select 1 from gradey_private.web_sessions where id=guest_id) then raise exception 'expired session survived cleanup'; end if;
  delete from auth.users where id=owner;
  if public.gradey_web_session_get(session_id) is not null then raise exception 'deleted account retained session'; end if;
end; $$;
rollback;
