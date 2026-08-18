begin;

select plan(8);

select has_function(
  'public',
  'update_provider_secret',
  array['uuid', 'uuid', 'jsonb', 'text'],
  'the polling secret-rotation function exists'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.update_provider_secret(uuid,uuid,jsonb,text)'::regprocedure
  ),
  'provider-secret rotation is security definer'
);

select ok(
  (
    select proconfig @> array['search_path=""']
    from pg_proc
    where oid = 'public.update_provider_secret(uuid,uuid,jsonb,text)'::regprocedure
  ),
  'the privileged rotation function has an empty search path'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.update_provider_secret(uuid,uuid,jsonb,text)',
    'execute'
  ),
  'the service role can rotate a provider secret'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_provider_secret(uuid,uuid,jsonb,text)',
    'execute'
  ),
  'authenticated clients cannot rotate provider secrets'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_provider_secret(uuid,uuid,jsonb,text)',
    'execute'
  ),
  'anonymous clients cannot rotate provider secrets'
);

select ok(
  pg_get_functiondef(
    'public.update_provider_secret(uuid,uuid,jsonb,text)'::regprocedure
  ) ilike '%secret.id = p_secret_id%secret.user_id = p_user_id%',
  'rotation requires both the secret ID and its owning user'
);

select ok(
  pg_get_functiondef(
    'public.update_provider_secret(uuid,uuid,jsonb,text)'::regprocedure
  ) ilike '%extensions.pgp_sym_encrypt%rotated_at = now()%',
  'rotation re-encrypts the payload and records when it changed'
);

select * from finish();
rollback;
