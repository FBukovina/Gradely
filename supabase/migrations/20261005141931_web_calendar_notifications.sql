-- Additive web delivery: never claims or updates the native APNs queue.
create table public.web_calendar_feeds (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token_hash text unique not null check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
alter table public.web_calendar_feeds enable row level security;
revoke all on public.web_calendar_feeds from anon, authenticated;
grant all on public.web_calendar_feeds to service_role;

create table public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint_hash text unique not null,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  planner_reminders boolean not null default true,
  reminder_minute integer not null default 1080 check(reminder_minute between 0 and 1439),
  time_zone text not null default 'Europe/Prague',
  created_at timestamptz not null default now()
);
alter table public.web_push_subscriptions enable row level security;
revoke all on public.web_push_subscriptions from anon, authenticated;
grant all on public.web_push_subscriptions to service_role;

create table public.web_push_jobs (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.web_push_subscriptions(id) on delete cascade,
  event_id uuid references public.new_mark_events(id) on delete cascade,
  event_key text not null,
  kind text not null check (kind in ('mark','planner')),
  status text not null default 'queued' check(status in ('queued','claimed','sent','failed')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  claimed_until timestamptz,
  unique(subscription_id, event_key)
);
create index web_push_jobs_due on public.web_push_jobs(available_at) where status in ('queued','claimed');
alter table public.web_push_jobs enable row level security;
revoke all on public.web_push_jobs from anon, authenticated;
grant all on public.web_push_jobs to service_role;

create function public.enqueue_web_mark() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.web_push_jobs(subscription_id,event_id,event_key,kind)
    select s.id, new.id, 'mark:' || new.id, 'mark' from public.web_push_subscriptions s where s.user_id = new.user_id
    on conflict do nothing;
  return new;
end; $$;
revoke all on function public.enqueue_web_mark() from public,anon,authenticated;
create trigger enqueue_web_mark after insert on public.new_mark_events for each row execute function public.enqueue_web_mark();

create function public.enqueue_web_planner_reminders() returns void language sql security invoker set search_path = '' as $$
  insert into public.web_push_jobs(subscription_id,event_key,kind)
  select s.id, 'planner:' || to_char(now() at time zone s.time_zone,'YYYY-MM-DD'), 'planner'
  from public.web_push_subscriptions s
  where s.planner_reminders
    and extract(hour from now() at time zone s.time_zone)*60 + extract(minute from now() at time zone s.time_zone) >= s.reminder_minute
    and exists(select 1 from public.planner_items p where p.owner_id=s.user_id and p.item->>'deletedAt' is null
      and coalesce((p.item->>'isCompleted')::boolean,false)=false
      and (coalesce(p.item->>'dueDate',p.item#>>'{lesson,start}',p.item->>'linkedDate')::timestamptz at time zone s.time_zone)::date
        between (now() at time zone s.time_zone)::date and (now() at time zone s.time_zone)::date+1)
  on conflict do nothing;
$$;
revoke all on function public.enqueue_web_planner_reminders() from public,anon,authenticated;
grant execute on function public.enqueue_web_planner_reminders() to service_role;

create function public.claim_web_push_jobs(p_limit integer default 50) returns setof public.web_push_jobs language sql security invoker set search_path = '' as $$
  with due as(select id from public.web_push_jobs where available_at<=now() and attempts<8
    and (status='queued' or (status='claimed' and claimed_until<now()))
    order by available_at for update skip locked limit least(greatest(p_limit,1),100))
  update public.web_push_jobs j set status='claimed',claimed_until=now()+interval '5 minutes',attempts=attempts+1
  from due where j.id=due.id returning j.*;
$$;
revoke all on function public.claim_web_push_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_web_push_jobs(integer) to service_role;
