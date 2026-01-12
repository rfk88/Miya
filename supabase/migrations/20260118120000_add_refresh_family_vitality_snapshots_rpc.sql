-- =====================================================
-- RPC: refresh_family_vitality_snapshots(family_id uuid)
-- Updates user_profiles snapshot scores from the latest vitality_scores row
-- for each member in the family. This keeps pillar scores up to date when
-- daily scoring exists but the snapshot hasn't been updated yet.
--
-- Authorization:
-- - Caller must be a member of the family (auth.uid()).
-- - Uses SECURITY DEFINER so caregivers can refresh member snapshots.
-- =====================================================

create or replace function public.refresh_family_vitality_snapshots(
  family_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
begin
  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = refresh_family_vitality_snapshots.family_id
      and fm.user_id = auth.uid()
  )
  into caller_is_member;

  if not caller_is_member then
    raise exception 'Not authorized to refresh family vitality snapshots';
  end if;

  update public.user_profiles up
  set
    vitality_score_current = v.total_score,
    vitality_score_source = 'wearable',
    vitality_score_updated_at = v.score_date::timestamptz,
    vitality_sleep_pillar_score = v.vitality_sleep_pillar_score,
    vitality_movement_pillar_score = v.vitality_movement_pillar_score,
    vitality_stress_pillar_score = v.vitality_stress_pillar_score
  from (
    select distinct on (vs.user_id)
      vs.user_id,
      vs.total_score,
      vs.vitality_sleep_pillar_score,
      vs.vitality_movement_pillar_score,
      vs.vitality_stress_pillar_score,
      vs.score_date
    from public.vitality_scores vs
    where vs.user_id in (
      select fm.user_id
      from public.family_members fm
      where fm.family_id = refresh_family_vitality_snapshots.family_id
        and fm.user_id is not null
    )
    order by vs.user_id, vs.score_date desc
  ) v
  where up.user_id = v.user_id;
end;
$$;
