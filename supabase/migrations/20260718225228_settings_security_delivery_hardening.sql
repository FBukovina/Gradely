-- Validate canonical notification time zones at the database boundary as well
-- as in the Edge Function. PostgreSQL's catalog is the authoritative list for
-- server-side scheduling.
create or replace function public.is_valid_iana_timezone(p_identifier text)
returns boolean
language sql
stable
parallel safe
security invoker
set search_path = ''
as $$
  select p_identifier is not null
    and exists (
      select 1
      from pg_catalog.pg_timezone_names as zone
      where zone.name = p_identifier
    );
$$;

revoke execute on function public.is_valid_iana_timezone(text)
  from public, anon, authenticated;
grant execute on function public.is_valid_iana_timezone(text)
  to service_role;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'notification_preferences_quiet_timezone_iana'
      and conrelid = 'public.notification_preferences'::regclass
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_quiet_timezone_iana
      check (public.is_valid_iana_timezone(quiet_hours_time_zone))
      not valid;
  end if;
end
$$;

alter table public.notification_preferences
  validate constraint notification_preferences_quiet_timezone_iana;

-- A school identity is provider + canonical school endpoint + provider user
-- (the EduPage child ID or Bakalari user UID). This allows multiple children
-- while making retries and concurrent links converge on one row.
alter table public.linked_accounts
  add column if not exists school_identity_key text;

create or replace function public.school_account_identity_key(
  p_provider public.linked_account_provider,
  p_base_url text,
  p_provider_user_id text
)
returns text
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $$
  select case
    when p_provider in ('bakalari'::public.linked_account_provider, 'eduPage'::public.linked_account_provider)
      and p_base_url is not null
    then encode(
      extensions.digest(
        concat_ws(
          pg_catalog.chr(31),
          p_provider::text,
          pg_catalog.regexp_replace(pg_catalog.btrim(p_base_url), '/+$', ''),
          coalesce(
            nullif(pg_catalog.btrim(p_provider_user_id), ''),
            '__unknown__'
          )
        ),
        'sha256'
      ),
      'hex'
    )
    else null
  end;
$$;

