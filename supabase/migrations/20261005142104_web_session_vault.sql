-- Opaque browser-session credentials remain encrypted by the web server.
-- No browser role can read the vault or invoke these service-only RPCs.
create schema if not exists gradey_private;
revoke all on schema gradey_private from public, anon, authenticated;
create table gradey_private.web_sessions (
  id text primary key check (id ~ '^[a-f0-9]{64}$'),
  user_id uuid references auth.users(id) on delete cascade,
  ciphertext text not null check (length(ciphertext) <= 1000000),
  expires_at timestamptz not null,
  lease_id uuid,
  lease_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table gradey_private.web_sessions enable row level security;
create index web_sessions_expiry on gradey_private.web_sessions(expires_at);
create table gradey_private.web_rate_limits (key text primary key, count integer not null, expires_at timestamptz not null);
alter table gradey_private.web_rate_limits enable row level security;

create function public.gradey_web_session_get(p_id text) returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('user_id', user_id, 'ciphertext', ciphertext, 'expires_at', expires_at)
  from gradey_private.web_sessions where id = p_id and expires_at > now();
$$;
create function public.gradey_web_session_put(p_id text, p_user_id uuid, p_ciphertext text, p_expires_at timestamptz, p_lease uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_expires_at > now() + interval '8 days' or p_expires_at <= now() then return false; end if;
  if p_lease is null then
    insert into gradey_private.web_sessions(id,user_id,ciphertext,expires_at) values(p_id,p_user_id,p_ciphertext,p_expires_at) on conflict do nothing;
  else
    update gradey_private.web_sessions set ciphertext=p_ciphertext,expires_at=p_expires_at,updated_at=now()
    where id=p_id and user_id is not distinct from p_user_id and lease_id=p_lease and lease_until>now();
  end if;
  return found;
end; $$;
create function public.gradey_web_session_lock(p_id text, p_user_id uuid, p_lease uuid) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update gradey_private.web_sessions set lease_id=p_lease,lease_until=now()+interval '120 seconds'
  where id=p_id and user_id is not distinct from p_user_id and expires_at>now() and (lease_until is null or lease_until<now());
  return found;
end; $$;
create function public.gradey_web_session_unlock(p_id text,p_lease uuid) returns void language sql security definer set search_path = '' as $$
  update gradey_private.web_sessions set lease_id=null,lease_until=null where id=p_id and lease_id=p_lease;
$$;
create function public.gradey_web_session_delete(p_id text) returns void language sql security definer set search_path = '' as $$
  delete from gradey_private.web_sessions where id=p_id;
$$;
create function public.gradey_web_rate_limit(p_key text,p_limit integer,p_seconds integer) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if p_limit < 1 or p_limit > 1000 or p_seconds < 1 or p_seconds > 86400 or length(p_key) != 64 then return false; end if;
  insert into gradey_private.web_rate_limits(key,count,expires_at) values(p_key,1,now()+make_interval(secs=>p_seconds))
  on conflict(key) do update set count=case when gradey_private.web_rate_limits.expires_at<=now() then 1 else gradey_private.web_rate_limits.count+1 end,
    expires_at=case when gradey_private.web_rate_limits.expires_at<=now() then now()+make_interval(secs=>p_seconds) else gradey_private.web_rate_limits.expires_at end
  returning count into v_count;
  return v_count<=p_limit;
end; $$;
revoke all on function public.gradey_web_session_get(text), public.gradey_web_session_put(text,uuid,text,timestamptz,uuid), public.gradey_web_session_lock(text,uuid,uuid), public.gradey_web_session_unlock(text,uuid), public.gradey_web_session_delete(text), public.gradey_web_rate_limit(text,integer,integer) from public, anon, authenticated;
grant execute on function public.gradey_web_session_get(text), public.gradey_web_session_put(text,uuid,text,timestamptz,uuid), public.gradey_web_session_lock(text,uuid,uuid), public.gradey_web_session_unlock(text,uuid), public.gradey_web_session_delete(text), public.gradey_web_rate_limit(text,integer,integer) to service_role;

-- Scheduler registration is deliberately operational: expire data daily using this function.
create function public.gradey_web_cleanup_sessions() returns void language sql security definer set search_path = '' as $$
  delete from gradey_private.web_sessions where expires_at<=now();
  delete from gradey_private.web_rate_limits where expires_at<=now();
$$;
revoke all on function public.gradey_web_cleanup_sessions() from public, anon, authenticated;
grant execute on function public.gradey_web_cleanup_sessions() to service_role;
