-- =====================================================
-- Data integrity cleanup: Vitality snapshot columns
-- - Replace invalid negative values with NULL (\"no score\" should be NULL, never -1)
-- - Enforce 0–100 (or NULL) range constraints so negatives can't come back
-- =====================================================

begin;

-- 1) Clean invalid values (negatives -> NULL)
update public.user_profiles
set vitality_score_current = null
where vitality_score_current < 0;

update public.user_profiles
set vitality_sleep_pillar_score = null
where vitality_sleep_pillar_score < 0;

update public.user_profiles
set vitality_movement_pillar_score = null
where vitality_movement_pillar_score < 0;

update public.user_profiles
set vitality_stress_pillar_score = null
where vitality_stress_pillar_score < 0;

-- 2) Add CHECK constraints (NULL or 0–100)
do $$
begin
  -- vitality_score_current had no range constraint previously.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'vitality_score_current'
  ) then
    if not exists (
      select 1 from pg_constraint
      where conname = 'user_profiles_vitality_score_current_range'
    ) then
      alter table public.user_profiles
        add constraint user_profiles_vitality_score_current_range
        check (vitality_score_current is null or (vitality_score_current between 0 and 100));
    end if;
  end if;

  -- These pillar columns already have CHECK constraints in migrations, but we add named constraints
  -- (idempotently) to guarantee the invariant in all environments.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'vitality_sleep_pillar_score'
  ) then
    if not exists (select 1 from pg_constraint where conname = 'user_profiles_vitality_sleep_pillar_score_range') then
      alter table public.user_profiles
        add constraint user_profiles_vitality_sleep_pillar_score_range
        check (vitality_sleep_pillar_score is null or (vitality_sleep_pillar_score between 0 and 100));
    end if;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'vitality_movement_pillar_score'
  ) then
    if not exists (select 1 from pg_constraint where conname = 'user_profiles_vitality_movement_pillar_score_range') then
      alter table public.user_profiles
        add constraint user_profiles_vitality_movement_pillar_score_range
        check (vitality_movement_pillar_score is null or (vitality_movement_pillar_score between 0 and 100));
    end if;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_profiles'
      and column_name = 'vitality_stress_pillar_score'
  ) then
    if not exists (select 1 from pg_constraint where conname = 'user_profiles_vitality_stress_pillar_score_range') then
      alter table public.user_profiles
        add constraint user_profiles_vitality_stress_pillar_score_range
        check (vitality_stress_pillar_score is null or (vitality_stress_pillar_score between 0 and 100));
    end if;
  end if;
end $$;

commit;


