-- The background marks poller rotates provider refresh tokens. Keep this
-- privileged write path scoped to the service role and to a user-owned secret.
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
    p_payload::text,
    p_key,
    'compress-algo=1,cipher-algo=aes256'
  ),
      rotated_at = now()
  where secret.id = p_secret_id
    and secret.user_id = p_user_id;

  return found;
end;
$$;

revoke execute on function public.update_provider_secret(uuid, uuid, jsonb, text)
  from public, anon, authenticated, service_role;
grant execute on function public.update_provider_secret(uuid, uuid, jsonb, text)
  to service_role;
