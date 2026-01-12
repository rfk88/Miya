-- Create table for storing user feedback on AI insights
-- Migration: 20260112000000_create_alert_insight_feedback.sql

create table if not exists public.alert_insight_feedback (
  id uuid primary key default gen_random_uuid(),
  alert_state_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_helpful boolean not null, -- true for thumbs up, false for thumbs down
  created_at timestamptz not null default now(),
  
  -- Constraints
  constraint unique_feedback_per_alert unique (alert_state_id, user_id)
);

-- Index for efficient queries
create index if not exists idx_alert_insight_feedback_alert_state_id 
  on public.alert_insight_feedback(alert_state_id);
create index if not exists idx_alert_insight_feedback_user_id 
  on public.alert_insight_feedback(user_id);
create index if not exists idx_alert_insight_feedback_created_at 
  on public.alert_insight_feedback(created_at desc);

-- Row Level Security
alter table public.alert_insight_feedback enable row level security;

-- Users can only read/write their own feedback
create policy "Users can read own feedback"
  on public.alert_insight_feedback
  for select
  using (auth.uid() = user_id);

create policy "Users can insert own feedback"
  on public.alert_insight_feedback
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own feedback"
  on public.alert_insight_feedback
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own feedback"
  on public.alert_insight_feedback
  for delete
  using (auth.uid() = user_id);

-- Add comments
comment on table public.alert_insight_feedback is 
  'Stores user feedback (thumbs up/down) on AI-generated health insights';
comment on column public.alert_insight_feedback.alert_state_id is 
  'Reference to the pattern_alert_state that this feedback is for';
comment on column public.alert_insight_feedback.is_helpful is 
  'true = thumbs up (helpful), false = thumbs down (not helpful)';
