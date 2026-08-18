begin;

select plan(62);

select has_column(
  'public',
  'notification_preferences',
  'quiet_hours_time_zone',
  'notification preferences store an IANA time-zone identifier'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_quiet_start_range'
      and pg_get_constraintdef(oid) like '%BETWEEN 0 AND 1439%'
  ),
  'quiet-hours start minute is range constrained'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_quiet_end_range'
      and pg_get_constraintdef(oid) like '%BETWEEN 0 AND 1439%'
  ),
  'quiet-hours end minute is range constrained'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_quiet_timezone_iana'
      and convalidated
  ),
  'quiet-hours time zones are validated against PostgreSQL IANA data'
);

select ok(
  public.is_valid_iana_timezone('Europe/Prague'),
  'a canonical IANA time zone is accepted'
);

select ok(
  not public.is_valid_iana_timezone('Mars/Olympus'),
  'an unknown time zone is rejected at the database boundary'
);

select has_column('public', 'new_mark_events', 'delivery_due_at', 'events have a delivery schedule');
select has_column('public', 'new_mark_events', 'claim_token', 'events have an atomic claim token');
select has_column('public', 'new_mark_events', 'quiet_hours_deferred_at', 'events record quiet-hours deferral');
select has_column('public', 'new_mark_events', 'delivery_attempt_count', 'events track retry attempts');
select has_column('public', 'new_mark_events', 'last_delivery_error', 'events track their last error');
select has_column('public', 'new_mark_events', 'suppressed_at', 'events track suppression');

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'new_mark_events_delivery_due_idx'
      and indexdef ilike '%delivered_at is null%'
      and indexdef ilike '%suppressed_at is null%'
  ),
  'the due-event index is partial over unfinished unsuppressed events'
);

select has_function(
  'public',
  'claim_new_mark_events',
  array['uuid', 'integer', 'uuid[]'],
  'the queue claim function exists'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.claim_new_mark_events(uuid,integer,uuid[])'::regprocedure
  ),
  'the queue claim function is security invoker'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_new_mark_events(uuid,integer,uuid[])',
    'execute'
  ),
  'the service role can claim notification events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_new_mark_events(uuid,integer,uuid[])',
    'execute'
  ),
  'authenticated users cannot claim notification events'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.claim_new_mark_events(uuid,integer,uuid[])',
    'execute'
  ),
  'anonymous callers cannot claim notification events'
);

select ok(
  pg_get_functiondef('public.claim_new_mark_events(uuid,integer,uuid[])'::regprocedure)
    ilike '%for update%skip locked%',
  'concurrent workers skip already claimed rows'
);

select ok(
  pg_get_functiondef('public.claim_new_mark_events(uuid,integer,uuid[])'::regprocedure)
    ilike '%pg_try_advisory_xact_lock%',
  'a quiet-window group is serialized into one coherent summary claim'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'linked_accounts'
      and roles @> array['authenticated']::name[]
      and qual like '%auth.uid()%user_id%'
  ),
  'linked account reads remain owner isolated'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_preferences'
      and roles @> array['authenticated']::name[]
      and (
        qual like '%auth.uid()%user_id%'
        or with_check like '%auth.uid()%user_id%'
      )
  ),
  'notification preference mutations remain owner isolated'
);

select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'gradey-send-apns'
      and schedule = '* * * * *'
  ),
  'the deferred dispatcher runs every minute'
);

select has_column(
  'public',
  'linked_accounts',
  'school_identity_key',
  'school links have a canonical provider identity'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.linked_accounts'::regclass
      and conname = 'linked_accounts_school_identity_unique'
      and contype = 'u'
  ),
  'school identities are unique per Gradey user and provider'
);

select is(
  public.school_account_identity_key(
    'eduPage'::public.linked_account_provider,
    'https://school.edupage.org/',
    'child-1'
  ),
  public.school_account_identity_key(
    'eduPage'::public.linked_account_provider,
    'https://school.edupage.org',
    'child-1'
  ),
  'school identity ignores a trailing provider URL slash'
);

select isnt(
  public.school_account_identity_key(
    'eduPage'::public.linked_account_provider,
    'https://school.edupage.org',
    'child-1'
  ),
  public.school_account_identity_key(
    'eduPage'::public.linked_account_provider,
    'https://school.edupage.org',
    'child-2'
  ),
  'different EduPage children keep distinct school identities'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.linked_accounts'::regclass
      and tgname = 'set_school_account_identity_key'
      and not tgisinternal
  ),
  'school identity is recomputed for every identity-changing write'
);

select has_function(
  'public',
  'upsert_school_link',
  array['uuid', 'linked_account_provider', 'text', 'text', 'text', 'text', 'jsonb', 'text'],
  'transactional school-link upsert exists'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.upsert_school_link(uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'execute'
  ),
  'only the service-backed endpoint can upsert school links'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.upsert_school_link(uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'execute'
  ),
  'authenticated clients cannot call the school-link upsert directly'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.upsert_school_link(uuid,public.linked_account_provider,text,text,text,text,jsonb,text)'::regprocedure
  ),
  'school-link upsert executes with the restricted service caller privileges'
);

