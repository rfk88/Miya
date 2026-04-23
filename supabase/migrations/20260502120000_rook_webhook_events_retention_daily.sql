-- Upgrade path: if an older schedule (e.g. twice-monthly) was already applied, switch to daily retention.
-- Safe if job absent or already daily (idempotent reschedule).

select cron.unschedule(jobid)
from cron.job
where jobname = 'rook_webhook_events_retention';

select cron.schedule(
  'rook_webhook_events_retention',
  '0 4 * * *',
  $$delete from public.rook_webhook_events where created_at < (now() - interval '7 days')$$
);
