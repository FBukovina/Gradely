-- Uses real pgcrypto and transactions; fixtures contain synthetic secrets only.
begin;
select '1..1';
do $$
declare
  v_user uuid := gen_random_uuid();
  v_other_user uuid := gen_random_uuid();
  v_key text := 'synthetic-test-encryption-key-at-least-32-characters';
  v_payload jsonb := '{"provider":"bakalari","baseURL":"https://school.example/","accessToken":"access","refreshToken":"refresh","pollingSessionEstablishedAt":"2026-09-07T12:00:00Z","username":"student","password":"flat-secret","bakalari":{"username":"student","password":"nested-secret"},"unexpected":{"password":"secret"}}';
  v_secret uuid;
  v_legacy uuid;
  v_apns uuid;
  v_account jsonb;
  v_relinked jsonb;
  v_raw jsonb;
  v_clean jsonb;
  v_counts jsonb;
  v_signature text;
begin
  insert into auth.users(id, email, raw_user_meta_data) values
    (v_user, 'privacy-fixture@example.invalid', '{}'::jsonb),
    (v_other_user, 'privacy-other@example.invalid', '{}'::jsonb);

  execute 'set local role service_role';

  v_clean := public.sanitize_provider_secret(v_payload);
  assert v_clean = '{"provider":"bakalari","baseURL":"https://school.example/","accessToken":"access","refreshToken":"refresh","pollingSessionEstablishedAt":"2026-09-07T12:00:00Z"}'::jsonb, 'Bakalari allowlist must discard flat, nested, and unknown credentials';
  assert public.sanitize_provider_secret('{"provider":"bakalari","accessToken":{"password":"hidden"}}') = '{"provider":"bakalari"}'::jsonb, 'allowed scalar fields must not contain objects';

  v_raw := public.sanitize_provider_secret('{"provider":"eduPage","eduPage":{"sessionID":"cookie","username":"parent","password":"secret","gsecHash":"hash","userID":"parent-id","activeStudent":{"id":"child","fullName":"Test Child","password":"secret"},"linkedStudents":[{"id":"child","fullName":"Test Child","password":"secret"}],"subjects":[{"id":"math","name":"Math","shortName":"M","password":"secret"}]}}');
  assert v_raw::text not ilike '%password%', 'EduPage nested passwords must be removed';
  assert v_raw->'eduPage'->>'sessionID' = 'cookie', 'EduPage session must survive';
  assert v_raw->'eduPage'->'activeStudent'->>'id' = 'child', 'selected child must survive';
  assert jsonb_array_length(v_raw->'eduPage'->'subjects') = 1, 'EduPage subject context must survive';
  assert public.sanitize_provider_secret('{"provider":"stravaCZ","serviceURL":"https://canteen.example/","sessionID":"cookie","canteenNumber":"001","username":"student","password":"secret"}') = '{"provider":"stravaCZ","serviceURL":"https://canteen.example/","sessionID":"cookie","canteenNumber":"001","username":"student"}'::jsonb, 'canteen session must survive';

  -- Each actual writer is checked against decrypted ciphertext, bypassing readers.
  v_secret := public.store_provider_secret(v_user, v_payload, v_key);
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = v_secret;
  assert v_raw = v_clean, 'store must sanitize before encryption';
  assert not public.update_provider_secret(v_secret, v_other_user, v_payload, v_key), 'rotation must enforce secret ownership';
  assert public.update_provider_secret(v_secret, v_user, v_payload || '{"accessToken":"rotated"}'::jsonb, v_key), 'owner rotation must succeed';
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = v_secret;
  assert v_raw = v_clean || '{"accessToken":"rotated"}'::jsonb, 'rotation must sanitize before encryption';

  v_account := public.upsert_school_link(v_user, 'bakalari', 'student', 'https://school.example/', 'Test Student', 'Test School', v_payload, v_key);
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = (v_account->>'secret_id')::uuid;
  assert v_raw = v_clean, 'link must sanitize before encryption';
  update public.linked_accounts set notifications_enabled = false where id = (v_account->>'id')::uuid;
  v_relinked := public.relink_owned_school_link(v_user, (v_account->>'id')::uuid, 'bakalari', 'student', 'https://school.example/', 'Test Student', 'Test School', v_payload, v_key);
  assert v_relinked->>'id' = v_account->>'id', 'reconnect must preserve the account ID';
  assert v_relinked->>'notifications_enabled' = 'false', 'reconnect must preserve notification preferences';
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = (v_relinked->>'secret_id')::uuid;
  assert v_raw = v_clean, 'reconnect must sanitize before encryption';

  -- An orphaned legacy row must be cleaned even if no poll or activation reads it.
  insert into public.encrypted_provider_secrets(user_id, ciphertext)
  values (v_user, extensions.pgp_sym_encrypt(v_payload::text, v_key)) returning id into v_legacy;
  assert public.read_provider_secret(v_legacy, v_key) = v_clean, 'legacy reads must not return passwords';
  v_apns := public.store_provider_secret(v_user, '{"token":"synthetic-apns-token"}', v_key);
  assert public.read_provider_secret(v_apns, v_key) = '{"token":"synthetic-apns-token"}'::jsonb, 'shared APNs storage must preserve the device token';

  v_counts := public.purge_provider_passwords(v_key);
  assert (v_counts->>'needing_cleanup')::integer >= 1 and (v_counts->>'updated')::integer = 0, 'default cleanup must be dry-run';
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = v_legacy;
  assert v_raw = v_payload, 'dry-run must not alter ciphertext';
  v_counts := public.purge_provider_passwords(v_key, true);
  assert (v_counts->>'updated')::integer >= 1, 'apply must rewrite orphaned legacy rows';
  select extensions.pgp_sym_decrypt(ciphertext, v_key)::jsonb into v_raw from public.encrypted_provider_secrets where id = v_legacy;
  assert v_raw = v_clean, 'purge must actually remove credentials from ciphertext';
  assert (public.purge_provider_passwords(v_key)->>'needing_cleanup')::integer = 0, 'verification must find no remaining legacy payloads';
  assert (public.purge_provider_passwords(v_key, true)->>'updated')::integer = 0, 'cleanup must be idempotent';
  assert public.read_provider_secret(v_apns, v_key)->>'token' = 'synthetic-apns-token', 'cleanup must preserve APNs tokens';
  assert exists(select 1 from public.linked_accounts where id = (v_account->>'id')::uuid), 'cleanup must preserve school links';

  foreach v_signature in array array[
    'public.store_provider_secret(uuid,jsonb,text)', 'public.read_provider_secret(uuid,text)',
    'public.update_provider_secret(uuid,uuid,jsonb,text)',
    'public.upsert_school_link(uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'public.relink_owned_school_link(uuid,uuid,public.linked_account_provider,text,text,text,text,jsonb,text)',
    'public.sanitize_provider_secret(jsonb)', 'public.provider_secret_strings(jsonb,text[])',
    'public.purge_provider_passwords(text,boolean)'
  ] loop
    assert not has_function_privilege('anon', v_signature, 'execute'), 'anonymous role must not call privileged secret functions';
    assert not has_function_privilege('authenticated', v_signature, 'execute'), 'users must not call privileged secret functions';
    assert has_function_privilege('service_role', v_signature, 'execute'), 'service role must retain the secret functions';
  end loop;
end;
$$;
select 'ok 1 - password boundary, encrypted writers, legacy purge, account preservation, and permissions';
rollback;