select has_function(
  'public',
  'relink_owned_school_link',
  array['uuid', 'uuid', 'linked_account_provider', 'text', 'text', 'text', 'text', 'jsonb', 'text'],
  'transactional owned-school reconnect exists'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.relink_owned_school_link(uuid,uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'execute'
  ),
  'the service-backed endpoint can reconnect an owned school row in place'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.relink_owned_school_link(uuid,uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'execute'
  ),
  'authenticated clients cannot invoke credential rotation directly'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.relink_owned_school_link(uuid,uuid,public.linked_account_provider,text,text,text,text,jsonb,text)'::regprocedure
  ),
  'school reconnect is security invoker'
);

select ok(
  pg_get_functiondef(
    'public.relink_owned_school_link(uuid,uuid,public.linked_account_provider,text,text,text,text,jsonb,text)'::regprocedure
  ) ilike '%account.id = p_account_id%account.user_id = p_user_id%',
  'school reconnect rechecks ownership while locking the requested row'
);

select has_function(
  'public',
  'unlink_owned_account',
  array['uuid', 'uuid'],
  'transactional owned-account unlink exists'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.unlink_owned_account(uuid,uuid)',
    'execute'
  ),
  'the service-backed endpoint can unlink an owned account'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.unlink_owned_account(uuid,uuid)',
    'execute'
  ),
  'authenticated clients cannot call owned-account unlink directly'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.unlink_owned_account(uuid,uuid)'::regprocedure
  ),
  'owned-account unlink is security invoker'
);

select ok(
  pg_get_functiondef('public.unlink_owned_account(uuid,uuid)'::regprocedure)
      ilike '%account.id = p_account_id%account.user_id = p_user_id%'
    and pg_get_functiondef('public.unlink_owned_account(uuid,uuid)'::regprocedure)
      ilike '%''removedLinkedAccountID'', v_account.id%',
  'unlink verifies ownership and records the removed UUID only as audit metadata'
);

select has_column(
  'public',
  'new_mark_events',
  'delivery_targets_created_at',
  'events record when their target-device set was sealed'
);

select has_column(
  'public',
  'new_mark_events',
  'quiet_delivery_key',
  'events persist a stable quiet-window delivery identity'
);

select has_table(
  'public',
  'new_mark_event_deliveries',
  'per-device notification deliveries are durable'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.new_mark_event_deliveries'::regclass
  ),
  'per-device delivery rows have RLS enabled'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.new_mark_event_deliveries',
    'select'
  ),
  'authenticated clients cannot inspect internal device-delivery state'
);

select ok(
  has_table_privilege(
    'service_role',
    'public.new_mark_event_deliveries',
    'select'
  ),
  'the service role can inspect internal device-delivery state'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'new_mark_event_deliveries_due_idx'
      and indexdef ilike '%accepted_at is null%'
      and indexdef ilike '%suppressed_at is null%'
  ),
  'unfinished event-device deliveries have a partial due index'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'new_mark_event_deliveries_device_idx'
  ),
  'the device side of the composite delivery foreign key is indexed'
);

select has_column(
  'public',
  'new_mark_event_deliveries',
  'apns_id',
  'each target persists its APNs request identity'
);

select has_column(
  'public',
  'new_mark_event_deliveries',
  'accepted_at',
  'each target records APNs acceptance independently'
);

select has_column(
  'public',
  'new_mark_event_deliveries',
  'suppressed_at',
  'each target records terminal suppression independently'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.new_mark_event_deliveries'::regclass
      and conname = 'new_mark_event_deliveries_event_device_unique'
      and contype = 'u'
  ),
  'retries cannot create a duplicate event/device target'
);

select ok(
  (
    select count(*)
    from pg_constraint
    where conrelid = 'public.new_mark_event_deliveries'::regclass
      and conname in (
        'new_mark_event_deliveries_event_owner_fkey',
        'new_mark_event_deliveries_device_owner_fkey'
      )
      and contype = 'f'
  ) = 2,
  'event and device composite foreign keys enforce matching ownership'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.new_mark_event_deliveries'::regclass
      and conname = 'new_mark_event_deliveries_attempt_range'
      and pg_get_constraintdef(oid) ilike '%between 0 and 5%'
  ),
  'each device retry counter is independently bounded at five attempts'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.new_mark_event_deliveries'::regclass
      and conname = 'new_mark_event_deliveries_terminal_state'
  ),
  'a target cannot be both APNs-accepted and suppressed'
);

select has_function(
  'public',
  'finalize_new_mark_event_deliveries',
  array['uuid[]', 'uuid'],
  'the event-delivery finalizer exists'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.finalize_new_mark_event_deliveries(uuid[],uuid)'::regprocedure
  ),
  'the event-delivery finalizer is security invoker'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_new_mark_event_deliveries(uuid[],uuid)',
    'execute'
  ),
  'the service role can finalize device-delivery rollups'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.finalize_new_mark_event_deliveries(uuid[],uuid)',
    'execute'
  ),
  'authenticated clients cannot finalize internal device-delivery state'
);

select ok(
  pg_get_functiondef(
    'public.finalize_new_mark_event_deliveries(uuid[],uuid)'::regprocedure
  ) ilike '%pending_count%accepted_count%next_due_at%',
  'parent completion retains retries until every device target is terminal'
);

select * from finish();
rollback;
