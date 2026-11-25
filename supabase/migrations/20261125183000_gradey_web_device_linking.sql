-- Gradey for Web: QR-based device linking and independent web sessions.
-- Each web session owns an isolated provider token family stored in
-- encrypted_provider_secrets; raw school passwords remain strictly disallowed.

create or replace function public.sanitize_provider_secret(p_payload jsonb)
returns jsonb language plpgsql immutable security invoker set search_path = ''
as $$
declare
  v_result jsonb;
  v_edu jsonb;
  v_students jsonb;
  v_subjects jsonb;
  v_student_keys text[] := array['id', 'fullName', 'classID', 'className'];
begin
  -- Preserve APNs device tokens stored in encrypted_provider_secrets.
  if p_payload->>'provider' is null and jsonb_typeof(p_payload->'token') = 'string' then
    return public.provider_secret_strings(p_payload, array['token']);
  end if;
  if p_payload->>'provider' = 'stravaCZ' then
    return public.provider_secret_strings(p_payload,
      array['provider', 'serviceURL', 'sessionID', 'canteenNumber', 'username']);
  end if;
  v_result := public.provider_secret_strings(p_payload,
    array[
      'provider',
      'baseURL',
      'accessToken',
      'refreshToken',
      'tokenType',
      'expiresAt',
      'pollingSessionEstablishedAt',
      'webSessionEstablishedAt'
    ]);
  if p_payload->>'provider' = 'eduPage' then
    v_edu := public.provider_secret_strings(p_payload->'eduPage', array['sessionID', 'username', 'gsecHash', 'userID']);
    if p_payload->'eduPage'->'activeStudent' is not null and p_payload->'eduPage'->'activeStudent' <> 'null'::jsonb then
      v_edu := v_edu || jsonb_build_object('activeStudent', public.provider_secret_strings(p_payload->'eduPage'->'activeStudent', v_student_keys));
    end if;
    select coalesce(jsonb_agg(public.provider_secret_strings(value, v_student_keys) order by ordinality), '[]'::jsonb)
    into v_students
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'eduPage'->'linkedStudents') = 'array'
      then p_payload->'eduPage'->'linkedStudents' else '[]'::jsonb end) with ordinality;
    select coalesce(jsonb_agg(public.provider_secret_strings(value, array['id', 'name', 'shortName']) order by ordinality), '[]'::jsonb)
    into v_subjects
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'eduPage'->'subjects') = 'array'
      then p_payload->'eduPage'->'subjects' else '[]'::jsonb end) with ordinality;
    v_result := v_result || jsonb_build_object('eduPage', v_edu || jsonb_build_object('linkedStudents', v_students, 'subjects', v_subjects));
  end if;
  return v_result;
end;
$$;

revoke execute on function public.sanitize_provider_secret(jsonb) from public, anon, authenticated;
grant execute on function public.sanitize_provider_secret(jsonb) to service_role;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'web_pairing_status') then
    create type public.web_pairing_status as enum (
      'pending',
      'scanned',
      'approved',
      'claimed',
      'expired',
      'rejected'
    );
  end if;
end;
$$;

create table if not exists public.web_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  linked_account_id uuid references public.linked_accounts(id) on delete cascade,
  provider public.linked_account_provider not null check (provider in ('bakalari', 'eduPage')),
  provider_user_id text,
  base_url text not null,
  student_name text not null,
  class_name text,
  school_name text,
  secret_id uuid references public.encrypted_provider_secrets(id) on delete set null,
  session_token_hash text not null unique,
  previous_session_token_hash text,
  previous_token_grace_until timestamptz,
  csrf_token_hash text not null,
  user_agent_family text not null,
  browser_name text not null,
  os_name text not null,
  device_label text not null,
  created_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  rotated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoke_reason text
);

create table if not exists public.web_pairing_challenges (
  id uuid primary key default gen_random_uuid(),
  qr_secret_hash text not null unique,
  browser_binding_hash text not null,
  user_agent_family text not null,
  browser_name text not null,
  os_name text not null,
  device_label text not null,
  ip_hash text,
  status public.web_pairing_status not null default 'pending',
  scanner_user_id uuid references public.profiles(id) on delete cascade,
  web_session_id uuid references public.web_sessions(id) on delete set null,
  failed_attempts integer not null default 0,
  created_at timestamptz not null default now(),
  scanned_at timestamptz,
  approved_at timestamptz,
  claimed_at timestamptz,
  expires_at timestamptz not null
);

