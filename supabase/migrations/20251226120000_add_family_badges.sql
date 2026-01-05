-- =====================================================
-- Family Badges (weekly winners)
-- Stores weekly badge winners per family/week for fast reads and auditability.
-- =====================================================
--
-- Notes:
-- - Week windows are UTC date keys (YYYY-MM-DD) computed client-side.
-- - badge_type is constrained to the supported weekly badge set (v1).
-- - Writes are allowed for admin/superadmin members of the family (v1).
-- =====================================================

create table if not exists public.family_badges (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  badge_week_start date not null,
  badge_week_end date not null,
  badge_type text not null,
  winner_user_id uuid not null references auth.users(id) on delete cascade,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Enforce supported badge types (weekly only, v1)
do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints tc
    where tc.table_schema = 'public'
      and tc.table_name = 'family_badges'
      and tc.constraint_name = 'family_badges_badge_type_check'
  ) then
    alter table public.family_badges
      add constraint family_badges_badge_type_check
      check (badge_type in (
        'weekly_vitality_mvp',
        'weekly_sleep_mvp',
        'weekly_movement_mvp',
        'weekly_stressfree_mvp',
        'weekly_family_anchor',
        'weekly_consistency_mvp',
        'weekly_balanced_week',
        'weekly_biggest_comeback_day',
        'weekly_sleep_streak_leader',
        'weekly_movement_streak_leader',
        'weekly_stress_streak_leader',
        'weekly_data_champion'
      ));
  end if;
end$$;

-- Idempotency: one winner per family/week/badge
create unique index if not exists family_badges_unique_week_type
  on public.family_badges (family_id, badge_week_start, badge_type);

create index if not exists family_badges_family_week_idx
  on public.family_badges (family_id, badge_week_start);

alter table public.family_badges enable row level security;

-- Read: any authenticated member of the family can view badges
drop policy if exists "family_badges_read_family" on public.family_badges;
create policy "family_badges_read_family"
  on public.family_badges
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = family_badges.family_id
        and fm.user_id = auth.uid()
    )
  );

-- Write: only admin/superadmin can insert/update (v1)
drop policy if exists "family_badges_write_admin" on public.family_badges;
create policy "family_badges_write_admin"
  on public.family_badges
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = family_badges.family_id
        and fm.user_id = auth.uid()
        and fm.role in ('admin', 'superadmin')
    )
  );

drop policy if exists "family_badges_update_admin" on public.family_badges;
create policy "family_badges_update_admin"
  on public.family_badges
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = family_badges.family_id
        and fm.user_id = auth.uid()
        and fm.role in ('admin', 'superadmin')
    )
  )
  with check (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = family_badges.family_id
        and fm.user_id = auth.uid()
        and fm.role in ('admin', 'superadmin')
    )
  );