revoke execute on function public.school_account_identity_key(
  public.linked_account_provider,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.school_account_identity_key(
  public.linked_account_provider,
  text,
  text
) to service_role;

-- Preserve any historical duplicate data without allowing it to keep polling.
-- The oldest row becomes canonical; legacy duplicates receive a noncanonical
-- migration-only suffix and are paused. All future writes pass through the
-- trigger below and therefore cannot create another duplicate identity.
with identities as (
  select
    account.id,
    account.user_id,
    public.school_account_identity_key(
      account.provider,
      account.base_url,
      account.provider_user_id
    ) as identity_key,
    first_value(account.id) over (
      partition by
        account.user_id,
        account.provider,
        public.school_account_identity_key(
          account.provider,
          account.base_url,
          account.provider_user_id
        )
      order by account.created_at, account.id
    ) as canonical_id,
    row_number() over (
      partition by
        account.user_id,
        account.provider,
        public.school_account_identity_key(
          account.provider,
          account.base_url,
          account.provider_user_id
        )
      order by account.created_at, account.id
    ) as identity_rank
  from public.linked_accounts as account
  where account.provider in ('bakalari', 'eduPage')
    and public.school_account_identity_key(
      account.provider,
      account.base_url,
      account.provider_user_id
    ) is not null
)
update public.profiles as profile
set
  active_school_account_id = identities.canonical_id,
  updated_at = now()
from identities
where identities.identity_rank > 1
  and profile.id = identities.user_id
  and profile.active_school_account_id = identities.id;

with ranked as (
  select
    account.id,
    public.school_account_identity_key(
      account.provider,
      account.base_url,
      account.provider_user_id
    ) as identity_key,
    row_number() over (
      partition by
        account.user_id,
        account.provider,
        coalesce(
          public.school_account_identity_key(
            account.provider,
            account.base_url,
            account.provider_user_id
          ),
          account.id::text
        )
      order by account.created_at, account.id
    ) as identity_rank
  from public.linked_accounts as account
  where account.provider in ('bakalari', 'eduPage')
)
update public.linked_accounts as account
set
  school_identity_key = case
    when ranked.identity_key is null then 'legacy:missing-url:' || account.id::text
    when ranked.identity_rank = 1 then ranked.identity_key
    else ranked.identity_key || ':legacy:' || account.id::text
  end,
  status = case
    when ranked.identity_key is not null and ranked.identity_rank = 1
      then account.status
    else 'paused'::public.linked_account_status
  end,
  notifications_enabled = case
    when ranked.identity_key is not null and ranked.identity_rank = 1
      then account.notifications_enabled
    else false
  end,
  action_required_reason = case
    when ranked.identity_key is null
      then 'This legacy school link has no provider URL. Reconnect it in Gradey.'
    when ranked.identity_rank = 1 then account.action_required_reason
    else 'Legacy duplicate link retained for history. Unlink this duplicate in Gradey.'
  end,
  updated_at = now()
from ranked
where account.id = ranked.id;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'linked_accounts_school_identity_shape'
      and conrelid = 'public.linked_accounts'::regclass
  ) then
    alter table public.linked_accounts
      add constraint linked_accounts_school_identity_shape
      check (
        (
          provider in ('bakalari', 'eduPage')
          and school_identity_key is not null
        )
        or
        (
          provider = 'stravaCZ'
          and school_identity_key is null
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'linked_accounts_school_identity_unique'
      and conrelid = 'public.linked_accounts'::regclass
  ) then
    alter table public.linked_accounts
      add constraint linked_accounts_school_identity_unique
      unique (user_id, provider, school_identity_key);
  end if;
end
$$;

create or replace function public.set_school_account_identity_key()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.school_identity_key := public.school_account_identity_key(
    new.provider,
    new.base_url,
    new.provider_user_id
  );
  return new;
end;
$$;

drop trigger if exists set_school_account_identity_key on public.linked_accounts;
create trigger set_school_account_identity_key
before insert or update of provider, base_url, provider_user_id
on public.linked_accounts
for each row execute function public.set_school_account_identity_key();

revoke execute on function public.set_school_account_identity_key()
  from public, anon, authenticated, service_role;

-- Store provider credentials and insert-or-refresh the canonical school link
-- in one transaction. This removes retry duplicates and prevents orphaned
-- encrypted secrets during concurrent links.
create or replace function public.upsert_school_link(
  p_user_id uuid,
  p_provider public.linked_account_provider,
  p_provider_user_id text,
  p_base_url text,
  p_display_name text,
  p_school_name text,
  p_payload jsonb,
  p_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_identity_key text;
  v_existing public.linked_accounts%rowtype;
  v_result public.linked_accounts%rowtype;
  v_secret_id uuid;
  v_old_secret_id uuid;
  v_had_existing boolean := false;
begin
  if p_provider not in ('bakalari'::public.linked_account_provider, 'eduPage'::public.linked_account_provider) then
    raise exception 'unsupported school provider' using errcode = '22023';
  end if;

  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  v_identity_key := public.school_account_identity_key(
    p_provider,
    p_base_url,
    p_provider_user_id
  );
  if v_identity_key is null then
    raise exception 'school identity is incomplete' using errcode = '22023';
  end if;

  select account.*
  into v_existing
  from public.linked_accounts as account
  where account.user_id = p_user_id
    and account.provider = p_provider
    and account.school_identity_key = v_identity_key
  for update;
  v_had_existing := found;

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

  if v_had_existing then
    v_old_secret_id := v_existing.secret_id;
    update public.linked_accounts as account
    set
      provider_user_id = p_provider_user_id,
      base_url = p_base_url,
      display_name = coalesce(nullif(p_display_name, ''), p_provider::text),
      school_name = p_school_name,
      status = 'active',
      secret_id = v_secret_id,
      failure_count = 0,
      action_required_reason = null,
      last_synced_at = now(),
      next_poll_at = now() + interval '15 minutes',
      updated_at = now()
    where account.id = v_existing.id
    returning account.* into v_result;
  else
    begin
      insert into public.linked_accounts (
        user_id,
        provider,
        provider_user_id,
        base_url,
        display_name,
        school_name,
        status,
        notifications_enabled,
        secret_id,
        last_synced_at,
        next_poll_at,
        school_identity_key
      ) values (
        p_user_id,
        p_provider,
        p_provider_user_id,
        p_base_url,
        coalesce(nullif(p_display_name, ''), p_provider::text),
        p_school_name,
        'active',
        true,
        v_secret_id,
        now(),
        now() + interval '15 minutes',
        v_identity_key
      )
      returning * into v_result;
    exception when unique_violation then
      select account.*
      into strict v_existing
      from public.linked_accounts as account
      where account.user_id = p_user_id
        and account.provider = p_provider
        and account.school_identity_key = v_identity_key
      for update;

      v_old_secret_id := v_existing.secret_id;
      update public.linked_accounts as account
      set
        provider_user_id = p_provider_user_id,
        base_url = p_base_url,
        display_name = coalesce(nullif(p_display_name, ''), p_provider::text),
        school_name = p_school_name,
        status = 'active',
        secret_id = v_secret_id,
        failure_count = 0,
        action_required_reason = null,
        last_synced_at = now(),
        next_poll_at = now() + interval '15 minutes',
        updated_at = now()
      where account.id = v_existing.id
      returning account.* into v_result;
    end;
  end if;

  if v_old_secret_id is not null and v_old_secret_id <> v_secret_id then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = v_old_secret_id
      and secret.user_id = p_user_id
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

  return to_jsonb(v_result);
end;
$$;

revoke execute on function public.upsert_school_link(
  uuid,
  public.linked_account_provider,
  text,
  text,
  text,
  text,
  jsonb,
  text
) from public, anon, authenticated;
grant execute on function public.upsert_school_link(
  uuid,
  public.linked_account_provider,
  text,
  text,
  text,
  text,
  jsonb,
  text
) to service_role;

-- Reconnection is identity preserving and always updates the explicitly owned
-- row. Credential rotation and cleanup share the same transaction, so a
-- failed refresh cannot strand a duplicate account or an orphaned secret.
create or replace function public.relink_owned_school_link(
  p_user_id uuid,
  p_account_id uuid,
  p_provider public.linked_account_provider,
  p_provider_user_id text,
  p_base_url text,
  p_display_name text,
  p_school_name text,
  p_payload jsonb,
  p_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existing public.linked_accounts%rowtype;
  v_result public.linked_accounts%rowtype;
  v_secret_id uuid;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  select account.*
  into v_existing
  from public.linked_accounts as account
  where account.id = p_account_id
    and account.user_id = p_user_id
    and account.provider in (
      'bakalari'::public.linked_account_provider,
      'eduPage'::public.linked_account_provider
    )
  for update;

  if not found then
    return null;
  end if;

  if v_existing.provider <> p_provider then
    raise exception 'provider does not match the owned account'
      using errcode = '22023';
  end if;

  if public.school_account_identity_key(
    p_provider,
    p_base_url,
    p_provider_user_id
  ) is null then
    raise exception 'school identity is incomplete' using errcode = '22023';
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

  update public.linked_accounts as account
  set
    provider_user_id = p_provider_user_id,
    base_url = p_base_url,
    display_name = coalesce(nullif(p_display_name, ''), account.display_name),
    school_name = p_school_name,
    status = 'active',
    secret_id = v_secret_id,
    failure_count = 0,
    action_required_reason = null,
    last_synced_at = now(),
    next_poll_at = now() + interval '15 minutes',
    updated_at = now()
  where account.id = v_existing.id
    and account.user_id = p_user_id
  returning account.* into v_result;

  if v_existing.secret_id is not null
    and v_existing.secret_id <> v_secret_id
  then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = v_existing.secret_id
      and secret.user_id = p_user_id
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

  return to_jsonb(v_result);
end;
$$;

revoke execute on function public.relink_owned_school_link(
  uuid,
  uuid,
  public.linked_account_provider,
  text,
  text,
  text,
  text,
  jsonb,
  text
) from public, anon, authenticated;
grant execute on function public.relink_owned_school_link(
  uuid,
  uuid,
  public.linked_account_provider,
  text,
  text,
  text,
  text,
  jsonb,
  text
) to service_role;

-- Unlink account, credential removal, and audit are one transaction. The audit
-- intentionally stores the removed UUID as metadata rather than a live FK.
create or replace function public.unlink_owned_account(
  p_user_id uuid,
  p_account_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_account public.linked_accounts%rowtype;
begin
  select account.*
  into v_account
  from public.linked_accounts as account
  where account.id = p_account_id
    and account.user_id = p_user_id
  for update;

  if not found then
    return null;
  end if;

  delete from public.linked_accounts as account
  where account.id = v_account.id
    and account.user_id = p_user_id;

  if v_account.secret_id is not null then
    delete from public.encrypted_provider_secrets as secret
    where secret.id = v_account.secret_id
      and secret.user_id = p_user_id
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

  insert into public.account_audit_logs (
    user_id,
    linked_account_id,
    event_name,
    metadata
  ) values (
    p_user_id,
    null,
    'unlinked_account',
    jsonb_build_object(
      'removedLinkedAccountID', v_account.id,
      'provider', v_account.provider,
      'displayName', v_account.display_name
    )
  );

  return jsonb_build_object(
    'id', v_account.id,
    'provider', v_account.provider,
    'removedSecret', v_account.secret_id is not null
  );
end;
$$;

revoke execute on function public.unlink_owned_account(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.unlink_owned_account(uuid, uuid)
  to service_role;

-- Every target device gets an independent durable terminal/retry state. Parent
-- events remain the scheduler/claim unit, so a worker owns all device outcomes
-- for a mark while device attempts can advance independently.
alter table public.new_mark_events
  add column if not exists delivery_targets_created_at timestamptz,
  add column if not exists quiet_delivery_key text;

create unique index if not exists new_mark_events_id_user_id_key
  on public.new_mark_events (id, user_id);

create unique index if not exists device_push_tokens_id_user_id_key
  on public.device_push_tokens (id, user_id);

create table if not exists public.new_mark_event_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event_id uuid not null,
  device_id uuid not null,
  apns_id uuid not null default gen_random_uuid(),
  delivery_due_at timestamptz not null default now(),
  delivery_attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_delivery_error text,
  accepted_at timestamptz,
  suppressed_at timestamptz,
  suppression_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint new_mark_event_deliveries_event_owner_fkey
    foreign key (event_id, user_id)
    references public.new_mark_events (id, user_id)
    on delete cascade,
  constraint new_mark_event_deliveries_device_owner_fkey
    foreign key (device_id, user_id)
    references public.device_push_tokens (id, user_id)
    on delete cascade,
  constraint new_mark_event_deliveries_event_device_unique
    unique (event_id, device_id),
  constraint new_mark_event_deliveries_attempt_range
    check (delivery_attempt_count between 0 and 5),
  constraint new_mark_event_deliveries_terminal_state
    check (accepted_at is null or suppressed_at is null)
);

create index if not exists new_mark_event_deliveries_due_idx
  on public.new_mark_event_deliveries (event_id, delivery_due_at)
  include (device_id, user_id)
  where accepted_at is null and suppressed_at is null;

-- The event-first index serves dispatcher rollups. This second index serves
-- the other side of the composite device FK and token invalidation cleanup.
create index if not exists new_mark_event_deliveries_device_idx
  on public.new_mark_event_deliveries (device_id, event_id)
  where accepted_at is null and suppressed_at is null;

alter table public.new_mark_event_deliveries enable row level security;

revoke all on table public.new_mark_event_deliveries
  from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.new_mark_event_deliveries
  to service_role;

create or replace function public.finalize_new_mark_event_deliveries(
  p_event_ids uuid[],
  p_claim_token uuid
)
returns setof public.new_mark_events
language sql
security invoker
set search_path = ''
as $$
  with delivery_rollup as (
    select
      delivery.event_id,
      count(*) filter (
        where delivery.accepted_at is null
          and delivery.suppressed_at is null
      ) as pending_count,
      count(*) filter (where delivery.accepted_at is not null) as accepted_count,
      min(delivery.delivery_due_at) filter (
        where delivery.accepted_at is null
          and delivery.suppressed_at is null
      ) as next_due_at,
      max(delivery.delivery_attempt_count) as maximum_attempt_count,
      max(delivery.last_attempt_at) as latest_attempt_at,
      (
        array_agg(
          delivery.last_delivery_error
          order by delivery.last_attempt_at desc nulls last
        ) filter (where delivery.last_delivery_error is not null)
      )[1] as latest_delivery_error
    from public.new_mark_event_deliveries as delivery
    where delivery.event_id = any (p_event_ids)
    group by delivery.event_id
  ), finalized as (
    update public.new_mark_events as event
    set
      delivered_at = case
        when rollup.pending_count = 0 and rollup.accepted_count > 0
          then coalesce(event.delivered_at, now())
        else event.delivered_at
      end,
      suppressed_at = case
        when rollup.pending_count = 0 and rollup.accepted_count = 0
          then coalesce(event.suppressed_at, now())
        else event.suppressed_at
      end,
      suppression_reason = case
        when rollup.pending_count = 0 and rollup.accepted_count = 0
          then coalesce(event.suppression_reason, 'all_device_deliveries_suppressed')
        else event.suppression_reason
      end,
      delivery_due_at = case
        when rollup.pending_count > 0 then rollup.next_due_at
        else event.delivery_due_at
      end,
      delivery_attempt_count = greatest(
        event.delivery_attempt_count,
        coalesce(rollup.maximum_attempt_count, 0)
      ),
      last_attempt_at = greatest(
        event.last_attempt_at,
        rollup.latest_attempt_at
      ),
      last_delivery_error = case
        when rollup.pending_count > 0 then rollup.latest_delivery_error
        when rollup.accepted_count > 0 then null
        else coalesce(rollup.latest_delivery_error, event.last_delivery_error)
      end,
      claim_token = null,
      claimed_at = null,
      claim_expires_at = null
    from delivery_rollup as rollup
    where event.id = rollup.event_id
      and event.claim_token = p_claim_token
    returning event.*
  )
  select finalized.*
  from finalized;
$$;

revoke execute on function public.finalize_new_mark_event_deliveries(uuid[], uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_new_mark_event_deliveries(uuid[], uuid)
  to service_role;

-- Quiet summaries are logical groups, not arbitrary claim pages. Serialize a
-- due user's quiet-window key with a transaction advisory lock, then claim all
-- currently due members of that group together. This prevents concurrent cron
-- workers or the ordinary row limit from splitting one summary payload.
create or replace function public.claim_new_mark_events(
  p_claim_token uuid,
  p_limit integer default 250,
  p_event_ids uuid[] default null
)
returns setof public.new_mark_events
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_claim_token is null then
    raise exception 'claim token is required' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'claim limit must be between 1 and 500' using errcode = '22023';
  end if;

  return query
  with eligible as materialized (
    select
      event.id,
      event.user_id,
      event.quiet_delivery_key,
      event.delivery_due_at,
      event.created_at
    from public.new_mark_events as event
    where event.delivered_at is null
      and event.suppressed_at is null
      and event.delivery_due_at <= now()
      and (
        event.claim_token is null
        or event.claim_expires_at <= now()
      )
      and (
        p_event_ids is null
        or event.id = any (p_event_ids)
      )
  ), quiet_candidates as (
    select
      candidate.user_id,
      candidate.quiet_delivery_key,
      min(candidate.delivery_due_at) as earliest_due_at,
      min(candidate.created_at) as earliest_created_at
    from eligible as candidate
    where candidate.quiet_delivery_key is not null
    group by candidate.user_id, candidate.quiet_delivery_key
    order by min(candidate.delivery_due_at), min(candidate.created_at)
    limit p_limit
  ), locked_quiet_groups as materialized (
    select candidate.user_id, candidate.quiet_delivery_key
    from quiet_candidates as candidate
    where pg_catalog.pg_try_advisory_xact_lock(
      pg_catalog.hashtextextended(
        candidate.user_id::text || pg_catalog.chr(31) ||
          candidate.quiet_delivery_key,
        0
      )
    )
  ), immediate_candidates as (
    select event.id
    from public.new_mark_events as event
    join eligible as candidate on candidate.id = event.id
    where candidate.quiet_delivery_key is null
    order by candidate.delivery_due_at, candidate.created_at
    limit p_limit
    for update of event skip locked
  ), quiet_event_candidates as (
    select event.id
    from public.new_mark_events as event
    join eligible as candidate on candidate.id = event.id
    join locked_quiet_groups as quiet_group
      on quiet_group.user_id = candidate.user_id
      and quiet_group.quiet_delivery_key = candidate.quiet_delivery_key
    for update of event skip locked
  ), candidate_ids as (
    select immediate.id from immediate_candidates as immediate
    union all
    select quiet.id from quiet_event_candidates as quiet
  ), claimed as (
    update public.new_mark_events as event
    set
      claim_token = p_claim_token,
      claimed_at = now(),
      claim_expires_at = now() + interval '5 minutes'
    from candidate_ids as candidate
    where event.id = candidate.id
    returning event.*
  )
  select claimed.*
  from claimed
  order by claimed.delivery_due_at, claimed.created_at;
end;
$$;

revoke execute on function public.claim_new_mark_events(uuid, integer, uuid[])
  from public, anon, authenticated;
grant execute on function public.claim_new_mark_events(uuid, integer, uuid[])
  to service_role;
