-- BIG competitive challenges (Phase B) — schema foundation.
-- Product rules: head_to_head (2) / family_brawl (2–6), focus includes steps, Mon–Sun per-user local (app layer).
-- Mutations are intended to go through security definer RPCs (added in a follow-up migration).

create table if not exists public.big_competitive_challenges (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  mode text not null check (mode in ('head_to_head', 'family_brawl')),
  focus text not null check (focus in ('sleep', 'movement', 'stress', 'steps')),
  status text not null default 'pending_accepts'
    check (status in ('pending_accepts', 'active', 'completed', 'cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists big_competitive_challenges_family_idx
  on public.big_competitive_challenges (family_id, created_at desc);

create table if not exists public.big_competitive_participants (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.big_competitive_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  invite_status text not null default 'pending'
    check (invite_status in ('pending', 'accepted', 'declined')),
  accepted_at timestamptz,
  unique (challenge_id, user_id)
);

create index if not exists big_competitive_participants_user_idx
  on public.big_competitive_participants (user_id);

-- Optional daily snapshots for standings / notification copy (filled by evaluator job later).
create table if not exists public.big_competitive_daily_snapshots (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.big_competitive_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  pillar_score numeric,
  steps integer,
  created_at timestamptz not null default now(),
  unique (challenge_id, user_id, local_date)
);

-- Ledger for Champions-style bonuses when a BIG challenge completes (server writes).
create table if not exists public.big_challenge_champion_point_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  points integer not null check (points > 0),
  reason text not null,
  competitive_challenge_id uuid references public.big_competitive_challenges(id) on delete set null,
  placement integer,
  created_at timestamptz not null default now()
);

create index if not exists big_challenge_champion_point_events_user_idx
  on public.big_challenge_champion_point_events (user_id, created_at desc);

alter table public.big_competitive_challenges enable row level security;
alter table public.big_competitive_participants enable row level security;
alter table public.big_competitive_daily_snapshots enable row level security;
alter table public.big_challenge_champion_point_events enable row level security;

drop policy if exists "big_competitive_challenges_select_family" on public.big_competitive_challenges;
create policy "big_competitive_challenges_select_family"
  on public.big_competitive_challenges
  for select
  using (
    exists (
      select 1 from public.family_members fm
      where fm.family_id = big_competitive_challenges.family_id
        and fm.user_id = auth.uid()
    )
  );

drop policy if exists "big_competitive_participants_select_family" on public.big_competitive_participants;
create policy "big_competitive_participants_select_family"
  on public.big_competitive_participants
  for select
  using (
    exists (
      select 1
      from public.big_competitive_challenges c
      join public.family_members fm on fm.family_id = c.family_id and fm.user_id = auth.uid()
      where c.id = big_competitive_participants.challenge_id
    )
  );

drop policy if exists "big_competitive_daily_snapshots_select_family" on public.big_competitive_daily_snapshots;
create policy "big_competitive_daily_snapshots_select_family"
  on public.big_competitive_daily_snapshots
  for select
  using (
    exists (
      select 1
      from public.big_competitive_challenges c
      join public.family_members fm on fm.family_id = c.family_id and fm.user_id = auth.uid()
      where c.id = big_competitive_daily_snapshots.challenge_id
    )
  );

drop policy if exists "big_challenge_champion_point_events_select_self" on public.big_challenge_champion_point_events;
create policy "big_challenge_champion_point_events_select_self"
  on public.big_challenge_champion_point_events
  for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.family_members fm
      where fm.family_id = big_challenge_champion_point_events.family_id
        and fm.user_id = auth.uid()
    )
  );

comment on table public.big_competitive_challenges is
  'Phase B head-to-head / family brawl competitive challenges (separate from legacy public.challenges).';
comment on table public.big_challenge_champion_point_events is
  'Audit log for Champions bonus points awarded for BIG challenge outcomes; totals consumed by app when wired.';
