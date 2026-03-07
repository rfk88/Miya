-- =====================================================
-- Family Care Loop: alert_care_state + alert_interventions
-- One row per alert for family-wide care state; ledger of all interventions.
-- =====================================================

-- 1. alert_care_state — one row per pattern_alert_state (family-wide)
create table if not exists public.alert_care_state (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  alert_id uuid not null unique references public.pattern_alert_state(id) on delete cascade,

  -- Health outcome state (what the system/caregiver knows about the outcome). Null = resurfaced (show as New).
  care_state text default 'monitoring'
    check (care_state is null or care_state in ('monitoring', 'improving', 'resolved', 'archived')),

  -- Action state (what the caregiver last did — separate from outcome)
  last_intervention_type text
    check (last_intervention_type in ('challenge', 'check_in', 'reach_out', 'manual_improve', 'manual_resolve', 'reviewed_no_action')),

  -- Who acted and when
  acted_by_user_id uuid references auth.users(id),
  acted_at timestamptz,

  -- Snapshot of recent_value at the moment of acting (for outcome comparison)
  pre_action_recent_value numeric,

  -- When the outcome job should evaluate this alert
  follow_up_due_date date,

  -- Whether outcome has been evaluated for current cycle
  outcome_evaluated_at timestamptz,

  -- Copy shown in the detail sheet header ("Sleep has improved for 2 nights")
  outcome_message text,

  -- How many act -> evaluate cycles have run (max 2 before auto-archive)
  cycle_count int not null default 0
);

create index if not exists idx_alert_care_state_alert on public.alert_care_state (alert_id);
create index if not exists idx_alert_care_state_monitoring on public.alert_care_state (care_state, follow_up_due_date)
  where care_state = 'monitoring' and outcome_evaluated_at is null;

comment on table public.alert_care_state is
'Family-wide care state per pattern alert. Created when a caregiver acts; outcome job updates it.';

comment on column public.alert_care_state.care_state is
'Health outcome: monitoring (waiting), improving, resolved, archived.';

comment on column public.alert_care_state.last_intervention_type is
'Last action taken: challenge, check_in, reach_out, manual_improve, manual_resolve, reviewed_no_action.';

-- 2. updated_at trigger for alert_care_state
drop trigger if exists update_alert_care_state_updated_at on public.alert_care_state;
create trigger update_alert_care_state_updated_at
  before update on public.alert_care_state
  for each row
  execute function public.update_updated_at_column();

-- 3. alert_interventions — full ledger of every caregiver action
create table if not exists public.alert_interventions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  alert_id uuid not null references public.pattern_alert_state(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  intervention_type text not null
    check (intervention_type in ('challenge', 'check_in', 'reach_out', 'manual_improve', 'manual_resolve', 'reviewed_no_action', 'not_concerning')),
  challenge_id uuid references public.challenges(id)
);

create index if not exists idx_alert_interventions_alert on public.alert_interventions (alert_id);
create index if not exists idx_alert_interventions_user on public.alert_interventions (user_id);

comment on table public.alert_interventions is
'Ledger of every caregiver action on an alert. Read for audit; writes via record_alert_intervention RPC.';

-- 4. RLS: alert_care_state
alter table public.alert_care_state enable row level security;

drop policy if exists "alert_care_state_read_family" on public.alert_care_state;
create policy "alert_care_state_read_family"
  on public.alert_care_state
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.pattern_alert_state pas
      join public.family_members fm on fm.user_id = pas.user_id
      where pas.id = alert_care_state.alert_id
        and fm.family_id in (
          select family_id from public.family_members where user_id = auth.uid()
        )
    )
  );

drop policy if exists "alert_care_state_block_write" on public.alert_care_state;
create policy "alert_care_state_block_write"
  on public.alert_care_state
  for all
  to authenticated
  using (false)
  with check (false);

-- 5. RLS: alert_interventions
alter table public.alert_interventions enable row level security;

drop policy if exists "alert_interventions_read_family" on public.alert_interventions;
create policy "alert_interventions_read_family"
  on public.alert_interventions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.pattern_alert_state pas
      join public.family_members fm on fm.user_id = pas.user_id
      where pas.id = alert_interventions.alert_id
        and fm.family_id in (
          select family_id from public.family_members where user_id = auth.uid()
        )
    )
  );

drop policy if exists "alert_interventions_block_write" on public.alert_interventions;
create policy "alert_interventions_block_write"
  on public.alert_interventions
  for all
  to authenticated
  using (false)
  with check (false);
