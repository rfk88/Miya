-- =====================================================
-- Update family vitality RPCs to return progress-to-optimal score
-- Requires: vitality_progress_score(...) + user_profiles progress fields
-- =====================================================

-- Drop existing functions first (PostgreSQL doesn't allow changing return types)
drop function if exists public.get_family_vitality_scores(uuid, text, text);
drop function if exists public.get_family_vitality(uuid);

-- 1) Daily history: add progress_score per (user_id, score_date)
-- Backward compatible: works even if vitality_progress_score() function doesn't exist yet
create function public.get_family_vitality_scores(
  family_id uuid,
  start_date text,
  end_date text
)
returns table (
  user_id uuid,
  score_date text,
  total_score int,
  progress_score int,
  vitality_sleep_pillar_score int,
  vitality_movement_pillar_score int,
  vitality_stress_pillar_score int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
  has_progress_function boolean;
begin
  -- Authorization: only family members can query this family.
  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = get_family_vitality_scores.family_id
      and fm.user_id = auth.uid()
  )
  into caller_is_member;

  if not caller_is_member then
    raise exception 'Not authorized to access family vitality scores';
  end if;

  -- Check if vitality_progress_score function exists (migration may not have run yet)
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'vitality_progress_score'
  )
  into has_progress_function;

  if has_progress_function then
    -- New path: compute progress_score using function
    return query
    select
      vs.user_id,
      vs.score_date::text,
      vs.total_score,
      public.vitality_progress_score(vs.total_score, up.date_of_birth, up.risk_band) as progress_score,
      vs.vitality_sleep_pillar_score,
      vs.vitality_movement_pillar_score,
      vs.vitality_stress_pillar_score
    from public.vitality_scores vs
    left join public.user_profiles up
      on up.user_id = vs.user_id
    where vs.user_id in (
      select fm.user_id
      from public.family_members fm
      where fm.family_id = get_family_vitality_scores.family_id
        and fm.user_id is not null
    )
      and vs.score_date::text >= get_family_vitality_scores.start_date
      and vs.score_date::text <= get_family_vitality_scores.end_date
    order by vs.user_id, vs.score_date asc;
  else
    -- Fallback path: return NULL for progress_score if function doesn't exist
    return query
    select
      vs.user_id,
      vs.score_date::text,
      vs.total_score,
      null::int as progress_score,
      vs.vitality_sleep_pillar_score,
      vs.vitality_movement_pillar_score,
      vs.vitality_stress_pillar_score
    from public.vitality_scores vs
    where vs.user_id in (
      select fm.user_id
      from public.family_members fm
      where fm.family_id = get_family_vitality_scores.family_id
        and fm.user_id is not null
    )
      and vs.score_date::text >= get_family_vitality_scores.start_date
      and vs.score_date::text <= get_family_vitality_scores.end_date
    order by vs.user_id, vs.score_date asc;
  end if;
end;
$$;

