-- Canonical, cross-device notification preferences.
alter table public.notification_preferences
  add column if not exists quiet_hours_time_zone text not null default 'Europe/Prague';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_preferences_quiet_start_range'
      and conrelid = 'public.notification_preferences'::regclass
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_quiet_start_range
      check (quiet_hours_start_minute between 0 and 1439);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_preferences_quiet_end_range'
      and conrelid = 'public.notification_preferences'::regclass
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_quiet_end_range
      check (quiet_hours_end_minute between 0 and 1439);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'notification_preferences_quiet_timezone_length'
      and conrelid = 'public.notification_preferences'::regclass
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_quiet_timezone_length
      check (
        length(quiet_hours_time_zone) between 1 and 128
        and quiet_hours_time_zone !~ '[[:cntrl:]]'
      );
  end if;
end
$$;

-- new_mark_events is the durable delivery queue. Keeping the queue beside the
-- immutable mark event avoids a second store while still making claims and
-- retries observable and recoverable.
alter table public.new_mark_events
  add column if not exists delivery_due_at timestamptz not null default now(),
  add column if not exists claim_token uuid,
  add column if not exists claimed_at timestamptz,
  add column if not exists claim_expires_at timestamptz,
  add column if not exists quiet_hours_deferred_at timestamptz,
  add column if not exists delivery_attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists last_delivery_error text,
  add column if not exists suppressed_at timestamptz,
  add column if not exists suppression_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'new_mark_events_delivery_attempt_range'
      and conrelid = 'public.new_mark_events'::regclass
  ) then
    alter table public.new_mark_events
      add constraint new_mark_events_delivery_attempt_range
      check (delivery_attempt_count between 0 and 5);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'new_mark_events_claim_consistency'
      and conrelid = 'public.new_mark_events'::regclass
  ) then
    alter table public.new_mark_events
      add constraint new_mark_events_claim_consistency
      check (
        (claim_token is null and claimed_at is null and claim_expires_at is null)
        or
        (claim_token is not null and claimed_at is not null and claim_expires_at is not null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'new_mark_events_terminal_state_consistency'
      and conrelid = 'public.new_mark_events'::regclass
  ) then
    alter table public.new_mark_events
      add constraint new_mark_events_terminal_state_consistency
      check (delivered_at is null or suppressed_at is null);
  end if;
end
$$;

create index if not exists new_mark_events_delivery_due_idx
  on public.new_mark_events (delivery_due_at, created_at)
  include (user_id, linked_account_id)
  where delivered_at is null and suppressed_at is null;

-- Prevent a burst of historical notifications when this dispatcher first
-- deploys. New events created after the migration retain the default due time.
update public.new_mark_events
set
  suppressed_at = now(),
  suppression_reason = 'pre_migration_event',
  claim_token = null,
  claimed_at = null,
  claim_expires_at = null
where delivered_at is null
  and suppressed_at is null;

-- Atomic, non-blocking queue claim. This remains SECURITY INVOKER and the
-- service role is the only role allowed to execute it.
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
  with candidates as (
    select event.id
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
    order by event.delivery_due_at, event.created_at
    limit p_limit
    for update skip locked
  ), claimed as (
    update public.new_mark_events as event
    set
      claim_token = p_claim_token,
      claimed_at = now(),
      claim_expires_at = now() + interval '5 minutes'
    from candidates
    where event.id = candidates.id
    returning event.*
  )
  select claimed.* from claimed
  order by claimed.delivery_due_at, claimed.created_at;
end;
$$;

revoke execute on function public.claim_new_mark_events(uuid, integer, uuid[])
  from public, anon, authenticated;
grant execute on function public.claim_new_mark_events(uuid, integer, uuid[])
  to service_role;

-- The dispatcher is intentionally separate from provider polling. Immediate
-- calls can claim just-created event IDs; this minute job recovers deferred and
-- retryable work.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'gradey-send-apns') then
    perform cron.unschedule('gradey-send-apns');
  end if;
end
$$;

select cron.schedule(
  'gradey-send-apns',
  '* * * * *',
  $$
  select
    net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'gradey_project_url'
      ) || '/functions/v1/send-apns',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'gradey_cron_secret'
        )
      ),
      body := '{"source":"cron"}'::jsonb
    );
  $$
);
