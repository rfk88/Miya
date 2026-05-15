-- Phase 1 hardening for BIG competitive challenges.
-- Adds Mon–Sun window columns, tie-break/winner fields, evaluation timestamp,
-- per-day per-user uniqueness, and a hard participant cap (2..6) enforced
-- by trigger on big_competitive_participants.
--
-- These tables were created in 20260515140000_big_competitive_challenges_v1.sql.
-- This migration is additive and idempotent (re-runnable).

-- 1) Window + result columns on big_competitive_challenges
alter table public.big_competitive_challenges
  add column if not exists start_date date,
  add column if not exists end_date   date,
  add column if not exists activated_at timestamptz,
  add column if not exists last_evaluated_at timestamptz,
  add column if not exists winner_user_id uuid references auth.users(id) on delete set null,
  add column if not exists tie_break_used boolean not null default false;

create index if not exists big_competitive_challenges_active_window_idx
  on public.big_competitive_challenges (status, start_date, end_date);

comment on column public.big_competitive_challenges.start_date is
  'First scored day (Monday) of the Mon–Sun window for this challenge.';
comment on column public.big_competitive_challenges.end_date is
  'Last scored day (Sunday) of the Mon–Sun window for this challenge.';
comment on column public.big_competitive_challenges.winner_user_id is
  'User declared the winner once status = completed; nullable for draws.';
comment on column public.big_competitive_challenges.tie_break_used is
  'True when the winner was decided by single-best-day tie-break instead of aggregate.';

-- 2) Optional convenience: store a denormalized "current leader" snapshot for fast UI reads.
--    Updated by the evaluator function; safe to be NULL.
alter table public.big_competitive_challenges
  add column if not exists current_leader_user_id uuid references auth.users(id) on delete set null,
  add column if not exists current_leader_metric numeric;

-- 3) Snapshot table: ensure (challenge_id, user_id, local_date) uniqueness is robust.
--    (Existing migration already declared this UNIQUE, this is a no-op safety check.)
do $$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename  = 'big_competitive_daily_snapshots'
      and indexname  = 'big_competitive_daily_snapshots_challenge_id_user_id_local_d_key'
  ) then
    -- created automatically by the UNIQUE constraint; nothing to do.
    null;
  end if;
end$$;

-- 4) Participants: enforce max 6, and ensure at least 2 once active.
--    Implemented as a trigger so it composes with multi-row inserts.
create or replace function public.big_competitive_participants_enforce_caps()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_status text;
begin
  select count(*) into v_count
  from public.big_competitive_participants
  where challenge_id = coalesce(new.challenge_id, old.challenge_id);

  if tg_op = 'INSERT' then
    if v_count > 6 then
      raise exception 'family_brawl_max_6_participants';
    end if;
  end if;

  if tg_op = 'DELETE' then
    select status into v_status
    from public.big_competitive_challenges
    where id = old.challenge_id;
    if v_status = 'active' and v_count < 2 then
      raise exception 'cannot_drop_below_two_active_participants';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_big_competitive_participants_caps on public.big_competitive_participants;
create trigger trg_big_competitive_participants_caps
after insert or delete on public.big_competitive_participants
for each row execute function public.big_competitive_participants_enforce_caps();

-- 5) Notification queue rate-limit support: index for "pushes per user per day".
--    Phase 3 lead-change scheduler counts rows by recipient_user_id and created_at::date.
create index if not exists notification_queue_recipient_created_idx
  on public.notification_queue (recipient_user_id, created_at desc);

comment on function public.big_competitive_participants_enforce_caps is
  'Hard cap on competitive challenges: maximum 6 participants; do not drop below 2 once active.';

-- Deployment note (cron — set manually in Supabase Dashboard):
--   Edge Functions > competitive_challenges_daily_evaluate > schedule "0 6 * * *"
--   header: x-miya-admin-secret = $MIYA_ADMIN_SECRET
-- pg_cron + pg_net example (kept commented; safe to copy/paste):
/*
select cron.schedule(
  'competitive-challenges-daily-evaluate',
  '0 6 * * *',
  $$ select net.http_post(
    url := 'https://YOUR_REF.supabase.co/functions/v1/competitive_challenges_daily_evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-miya-admin-secret', current_setting('app.miya_admin_secret', true)),
    body := '{}'
  ) as request_id $$
);
*/
