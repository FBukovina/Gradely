create extension if not exists pgcrypto;

create type linked_account_provider as enum ('bakalari', 'eduPage', 'stravaCZ');
create type linked_account_status as enum ('active', 'action_required', 'paused', 'linking', 'failed');
create type notification_lock_screen_detail as enum ('private_summary', 'mark_and_subject', 'full_details');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table encrypted_provider_secrets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  ciphertext bytea not null,
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

create table linked_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  provider linked_account_provider not null,
  provider_user_id text,
  base_url text,
  display_name text not null,
  school_name text,
  canteen_name text,
  status linked_account_status not null default 'active',
  notifications_enabled boolean not null default true,
  secret_id uuid references encrypted_provider_secrets(id) on delete set null,
  last_polled_at timestamptz,
  last_synced_at timestamptz,
  next_poll_at timestamptz,
  failure_count integer not null default 0,
  action_required_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table notification_preferences (
  user_id uuid primary key references profiles(id) on delete cascade,
  new_marks_enabled boolean not null default true,
  lock_screen_detail notification_lock_screen_detail not null default 'mark_and_subject',
  quiet_hours_enabled boolean not null default false,
  quiet_hours_start_minute integer not null default 1320,
  quiet_hours_end_minute integer not null default 360,
  updated_at timestamptz not null default now()
);

create table device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null check (platform in ('ios', 'macos')),
  environment text not null check (environment in ('sandbox', 'production')),
  token_hash text not null unique,
  token_secret_id uuid not null references encrypted_provider_secrets(id) on delete cascade,
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  invalidated_at timestamptz
);

create table mark_fingerprints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  linked_account_id uuid not null references linked_accounts(id) on delete cascade,
  provider linked_account_provider not null,
  subject_id text not null,
  provider_mark_id text,
  fingerprint text not null,
  source text not null check (source in ('provider_id', 'content_hash')),
  first_seen_at timestamptz not null default now(),
  unique (linked_account_id, fingerprint)
);

create table new_mark_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  linked_account_id uuid not null references linked_accounts(id) on delete cascade,
  fingerprint_id uuid not null references mark_fingerprints(id) on delete cascade,
  provider linked_account_provider not null,
  subject_id text not null,
  subject_abbrev text,
  subject_name text,
  mark_text text not null,
  notification_title text not null default 'New mark',
  notification_body text not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique (linked_account_id, fingerprint_id)
);

create table account_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete set null,
  linked_account_id uuid references linked_accounts(id) on delete set null,
  event_name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index linked_accounts_user_idx on linked_accounts(user_id);
create index linked_accounts_poll_idx on linked_accounts(status, next_poll_at) where provider in ('bakalari', 'eduPage');
create index mark_fingerprints_account_idx on mark_fingerprints(linked_account_id);
create index new_mark_events_user_idx on new_mark_events(user_id, created_at desc);
create index device_push_tokens_user_idx on device_push_tokens(user_id) where invalidated_at is null;

alter table profiles enable row level security;
alter table linked_accounts enable row level security;
alter table notification_preferences enable row level security;
alter table device_push_tokens enable row level security;
alter table mark_fingerprints enable row level security;
alter table new_mark_events enable row level security;
alter table account_audit_logs enable row level security;
alter table encrypted_provider_secrets enable row level security;

create policy "profile owner read" on profiles for select using (auth.uid() = id);
create policy "profile owner update" on profiles for update using (auth.uid() = id);
create policy "linked account owner read" on linked_accounts for select using (auth.uid() = user_id);
create policy "linked account owner update" on linked_accounts for update using (auth.uid() = user_id);
create policy "notification owner read" on notification_preferences for select using (auth.uid() = user_id);
create policy "notification owner upsert" on notification_preferences for insert with check (auth.uid() = user_id);
create policy "notification owner update" on notification_preferences for update using (auth.uid() = user_id);
create policy "device owner read" on device_push_tokens for select using (auth.uid() = user_id);
create policy "mark owner read" on mark_fingerprints for select using (auth.uid() = user_id);
create policy "event owner read" on new_mark_events for select using (auth.uid() = user_id);
create policy "audit owner read" on account_audit_logs for select using (auth.uid() = user_id);

create or replace function public.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    avatar_url = excluded.avatar_url,
    updated_at = now();

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert or update on auth.users
for each row execute function public.create_profile_for_auth_user();

create or replace function public.store_provider_secret(p_user_id uuid, p_payload jsonb, p_key text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  insert into encrypted_provider_secrets (user_id, ciphertext)
  values (p_user_id, pgp_sym_encrypt(p_payload::text, p_key, 'compress-algo=1,cipher-algo=aes256'))
  returning id into v_secret_id;

  return v_secret_id;
end;
$$;

create or replace function public.read_provider_secret(p_secret_id uuid, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload text;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  select pgp_sym_decrypt(ciphertext, p_key) into v_payload
  from encrypted_provider_secrets
  where id = p_secret_id;

  return v_payload::jsonb;
end;
$$;
