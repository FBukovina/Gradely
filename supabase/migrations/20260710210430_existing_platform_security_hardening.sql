-- Adopt fail-closed Data API defaults and grant every API-facing object
-- explicitly. Existing migrations predate Supabase's explicit-grant defaults.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

-- Recreate ownership policies with explicit roles and immutable ownership on
-- UPDATE. Anonymous Supabase users still use the authenticated Postgres role,
-- so row ownership remains mandatory.
drop policy if exists "profile owner read" on public.profiles;
drop policy if exists "profile owner update" on public.profiles;
drop policy if exists "linked account owner read" on public.linked_accounts;
drop policy if exists "linked account owner update" on public.linked_accounts;
drop policy if exists "notification owner read" on public.notification_preferences;
drop policy if exists "notification owner upsert" on public.notification_preferences;
drop policy if exists "notification owner update" on public.notification_preferences;
drop policy if exists "device owner read" on public.device_push_tokens;
drop policy if exists "mark owner read" on public.mark_fingerprints;
drop policy if exists "event owner read" on public.new_mark_events;
drop policy if exists "audit owner read" on public.account_audit_logs;
drop policy if exists "grade history owner read" on public.grade_history_events;

create policy "profile owner read"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "profile owner update"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "linked account owner read"
  on public.linked_accounts for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "linked account owner update"
  on public.linked_accounts for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "notification owner read"
  on public.notification_preferences for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "notification owner upsert"
  on public.notification_preferences for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "notification owner update"
  on public.notification_preferences for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "device owner read"
  on public.device_push_tokens for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "mark owner read"
  on public.mark_fingerprints for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "event owner read"
  on public.new_mark_events for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "audit owner read"
  on public.account_audit_logs for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "grade history owner read"
  on public.grade_history_events for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- pgcrypto is installed in Supabase's extensions schema. Fully qualify its
-- functions so these SECURITY DEFINER helpers work with an empty search path.
create or replace function public.store_provider_secret(
  p_user_id uuid,
  p_payload jsonb,
  p_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret_id uuid;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  insert into public.encrypted_provider_secrets (user_id, ciphertext)
  values (
    p_user_id,
    extensions.pgp_sym_encrypt(
      p_payload::text,
      p_key,
      'compress-algo=1,cipher-algo=aes256'
    )
  )
  returning id into v_secret_id;

  return v_secret_id;
end;
$$;

create or replace function public.read_provider_secret(
  p_secret_id uuid,
  p_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload text;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  select extensions.pgp_sym_decrypt(secret.ciphertext, p_key)
  into v_payload
  from public.encrypted_provider_secrets as secret
  where secret.id = p_secret_id;

  return v_payload::jsonb;
end;
$$;

-- Provider-secret functions are privileged implementation details. Edge
-- Functions validate the user and invoke them with the service role.
revoke execute on function public.store_provider_secret(uuid, jsonb, text)
  from public, anon, authenticated;
revoke execute on function public.read_provider_secret(uuid, text)
  from public, anon, authenticated;
grant execute on function public.store_provider_secret(uuid, jsonb, text) to service_role;
grant execute on function public.read_provider_secret(uuid, text) to service_role;

-- Trigger functions do not need to be callable over the Data API.
revoke execute on function public.create_profile_for_auth_user()
  from public, anon, authenticated, service_role;

-- Remove legacy broad grants and expose only owner-readable account data.
revoke all on table
  public.profiles,
  public.linked_accounts,
  public.notification_preferences,
  public.device_push_tokens,
  public.mark_fingerprints,
  public.new_mark_events,
  public.account_audit_logs,
  public.encrypted_provider_secrets,
  public.grade_history_events
from anon, authenticated, service_role;

grant usage on schema public to authenticated, service_role;

grant select on table
  public.profiles,
  public.linked_accounts,
  public.notification_preferences,
  public.device_push_tokens,
  public.mark_fingerprints,
  public.new_mark_events,
  public.account_audit_logs,
  public.grade_history_events
to authenticated;

grant select, insert, update, delete on table
  public.profiles,
  public.linked_accounts,
  public.notification_preferences,
  public.device_push_tokens,
  public.mark_fingerprints,
  public.new_mark_events,
  public.account_audit_logs,
  public.encrypted_provider_secrets,
  public.grade_history_events
to service_role;

-- Make provider-secret ownership part of referential integrity rather than
-- relying only on application checks or RLS.
create unique index if not exists linked_accounts_id_user_id_key
  on public.linked_accounts (id, user_id);

create unique index if not exists encrypted_provider_secrets_id_user_id_key
  on public.encrypted_provider_secrets (id, user_id);

create index if not exists encrypted_provider_secrets_user_idx
  on public.encrypted_provider_secrets (user_id);

create index if not exists linked_accounts_secret_owner_idx
  on public.linked_accounts (secret_id, user_id)
  where secret_id is not null;

create index if not exists device_push_tokens_secret_owner_idx
  on public.device_push_tokens (token_secret_id, user_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'linked_accounts_secret_owner_fkey'
      and conrelid = 'public.linked_accounts'::regclass
  ) then
    alter table public.linked_accounts
      add constraint linked_accounts_secret_owner_fkey
      foreign key (secret_id, user_id)
      references public.encrypted_provider_secrets (id, user_id)
      on delete set null (secret_id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'device_push_tokens_secret_owner_fkey'
      and conrelid = 'public.device_push_tokens'::regclass
  ) then
    alter table public.device_push_tokens
      add constraint device_push_tokens_secret_owner_fkey
      foreign key (token_secret_id, user_id)
      references public.encrypted_provider_secrets (id, user_id)
      on delete cascade;
  end if;
end
$$;
