-- Vitality scores storage (non-destructive)
-- Run in Supabase SQL editor

begin;

-- Daily vitality scores with components
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

-- Optional: snapshot of latest vitality on user_profiles
alter table user_profiles
    add column if not exists vitality_score_current integer,
    add column if not exists vitality_score_source text check (vitality_score_source in ('csv','wearable','manual')),
    add column if not exists vitality_score_updated_at timestamptz;

commit;

