-- A poll can include a school-token refresh and several provider requests.
-- pg_net's five-second default was timing out even during DNS resolution.
-- Keep the existing schedule and active state; only extend its HTTP timeout.
do $$
declare
  v_job_id bigint;
begin
  select jobid into strict v_job_id from cron.job
  where jobname = 'gradey-poll-new-marks';

  perform cron.alter_job(v_job_id, command := $command$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'gradey_project_url')
        || '/functions/v1/poll-new-marks',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'gradey_cron_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
  $command$);
end;
$$;
