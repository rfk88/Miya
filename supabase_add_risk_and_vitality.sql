-- One-shot SQL to add missing WHO risk + vitality storage (no deletes)
-- Run in Supabase SQL Editor

begin;

-- Risk / optimal fields
alter table user_profiles
  add column if not exists risk_band text check (risk_band in ('low','moderate','high','very_high','critical')),
  add column if not exists risk_points integer,
  add column if not exists optimal_vitality_target integer,
  add column if not exists risk_calculated_at timestamptz;

-- Vitality daily scores
create table if not exists vitality_scores (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) on delete cascade not null,
    score_date date not null,
    total_score integer check (total_score between 0 and 100),
    sleep_points integer,
    movement_points integer,
    stress_points integer,
    source text check (source in ('csv','wearable','manual')) default 'csv',
    created_at timestamptz default now(),
    unique (user_id, score_date)
);

-- Optional snapshot on user_profiles
alter table user_profiles
  add column if not exists vitality_score_current integer,
  add column if not exists vitality_score_source text check (vitality_score_source in ('csv','wearable','manual')),
  add column if not exists vitality_score_updated_at timestamptz;

commit;

