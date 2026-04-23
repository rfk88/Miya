-- Retention for rook_webhook_events (raw Rook audit log only).
-- Safe for app scores: vitality lives in vitality_scores / wearable_daily_metrics / user_profiles.
--
-- Prerequisites (Supabase Dashboard → Database → Extensions):
--   Enable "pg_cron" if this migration errors on CREATE EXTENSION.
--
-- Schedule: daily 04:00 UTC ('0 4 * * *'). Keeps at most ~7–8 days of webhook rows on disk between deletes.
-- Deletes rows older than 7 days (rolling window).

create index if not exists idx_rook_webhook_events_created_at
  on public.rook_webhook_events (created_at);

create extension if not exists pg_cron with schema extensions;

-- Idempotent: drop existing job name if we re-apply.
select cron.unschedule(jobid)
from cron.job
where jobname = 'rook_webhook_events_retention';

select cron.schedule(
  'rook_webhook_events_retention',
  '0 4 * * *',
  $$delete from public.rook_webhook_events where created_at < (now() - interval '7 days')$$
);
