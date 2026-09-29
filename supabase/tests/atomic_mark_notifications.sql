-- Synthetic fixtures only. The transaction rolls back every row.
begin;
select '1..1';
do $$
declare
  v_user uuid := gen_random_uuid();
  v_account uuid := gen_random_uuid();
  v_secret uuid := gen_random_uuid();
  v_result jsonb;
  v_due timestamptz := now() + interval '15 minutes';
  v_before_poll timestamptz;
  v_candidates jsonb := '[{"fingerprint":"fixture:baseline","subjectID":"MAT","providerMarkID":"baseline","source":"provider_id","subjectAbbrev":"M","subjectName":"Mathematics","markText":"1"}]';
  v_new jsonb := '[{"fingerprint":"fixture:new-1","subjectID":"MAT","providerMarkID":"new-1","source":"provider_id","subjectAbbrev":"M","markText":"2"},{"fingerprint":"fixture:new-2","subjectID":"CJ","providerMarkID":"new-2","source":"provider_id","subjectName":"Czech","markText":"1"}]';
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values (v_user, 'atomic-poll@example.invalid', '{}');
  insert into public.encrypted_provider_secrets(id, user_id, ciphertext)
  values (v_secret, v_user, '\x00');
  insert into public.linked_accounts(id, user_id, provider, provider_user_id, base_url, display_name, secret_id)
  values (v_account, v_user, 'bakalari', 'atomic-fixture', 'https://school.example/', 'Fixture', v_secret);

  execute 'set local role service_role';
  v_result := public.record_polled_marks(v_account, v_secret, v_candidates, v_due);
  assert (v_result->>'baseline')::boolean, 'first poll must be a baseline';
  assert jsonb_array_length(v_result->'eventIDs') = 0, 'baseline must not notify old marks';
  assert (select count(*) = 1 from public.mark_fingerprints where linked_account_id = v_account), 'baseline fingerprints must persist';
  assert (select last_polled_at is not null and next_poll_at = v_due from public.linked_accounts where id = v_account), 'baseline state must commit with fingerprints';

  v_result := public.record_polled_marks(v_account, v_secret, v_candidates || v_new || v_new, v_due);
  assert not (v_result->>'baseline')::boolean, 'later poll must notify';
  assert jsonb_array_length(v_result->'eventIDs') = 2, 'each distinct new mark must create exactly one event';
  assert (select count(*) = 2 from public.new_mark_events where linked_account_id = v_account), 'events must persist';
  assert (select bool_and(notification_body in ('2 from M', '1 from Czech')) from public.new_mark_events where linked_account_id = v_account), 'copy must preserve subject fallbacks';
  v_result := public.record_polled_marks(v_account, v_secret, v_candidates || v_new, v_due);
  assert jsonb_array_length(v_result->'eventIDs') = 0, 'retry after an ambiguous response must not duplicate events';

  -- Force the event insert to fail after the fingerprint insert. A separate
  -- HTTP cleanup could never guarantee this rollback on process termination.
  select last_polled_at into v_before_poll from public.linked_accounts where id = v_account;
  begin
    perform public.record_polled_marks(v_account, v_secret,
      '[{"fingerprint":"fixture:retry","subjectID":"MAT","source":"provider_id"}]', v_due + interval '1 hour');
    raise exception 'Expected event constraint failure';
  exception when not_null_violation then null;
  end;
  assert not exists(select 1 from public.mark_fingerprints where linked_account_id = v_account and fingerprint = 'fixture:retry'), 'failed event must roll back its fingerprint';
  assert (select last_polled_at = v_before_poll and next_poll_at = v_due from public.linked_accounts where id = v_account), 'failed recording must preserve poll state';
  v_result := public.record_polled_marks(v_account, v_secret,
    '[{"fingerprint":"fixture:retry","subjectID":"MAT","source":"provider_id","markText":"3"}]', v_due);
  assert jsonb_array_length(v_result->'eventIDs') = 1, 'next poll must recover the failed notification';

  v_result := public.record_polled_marks(v_account, gen_random_uuid(),
    '[{"fingerprint":"fixture:stale","subjectID":"MAT","source":"provider_id","markText":"4"}]', v_due);
  assert (v_result->>'skipped')::boolean, 'relinked session must reject stale poll results';
  assert not exists(select 1 from public.mark_fingerprints where fingerprint = 'fixture:stale' and linked_account_id = v_account), 'stale poll must not mark anything as seen';
  update public.linked_accounts set status = 'paused' where id = v_account;
  v_result := public.record_polled_marks(v_account, v_secret, '[]', v_due);
  assert (v_result->>'skipped')::boolean, 'paused account must not be changed';

  assert not has_function_privilege('anon', 'public.record_polled_marks(uuid,uuid,jsonb,timestamptz)', 'execute'), 'anonymous callers must be denied';
  assert not has_function_privilege('authenticated', 'public.record_polled_marks(uuid,uuid,jsonb,timestamptz)', 'execute'), 'app users must be denied';
  assert has_function_privilege('service_role', 'public.record_polled_marks(uuid,uuid,jsonb,timestamptz)', 'execute'), 'poller must be permitted';
end;
$$;
select 'ok 1 - atomic baseline/events, duplicate retries, failure rollback/recovery, stale sessions, and permissions';
rollback;
