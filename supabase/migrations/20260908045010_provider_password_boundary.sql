-- Apply the storage/read boundary before deploying token-only Edge Functions.
-- Existing ciphertext is not erased by changing readers. Run the separately
-- approved purge_provider_passwords operation, then verify with its dry run.

create or replace function public.provider_secret_strings(p_value jsonb, p_keys text[])
returns jsonb language sql immutable security invoker set search_path = ''
as $$
  select coalesce(jsonb_object_agg(item.key, item.value), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(p_value) = 'object' then p_value else '{}'::jsonb end) as item
  where item.key = any(p_keys) and jsonb_typeof(item.value) = 'string';
$$;

create or replace function public.sanitize_provider_secret(p_payload jsonb)
returns jsonb language plpgsql immutable security invoker set search_path = ''
as $$
declare
  v_result jsonb;
  v_edu jsonb;
  v_students jsonb;
  v_subjects jsonb;
  v_student_keys text[] := array['id', 'fullName', 'classID', 'className'];
begin
  -- The same encrypted table also stores APNs tokens. Preserve those exactly.
  if p_payload->>'provider' is null and jsonb_typeof(p_payload->'token') = 'string' then
    return public.provider_secret_strings(p_payload, array['token']);
  end if;
  if p_payload->>'provider' = 'stravaCZ' then
    return public.provider_secret_strings(p_payload,
      array['provider', 'serviceURL', 'sessionID', 'canteenNumber', 'username']);
  end if;
  v_result := public.provider_secret_strings(p_payload,
    array['provider', 'baseURL', 'accessToken', 'refreshToken', 'tokenType', 'expiresAt', 'pollingSessionEstablishedAt']);
  if p_payload->>'provider' = 'eduPage' then
    v_edu := public.provider_secret_strings(p_payload->'eduPage', array['sessionID', 'username', 'gsecHash', 'userID']);
    if p_payload->'eduPage'->'activeStudent' is not null and p_payload->'eduPage'->'activeStudent' <> 'null'::jsonb then
      v_edu := v_edu || jsonb_build_object('activeStudent', public.provider_secret_strings(p_payload->'eduPage'->'activeStudent', v_student_keys));
    end if;
    select coalesce(jsonb_agg(public.provider_secret_strings(value, v_student_keys) order by ordinality), '[]'::jsonb)
    into v_students
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'eduPage'->'linkedStudents') = 'array'
      then p_payload->'eduPage'->'linkedStudents' else '[]'::jsonb end) with ordinality;
    select coalesce(jsonb_agg(public.provider_secret_strings(value, array['id', 'name', 'shortName']) order by ordinality), '[]'::jsonb)
    into v_subjects
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'eduPage'->'subjects') = 'array'
      then p_payload->'eduPage'->'subjects' else '[]'::jsonb end) with ordinality;
    v_result := v_result || jsonb_build_object('eduPage', v_edu || jsonb_build_object('linkedStudents', v_students, 'subjects', v_subjects));
  end if;
  return v_result;
end;
$$;

revoke execute on function public.provider_secret_strings(jsonb, text[]) from public, anon, authenticated;
revoke execute on function public.sanitize_provider_secret(jsonb) from public, anon, authenticated;
grant execute on function public.provider_secret_strings(jsonb, text[]) to service_role;
grant execute on function public.sanitize_provider_secret(jsonb) to service_role;

-- Dry-run by default, aggregate counts only. Runs with service-role privileges,
-- locks each row before rewriting, and includes inactive and orphaned secrets.
-- A bad key aborts the transaction; no plaintext or per-account data is returned.
create or replace function public.purge_provider_passwords(p_key text, p_apply boolean default false)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare
  v_row record;
  v_original jsonb;
  v_clean jsonb;
  v_scanned integer := 0;
  v_dirty integer := 0;
  v_updated integer := 0;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;
  for v_row in select id, ciphertext from public.encrypted_provider_secrets order by id for update loop
    v_scanned := v_scanned + 1;
    v_original := extensions.pgp_sym_decrypt(v_row.ciphertext, p_key)::jsonb;
    v_clean := public.sanitize_provider_secret(v_original);
    if v_clean is distinct from v_original then
      v_dirty := v_dirty + 1;
      if p_apply then
        update public.encrypted_provider_secrets
        set ciphertext = extensions.pgp_sym_encrypt(v_clean::text, p_key, 'compress-algo=1,cipher-algo=aes256'),
            rotated_at = now()
        where id = v_row.id;
        v_updated := v_updated + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'needing_cleanup', v_dirty, 'updated', v_updated);
end;
$$;

revoke execute on function public.purge_provider_passwords(text, boolean) from public, anon, authenticated;
grant execute on function public.purge_provider_passwords(text, boolean) to service_role;

-- Preserve existing ownership, transaction, and function permissions.
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
      public.sanitize_provider_secret(p_payload)::text,
      p_key,
      'compress-algo=1,cipher-algo=aes256'
    )
  )
  returning id into v_secret_id;

  return v_secret_id;
end;
$$;

-- Preserve existing ownership, transaction, and function permissions.
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

  return public.sanitize_provider_secret(v_payload::jsonb);
end;
$$;

-- Preserve existing ownership, transaction, and function permissions.
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
      public.sanitize_provider_secret(p_payload)::text,
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

-- Preserve existing ownership, transaction, and function permissions.
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
      public.sanitize_provider_secret(p_payload)::text,
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

-- Preserve existing ownership, transaction, and function permissions.
create or replace function public.update_provider_secret(
  p_secret_id uuid,
  p_user_id uuid,
  p_payload jsonb,
  p_key text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'PROVIDER_SECRET_KEY must be set and at least 32 characters';
  end if;

  update public.encrypted_provider_secrets as secret
  set ciphertext = extensions.pgp_sym_encrypt(
    public.sanitize_provider_secret(p_payload)::text,
    p_key,
    'compress-algo=1,cipher-algo=aes256'
  ),
      rotated_at = now()
  where secret.id = p_secret_id
    and secret.user_id = p_user_id;

  return found;
end;
$$;

-- Production may predate the refresh-writer migration. A newly created function
-- must not inherit PostgreSQL's default PUBLIC execution permission.
revoke execute on function public.update_provider_secret(uuid, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.update_provider_secret(uuid, uuid, jsonb, text) to service_role;
