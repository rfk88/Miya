-- Atomic pattern-alert enqueue: N notification_queue rows + single last_notified_level bump.
-- Idempotent per (alert_state_id, level): skips if any row already exists for that episode level.

create or replace function public.miya_pattern_alert_enqueue_and_bump(
  p_alert_state_id uuid,
  p_member_user_id uuid,
  p_new_level integer,
  p_metric_type text,
  p_pattern_type text,
  p_active_since text,
  p_evaluated_end_date text,
  p_deviation_percent double precision,
  p_sole_in_app_family_lead boolean,
  p_other_lead_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  base jsonb;
  r uuid;
begin
  if exists (
    select 1
    from public.notification_queue q
    where q.alert_state_id = p_alert_state_id
      and coalesce((q.payload->>'level')::int, -1) = p_new_level
      and q.status in ('pending', 'sent', 'skipped')
  ) then
    return;
  end if;

  base := jsonb_build_object(
    'kind', 'pattern_alert',
    'member_user_id', p_member_user_id::text,
    'metric_type', p_metric_type,
    'pattern_type', p_pattern_type,
    'level', p_new_level,
    'active_since', p_active_since,
    'evaluated_end_date', p_evaluated_end_date,
    'deviation_percent', p_deviation_percent,
    'audience', 'member',
    'sole_in_app_family_lead', p_sole_in_app_family_lead
  );

  insert into public.notification_queue (
    recipient_user_id,
    member_user_id,
    alert_state_id,
    channel,
    payload,
    status
  ) values (
    p_member_user_id,
    p_member_user_id,
    p_alert_state_id,
    'push',
    base,
    'pending'
  );

  foreach r in array coalesce(p_other_lead_ids, '{}')
  loop
    if r is null or r = p_member_user_id then
      continue;
    end if;

    insert into public.notification_queue (
      recipient_user_id,
      member_user_id,
      alert_state_id,
      channel,
      payload,
      status
    ) values (
      r,
      p_member_user_id,
      p_alert_state_id,
      'push',
      base || jsonb_build_object('audience', 'family_lead'),
      'pending'
    );
  end loop;

  update public.pattern_alert_state
  set
    last_notified_level = p_new_level,
    last_notified_at = now(),
    updated_at = now()
  where id = p_alert_state_id;
end;
$$;

comment on function public.miya_pattern_alert_enqueue_and_bump is
  'Inserts pattern_alert notification_queue rows (member + optional family leads) and bumps last_notified_level atomically.';

revoke all on function public.miya_pattern_alert_enqueue_and_bump(
  uuid, uuid, integer, text, text, text, text, double precision, boolean, uuid[]
) from public;

grant execute on function public.miya_pattern_alert_enqueue_and_bump(
  uuid, uuid, integer, text, text, text, text, double precision, boolean, uuid[]
) to service_role;

-- Optional future: link onboarding champion to a Miya account for push (see notification plan Part II.3).
alter table public.user_profiles
  add column if not exists champion_user_id uuid references auth.users (id) on delete set null;

comment on column public.user_profiles.champion_user_id is
  'When set, this Miya user may be merged into pattern-alert family-lead push recipients (future).';
