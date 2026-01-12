-- =====================================================
-- Add baseline-driven pattern alert state + notification queue
-- Additive / safe to run on existing projects.
-- =====================================================

create table if not exists public.pattern_alert_state (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,

  user_id uuid not null references auth.users(id) on delete cascade,
  metric_type text not null,     -- sleep_minutes, steps, hrv_ms, resting_hr
  pattern_type text not null,    -- drop_vs_baseline, rise_vs_baseline

  -- Episode state
  episode_status text not null default 'active', -- active, resolved
  active_since date not null,
  last_evaluated_date date not null,
  consecutive_true_days int not null default 0,

  -- Escalation
  current_level int not null default 3, -- 3, 7, 14, 21
  last_notified_level int,
  last_notified_at timestamptz,

  -- UX controls
  snooze_until date,
  dismissed_at timestamptz,
  acknowledged_at timestamptz,

  -- Audit / explainability
  baseline_start date,
  baseline_end date,
  baseline_value numeric,
  recent_start date,
  recent_end date,
  recent_value numeric,
  deviation_percent numeric,
  computed_at timestamptz default now()
);

-- Ensure one row per episode key
create unique index if not exists idx_pattern_alert_state_episode_unique
  on public.pattern_alert_state (user_id, metric_type, pattern_type, active_since);

-- Fast lookups for active alerts per user
create index if not exists idx_pattern_alert_state_user_status
  on public.pattern_alert_state (user_id, episode_status, current_level);

create table if not exists public.notification_queue (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,

  recipient_user_id uuid not null references auth.users(id) on delete cascade, -- who receives (caregiver)
  member_user_id uuid not null references auth.users(id) on delete cascade,    -- who it's about
  alert_state_id uuid references public.pattern_alert_state(id) on delete set null,

  channel text not null,          -- push, whatsapp
  payload jsonb not null,

  status text not null default 'pending', -- pending, sent, failed
  attempts int not null default 0,
  last_error text,
  sent_at timestamptz
);

create index if not exists idx_notification_queue_status
  on public.notification_queue (status, created_at);

-- updated_at triggers (reuse existing helper if present)
do $$
begin
  if not exists (
    select 1 from pg_proc where proname = 'update_updated_at_column'
  ) then
    create or replace function public.update_updated_at_column()
    returns trigger as $fn$
    begin
      new.updated_at = now();
      return new;
    end;
    $fn$ language plpgsql;
  end if;
end $$;

drop trigger if exists update_pattern_alert_state_updated_at on public.pattern_alert_state;
create trigger update_pattern_alert_state_updated_at
  before update on public.pattern_alert_state
  for each row
  execute function public.update_updated_at_column();

drop trigger if exists update_notification_queue_updated_at on public.notification_queue;
create trigger update_notification_queue_updated_at
  before update on public.notification_queue
  for each row
  execute function public.update_updated_at_column();

