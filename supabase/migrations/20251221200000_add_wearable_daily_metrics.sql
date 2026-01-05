-- Create table to store parsed daily metrics from Rook webhooks
create table if not exists wearable_daily_metrics (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  user_id uuid, -- nullable for now, we'll fill it once we know the mapping
  rook_user_id text, -- Rook's user identifier if present
  source text, -- e.g. apple_health, whoop, oura, etc.
  metric_date date, -- "day this data belongs to"
  steps integer,
  sleep_minutes integer,
  hrv_ms numeric,
  resting_hr numeric,
  avg_hr numeric,
  calories_active numeric,
  calories_total numeric,
  score_raw numeric,
  score_normalized numeric,
  raw_payload jsonb -- full payload for debugging
);

-- Unique constraint for upsert logic: one row per (rook_user_id, metric_date, source)
-- PostgreSQL allows multiple NULLs in unique constraints, so this works for our nullable fields
create unique index if not exists idx_wearable_daily_metrics_unique 
  on wearable_daily_metrics (rook_user_id, metric_date, source);

-- Index for efficient lookups by Rook user ID and date
create index if not exists idx_wearable_daily_metrics_rook_user_date 
  on wearable_daily_metrics (rook_user_id, metric_date);

-- Trigger to automatically update updated_at on row updates
create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger update_wearable_daily_metrics_updated_at
  before update on wearable_daily_metrics
  for each row
  execute function update_updated_at_column();

