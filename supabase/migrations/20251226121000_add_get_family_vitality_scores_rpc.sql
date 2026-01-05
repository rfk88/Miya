-- =====================================================
-- RPC: get_family_vitality_scores(family_id uuid, start_date text, end_date text)
-- Returns daily vitality history (total + pillar scores) for all members in a family.
--
-- Notes:
-- - `vitality_scores.score_date` is stored/queried as a YYYY-MM-DD string in the app.
-- - Caller must be a member of the family (auth.uid()).
-- =====================================================

create or replace function public.get_family_vitality_scores(
  family_id uuid,
  start_date text,
  end_date text
)
returns table (
  user_id uuid,
  score_date text,
  total_score int,
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

  return query
  select
    vs.user_id,
    vs.score_date,
    vs.total_score,
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
    and vs.score_date >= get_family_vitality_scores.start_date
    and vs.score_date <= get_family_vitality_scores.end_date
  order by vs.user_id, vs.score_date asc;
end;
$$;