create index if not exists web_sessions_user_active_idx
  on public.web_sessions(user_id, last_active_at desc)
  where revoked_at is null;

create index if not exists web_sessions_prev_token_idx
  on public.web_sessions(previous_session_token_hash)
  where previous_session_token_hash is not null and revoked_at is null;

create index if not exists web_pairing_challenges_expires_idx
  on public.web_pairing_challenges(expires_at)
  where status in ('pending', 'scanned', 'approved');

alter table public.web_sessions enable row level security;
alter table public.web_pairing_challenges enable row level security;

drop policy if exists "web session owner read" on public.web_sessions;
create policy "web session owner read"
  on public.web_sessions
  for select
  using (auth.uid() = user_id);

-- Pairing challenges and session secrets are accessed exclusively via service_role.

create or replace function public.revoke_web_session(
  p_user_id uuid,
  p_session_id uuid,
  p_reason text default 'user_revoked'
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_session public.web_sessions%rowtype;
begin
  select ws.*
  into v_session
  from public.web_sessions as ws
  where ws.id = p_session_id
    and ws.user_id = p_user_id
  for update;

  if not found then
    return false;
  end if;

  if v_session.revoked_at is null then
    update public.web_sessions
    set
      revoked_at = now(),
      revoke_reason = coalesce(nullif(p_reason, ''), 'user_revoked'),
      secret_id = null,
      previous_session_token_hash = null,
      previous_token_grace_until = null
    where id = v_session.id;
  end if;

  if v_session.secret_id is not null then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = v_session.secret_id
      and secret.user_id = p_user_id;
  end if;

  insert into public.account_audit_logs (user_id, linked_account_id, event_name, metadata)
  values (
    p_user_id,
    v_session.linked_account_id,
    'web_session_revoked',
    jsonb_build_object(
      'web_session_id', v_session.id,
      'browser_name', v_session.browser_name,
      'os_name', v_session.os_name,
      'reason', coalesce(nullif(p_reason, ''), 'user_revoked')
    )
  );

  return true;
end;
$$;

create or replace function public.revoke_all_web_sessions(
  p_user_id uuid,
  p_reason text default 'user_revoked_all'
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_secret_ids uuid[];
  v_revoked_count integer := 0;
begin
  with target_sessions as (
    select id, secret_id
    from public.web_sessions
    where user_id = p_user_id
      and revoked_at is null
    for update
  ),
  updated as (
    update public.web_sessions as ws
    set
      revoked_at = now(),
      revoke_reason = coalesce(nullif(p_reason, ''), 'user_revoked_all'),
      secret_id = null,
      previous_session_token_hash = null,
      previous_token_grace_until = null
    from target_sessions
    where ws.id = target_sessions.id
    returning target_sessions.secret_id
  )
  select
    count(*)::integer,
    coalesce(array_agg(secret_id) filter (where secret_id is not null), array[]::uuid[])
  into v_revoked_count, v_secret_ids
  from updated;

  if cardinality(v_secret_ids) > 0 then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = any(v_secret_ids)
      and secret.user_id = p_user_id;
  end if;

  if v_revoked_count > 0 then
    insert into public.account_audit_logs (user_id, event_name, metadata)
    values (
      p_user_id,
      'web_sessions_revoked_all',
      jsonb_build_object(
        'revoked_count', v_revoked_count,
        'reason', coalesce(nullif(p_reason, ''), 'user_revoked_all')
      )
    );
  end if;

  return v_revoked_count;
end;
$$;

revoke execute on function public.revoke_web_session(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.revoke_all_web_sessions(uuid, text) from public, anon, authenticated;
grant execute on function public.revoke_web_session(uuid, uuid, text) to service_role;
grant execute on function public.revoke_all_web_sessions(uuid, text) to service_role;

create or replace function public.cleanup_deleted_web_session_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.secret_id is not null then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = old.secret_id
      and secret.user_id = old.user_id
      and not exists (
        select 1
        from public.web_sessions as ws
        where ws.secret_id = secret.id
      )
      and not exists (
        select 1
        from public.linked_accounts as account
        where account.secret_id = secret.id
      )
      and not exists (
        select 1
        from public.device_push_tokens as device
        where device.token_secret_id = secret.id
      );
  end if;
  return old;
end;
$$;

drop trigger if exists on_web_session_deleted on public.web_sessions;
create trigger on_web_session_deleted
after delete on public.web_sessions
for each row execute function public.cleanup_deleted_web_session_secret();