-- 2) Family snapshot: add family_progress_score (avg of member progress scores)
-- Backward compatible: works even if vitality_progress_score_current column doesn't exist yet
create function public.get_family_vitality(family_id uuid)
returns table (
  family_vitality_score int,
  members_with_data int,
  members_total int,
  last_updated_at timestamptz,
  has_recent_data boolean,
  family_progress_score int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
  has_is_active_column boolean;
  has_progress_column boolean;
begin
  -- Basic authorization: only family members can query this family's vitality.
  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = get_family_vitality.family_id
      and fm.user_id = auth.uid()
  )
  into caller_is_member;

  if not caller_is_member then
    raise exception 'Not authorized to access family vitality';
  end if;

  -- Check whether family_members has an is_active column; if not, treat all members as active.
  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'family_members'
      and c.column_name = 'is_active'
  )
  into has_is_active_column;

  -- Check if vitality_progress_score_current column exists (migration may not have run yet)
  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'user_profiles'
      and c.column_name = 'vitality_progress_score_current'
  )
  into has_progress_column;

  if has_is_active_column then
    if has_progress_column then
      -- New path: use vitality_progress_score_current column
      return query
      with active_members as (
        select fm.user_id
        from public.family_members fm
        where fm.family_id = get_family_vitality.family_id
          and fm.is_active is true
      ),
      member_scores as (
        select
          am.user_id,
          up.vitality_score_current,
          up.vitality_progress_score_current,
          up.vitality_score_updated_at
        from active_members am
        left join public.user_profiles up
          on up.user_id = am.user_id
      )
      select
        round(
          avg(member_scores.vitality_score_current) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_vitality_score,
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        )::int as members_with_data,
        (select count(*) from active_members)::int as members_total,
        max(member_scores.vitality_score_updated_at) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        ) as last_updated_at,
        (
          count(member_scores.user_id) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          ) > 0
        ) as has_recent_data,
        round(
          avg(member_scores.vitality_progress_score_current) filter (
            where member_scores.vitality_progress_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_progress_score
      from member_scores;
    else
      -- Fallback: return NULL for family_progress_score if column doesn't exist
      return query
      with active_members as (
        select fm.user_id
        from public.family_members fm
        where fm.family_id = get_family_vitality.family_id
          and fm.is_active is true
      ),
      member_scores as (
        select
          am.user_id,
          up.vitality_score_current,
          up.vitality_score_updated_at
        from active_members am
        left join public.user_profiles up
          on up.user_id = am.user_id
      )
      select
        round(
          avg(member_scores.vitality_score_current) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_vitality_score,
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        )::int as members_with_data,
        (select count(*) from active_members)::int as members_total,
        max(member_scores.vitality_score_updated_at) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        ) as last_updated_at,
        (
          count(member_scores.user_id) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          ) > 0
        ) as has_recent_data,
        null::int as family_progress_score
      from member_scores;
    end if;
  else
    if has_progress_column then
      -- New path: use vitality_progress_score_current column (no is_active column)
      return query
      with active_members as (
        select fm.user_id
        from public.family_members fm
        where fm.family_id = get_family_vitality.family_id
      ),
      member_scores as (
        select
          am.user_id,
          up.vitality_score_current,
          up.vitality_progress_score_current,
          up.vitality_score_updated_at
        from active_members am
        left join public.user_profiles up
          on up.user_id = am.user_id
      )
      select
        round(
          avg(member_scores.vitality_score_current) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_vitality_score,
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        )::int as members_with_data,
        (select count(*) from active_members)::int as members_total,
        max(member_scores.vitality_score_updated_at) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        ) as last_updated_at,
        (
          count(member_scores.user_id) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          ) > 0
        ) as has_recent_data,
        round(
          avg(member_scores.vitality_progress_score_current) filter (
            where member_scores.vitality_progress_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_progress_score
      from member_scores;
    else
      -- Fallback: return NULL for family_progress_score if column doesn't exist (no is_active column)
      return query
      with active_members as (
        select fm.user_id
        from public.family_members fm
        where fm.family_id = get_family_vitality.family_id
      ),
      member_scores as (
        select
          am.user_id,
          up.vitality_score_current,
          up.vitality_score_updated_at
        from active_members am
        left join public.user_profiles up
          on up.user_id = am.user_id
      )
      select
        round(
          avg(member_scores.vitality_score_current) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          )
        )::int as family_vitality_score,
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        )::int as members_with_data,
        (select count(*) from active_members)::int as members_total,
        max(member_scores.vitality_score_updated_at) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '7 days'
        ) as last_updated_at,
        (
          count(member_scores.user_id) filter (
            where member_scores.vitality_score_current is not null
              and member_scores.vitality_score_updated_at >= now() - interval '7 days'
          ) > 0
        ) as has_recent_data,
        null::int as family_progress_score
      from member_scores;
    end if;
  end if;
end;
$$;


