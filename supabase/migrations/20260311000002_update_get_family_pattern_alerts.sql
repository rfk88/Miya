-- =====================================================
-- Family Care Loop: update get_family_pattern_alerts
-- Exclude current user (caregiver does not see own alerts).
-- LEFT JOIN alert_care_state; filter archived; return care state fields.
-- =====================================================

drop function if exists public.get_family_pattern_alerts(uuid);

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
  snooze_days int,
  dismissed_at timestamptz,
  deviation_percent numeric,
  baseline_value numeric,
  recent_value numeric,
  care_state text,
  acted_by_user_id uuid,
  acted_at timestamptz,
  follow_up_due_date date,
  outcome_message text,
  cycle_count int,
  last_intervention_type text
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
    asn.snoozed_until as snooze_until,
    asn.snooze_days,
    pas.dismissed_at,
    pas.deviation_percent,
    pas.baseline_value,
    pas.recent_value,
    acs.care_state,
    acs.acted_by_user_id,
    acs.acted_at,
    acs.follow_up_due_date,
    acs.outcome_message,
    coalesce(acs.cycle_count, 0) as cycle_count,
    acs.last_intervention_type
  from public.pattern_alert_state pas
  left join public.alert_snoozes asn
    on asn.alert_id = pas.id
    and asn.user_id = auth.uid()
  left join public.alert_care_state acs
    on acs.alert_id = pas.id
  where pas.user_id in (
    select fm.user_id
    from public.family_members fm
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id is not null
      and fm.user_id != auth.uid()  -- Exclude current user (caregiver does not see own alerts)
  )
    and pas.episode_status = 'active'
    and pas.dismissed_at is null
    and (asn.snoozed_until is null or asn.snoozed_until < current_date)
    and (acs.care_state is null or acs.care_state != 'archived')
  order by pas.current_level desc, pas.active_since desc;
end;
$$;

comment on function public.get_family_pattern_alerts is
'Get active pattern alerts for family. Excludes current user. Returns care state and intervention fields. Snooze is per-user.';
