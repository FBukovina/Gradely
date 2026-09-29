-- The durable queue and the already-seen markers must share a transaction.
-- A failed/cancelled request cannot leave an unnotifiable fingerprint behind.
create or replace function public.record_polled_marks(
  p_account_id uuid,
  p_secret_id uuid,
  p_candidates jsonb,
  p_next_poll_at timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_account public.linked_accounts%rowtype;
  v_baseline boolean;
  v_event_ids jsonb;
begin
  if jsonb_typeof(p_candidates) is distinct from 'array' or p_next_poll_at is null then
    raise exception 'Invalid poll result' using errcode = '22023';
  end if;

  -- Relinking replaces the secret. An old in-flight poll must not complete the
  -- new session's baseline or overwrite its scheduling/status.
  select account.* into v_account
  from public.linked_accounts as account
  where account.id = p_account_id
    and account.secret_id = p_secret_id
    and account.status = 'active'
    and account.provider in ('bakalari', 'eduPage')
  for update;

  if not found then
    return jsonb_build_object('skipped', true, 'baseline', false, 'eventIDs', '[]'::jsonb);
  end if;
  v_baseline := v_account.last_polled_at is null;

  with candidates as materialized (
    select distinct on (candidate->>'fingerprint') candidate
    from jsonb_array_elements(p_candidates) with ordinality as items(candidate, ordinal)
    order by candidate->>'fingerprint', ordinal
  ), inserted_fingerprints as (
    insert into public.mark_fingerprints (
      user_id, linked_account_id, provider, subject_id,
      provider_mark_id, fingerprint, source
    )
    select v_account.user_id, v_account.id, v_account.provider,
      candidate->>'subjectID', candidate->>'providerMarkID',
      candidate->>'fingerprint', candidate->>'source'
    from candidates
    on conflict (linked_account_id, fingerprint) do nothing
    returning id, fingerprint
  ), inserted_events as (
    insert into public.new_mark_events (
      user_id, linked_account_id, fingerprint_id, provider, subject_id,
      subject_abbrev, subject_name, mark_text, notification_title, notification_body
    )
    select v_account.user_id, v_account.id, fingerprint.id, v_account.provider,
      candidate->>'subjectID', candidate->>'subjectAbbrev', candidate->>'subjectName',
      candidate->>'markText', 'New mark',
      (candidate->>'markText') || ' from ' || coalesce(
        nullif(candidate->>'subjectAbbrev', ''), nullif(candidate->>'subjectName', ''), 'school'
      )
    from inserted_fingerprints as fingerprint
    join candidates on candidate->>'fingerprint' = fingerprint.fingerprint
    where not v_baseline
    returning id
  )
  select coalesce(jsonb_agg(id), '[]'::jsonb) into v_event_ids from inserted_events;

  update public.linked_accounts
  set last_polled_at = now(), last_synced_at = now(), next_poll_at = p_next_poll_at,
      failure_count = 0, action_required_reason = null
  where id = v_account.id;

  return jsonb_build_object('skipped', false, 'baseline', v_baseline, 'eventIDs', v_event_ids);
end;
$$;

revoke execute on function public.record_polled_marks(uuid, uuid, jsonb, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.record_polled_marks(uuid, uuid, jsonb, timestamptz)
  to service_role;
