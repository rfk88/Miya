-- =====================================================
-- RPC: get_family_vitality(family_id uuid)
-- Computes a "Family Vitality" snapshot from existing tables only:
--   - family_members (family membership; optionally is_active)
--   - user_profiles (vitality_score_current, vitality_score_updated_at)
--
-- Rules:
--   - Only include active members (if family_members.is_active exists; otherwise treat all as active)
--   - Only include members with:
--       vitality_score_current IS NOT NULL
--       vitality_score_updated_at >= now() - interval '3 days'
--   - Return NULL score + has_recent_data=false if no members qualify
-- =====================================================

create or replace function public.get_family_vitality(family_id uuid)
returns table (
  family_vitality_score int,
  members_with_data int,
  members_total int,
  last_updated_at timestamptz,
  has_recent_data boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
  has_is_active_column boolean;
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

  if has_is_active_column then
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
            and member_scores.vitality_score_updated_at >= now() - interval '3 days'
        )
      )::int as family_vitality_score,
      count(member_scores.user_id) filter (
        where member_scores.vitality_score_current is not null
          and member_scores.vitality_score_updated_at >= now() - interval '3 days'
      )::int as members_with_data,
      (select count(*) from active_members)::int as members_total,
      max(member_scores.vitality_score_updated_at) filter (
        where member_scores.vitality_score_current is not null
          and member_scores.vitality_score_updated_at >= now() - interval '3 days'
      ) as last_updated_at,
      (
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '3 days'
        ) > 0
      ) as has_recent_data
    from member_scores;
  else
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
            and member_scores.vitality_score_updated_at >= now() - interval '3 days'
        )
      )::int as family_vitality_score,
      count(member_scores.user_id) filter (
        where member_scores.vitality_score_current is not null
          and member_scores.vitality_score_updated_at >= now() - interval '3 days'
      )::int as members_with_data,
      (select count(*) from active_members)::int as members_total,
      max(member_scores.vitality_score_updated_at) filter (
        where member_scores.vitality_score_current is not null
          and member_scores.vitality_score_updated_at >= now() - interval '3 days'
      ) as last_updated_at,
      (
        count(member_scores.user_id) filter (
          where member_scores.vitality_score_current is not null
            and member_scores.vitality_score_updated_at >= now() - interval '3 days'
        ) > 0
      ) as has_recent_data
    from member_scores;
  end if;
end;
$$;


