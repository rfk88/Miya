-- =====================================================
-- Family Care Loop: record_alert_intervention RPC
-- Called when a caregiver acts (challenge, reach_out, check_in, etc.).
-- Inserts into alert_interventions and upserts alert_care_state.
-- =====================================================

drop function if exists public.record_alert_intervention(uuid, text, uuid);

create or replace function public.record_alert_intervention(
  _alert_id uuid,
  _intervention_type text,
  _challenge_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  _caller_id uuid;
  _alert_user_id uuid;
  _current_level int;
  _pre_action_value numeric;
  _follow_up_days int;
  _follow_up_due date;
begin
  _caller_id := auth.uid();
  if _caller_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Validate: caller is in same family as the alert's user
  select pas.user_id, pas.current_level, pas.recent_value
  into _alert_user_id, _current_level, _pre_action_value
  from public.pattern_alert_state pas
  join public.family_members fm_alert on fm_alert.user_id = pas.user_id
  where pas.id = _alert_id
    and exists (
      select 1
      from public.family_members fm_caller
      where fm_caller.user_id = _caller_id
        and fm_caller.family_id = fm_alert.family_id
    );

  if _alert_user_id is null then
    raise exception 'Alert not found or not authorized';
  end if;

  -- Follow-up window by alert level
  _follow_up_days := case
    when _current_level <= 3 then 3
    when _current_level <= 7 then 5
    when _current_level <= 14 then 7
    else 10
  end;
  _follow_up_due := current_date + _follow_up_days;

  -- Insert into ledger
  insert into public.alert_interventions (
    alert_id,
    user_id,
    intervention_type,
    challenge_id
  ) values (
    _alert_id,
    _caller_id,
    _intervention_type,
    _challenge_id
  );

  -- Upsert alert_care_state
  insert into public.alert_care_state (
    alert_id,
    care_state,
    last_intervention_type,
    acted_by_user_id,
    acted_at,
    pre_action_recent_value,
    follow_up_due_date,
    outcome_evaluated_at,
    outcome_message,
    cycle_count
  ) values (
    _alert_id,
    'monitoring',
    _intervention_type,
    _caller_id,
    now(),
    _pre_action_value,
    _follow_up_due,
    null,
    null,
    1
  )
  on conflict (alert_id)
  do update set
    care_state = 'monitoring',
    last_intervention_type = excluded.last_intervention_type,
    acted_by_user_id = excluded.acted_by_user_id,
    acted_at = excluded.acted_at,
    pre_action_recent_value = excluded.pre_action_recent_value,
    follow_up_due_date = excluded.follow_up_due_date,
    outcome_evaluated_at = null,
    outcome_message = null,
    cycle_count = alert_care_state.cycle_count + 1,
    updated_at = now();

  return jsonb_build_object(
    'success', true,
    'alert_id', _alert_id,
    'follow_up_due_date', _follow_up_due,
    'follow_up_days', _follow_up_days
  );
end;
$$;

comment on function public.record_alert_intervention is
'Record a caregiver action on an alert (challenge, reach_out, check_in, etc.). Updates care state and sets follow-up date by alert level.';
