-- Schedules the process_notifications Edge Function worker via pg_cron + pg_net.
--
-- Prerequisites (Supabase Dashboard → Database → Extensions):
--   Enable "pg_cron" and "pg_net" if this migration errors on CREATE EXTENSION.
--
-- After deploy, set database GUCs (SQL editor, once per project):
--   alter database postgres set app.miya_admin_secret = '<MIYA_ADMIN_SECRET>';
--   alter database postgres set app.process_notifications_url =
--     'https://<project-ref>.supabase.co/functions/v1/process_notifications';
--
-- Edge Function secrets for process_notifications (Dashboard → Edge Functions → Secrets):
--   MIYA_ADMIN_SECRET, APNS_BUNDLE_ID, APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY
--   APNS_USE_SANDBOX=true for Xcode Debug / development APNs tokens
--
-- Manual alternative: Edge Functions → process_notifications → Cron every 1–5 min
--   POST body: { "batchSize": 50, "maxAge": 72 }
--   Header: x-miya-admin-secret: <MIYA_ADMIN_SECRET>

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create or replace function public.trigger_process_notifications_worker()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_secret text;
begin
  v_secret := nullif(trim(current_setting('app.miya_admin_secret', true)), '');
  v_url := nullif(trim(current_setting('app.process_notifications_url', true)), '');
  if v_secret is null or v_url is null then
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', v_secret
    ),
    body := '{"batchSize": 50, "maxAge": 72}'::jsonb
  );
end;
$$;

comment on function public.trigger_process_notifications_worker is
  'POSTs to process_notifications when app.miya_admin_secret and app.process_notifications_url are set. No-op otherwise.';

select cron.unschedule(jobid)
from cron.job
where jobname = 'process_notifications_worker';

select cron.schedule(
  'process_notifications_worker',
  '*/3 * * * *',
  $$select public.trigger_process_notifications_worker()$$
);
