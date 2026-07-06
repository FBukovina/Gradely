alter table profiles
  add column if not exists active_school_account_id uuid references linked_accounts(id) on delete set null;

create type grade_history_event_type as enum ('baseline', 'changed');

create table grade_history_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  linked_account_id uuid not null references linked_accounts(id) on delete cascade,
  provider linked_account_provider not null,
  subject_id text not null,
  subject_abbrev text,
  subject_name text,
  average_value numeric,
  mark_count integer not null default 0,
  average_delta numeric,
  mark_count_delta integer not null default 0,
  event_type grade_history_event_type not null,
  captured_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index grade_history_events_account_idx
  on grade_history_events(linked_account_id, captured_at desc);

create index grade_history_events_subject_idx
  on grade_history_events(linked_account_id, subject_id, captured_at desc);

alter table grade_history_events enable row level security;

create policy "grade history owner read"
  on grade_history_events for select
  using (auth.uid() = user_id);
