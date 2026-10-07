-- Reconnection must preserve the provider-side student identity. Keep this
-- check in the transactional RPC as defense in depth: the service-backed Edge
-- Function validates the same invariant, but no caller of this privileged RPC
-- may rotate credentials for a blank or different provider user.
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
  v_existing_provider_user_id text;
  v_candidate_provider_user_id text;
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

  v_existing_provider_user_id := nullif(
    pg_catalog.btrim(v_existing.provider_user_id),
    ''
  );
  v_candidate_provider_user_id := nullif(
    pg_catalog.btrim(p_provider_user_id),
    ''
  );

  if v_existing_provider_user_id is null
    or v_candidate_provider_user_id is null
    or v_existing_provider_user_id <> v_candidate_provider_user_id
  then
    raise exception 'provider user does not match the owned account'
      using errcode = '22023';
  end if;

  if public.school_account_identity_key(
    p_provider,
    p_base_url,
    v_candidate_provider_user_id
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
    provider_user_id = v_candidate_provider_user_id,
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
