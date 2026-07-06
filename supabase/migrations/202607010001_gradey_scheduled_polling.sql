create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'gradey-poll-new-marks') then
    perform cron.unschedule('gradey-poll-new-marks');
  end if;
end
$$;

select cron.schedule(
  'gradey-poll-new-marks',
  '*/5 * * * *',
  $$
  select
    net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'gradey_project_url'
      ) || '/functions/v1/poll-new-marks',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'gradey_cron_secret'
        )
      ),
      body := '{}'::jsonb
    );
  $$
);
