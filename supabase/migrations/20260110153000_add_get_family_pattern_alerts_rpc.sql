-- =====================================================
-- RPC: get_family_pattern_alerts(family_id uuid)
-- Returns active pattern alerts (pattern_alert_state) for all members in a family.
--
-- Authorization:
-- - Caller must be a member of the family (auth.uid()).
-- - Uses SECURITY DEFINER so a caregiver can read member alerts.
-- =====================================================

create or replace function public.get_family_pattern_alerts(
  family_id uuid
)
returns table (
  id uuid,
  member_user_id uuid,
  metric_type text,
  pattern_type text,
  episode_status text,
  active_since date,
  current_level int,
  severity text,
  snooze_until date,
  dismissed_at timestamptz,
  deviation_percent numeric,
  baseline_value numeric,
  recent_value numeric
)
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
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id = auth.uid()
  )
  into caller_is_member;

  if not caller_is_member then
    raise exception 'Not authorized to access family pattern alerts';
  end if;

  return query
  select
    pas.id,
    pas.user_id as member_user_id,
    pas.metric_type,
    pas.pattern_type,
    pas.episode_status,
    pas.active_since,
    pas.current_level,
    pas.severity,
    pas.snooze_until,
    pas.dismissed_at,
    pas.deviation_percent,
    pas.baseline_value,
    pas.recent_value
  from public.pattern_alert_state pas
  where pas.user_id in (
    select fm.user_id
    from public.family_members fm
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id is not null
  )
    and pas.episode_status = 'active'
  order by pas.current_level desc, pas.active_since desc;
end;
$$;

