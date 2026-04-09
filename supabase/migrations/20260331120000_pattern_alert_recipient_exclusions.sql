-- Per-user exclusions for level-7+ pattern alert fan-out (same family only; Self Setup only).
-- Writes via set_pattern_alert_excluded_recipients (SECURITY DEFINER); rook reads with service_role.

create table if not exists public.pattern_alert_recipient_exclusions (
  subject_user_id uuid not null references auth.users (id) on delete cascade,
  excluded_user_id uuid not null references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (subject_user_id, excluded_user_id),
  constraint pattern_alert_exclusions_subject_ne_excluded check (subject_user_id <> excluded_user_id)
);

create index if not exists pattern_alert_recipient_exclusions_subject_idx
  on public.pattern_alert_recipient_exclusions (subject_user_id);

comment on table public.pattern_alert_recipient_exclusions is
  'Subject user excludes these family user_ids from receiving in-app pattern alerts about the subject at escalation level 7+. Engine intersects with same-family accepted members.';

alter table public.pattern_alert_recipient_exclusions enable row level security;

drop policy if exists "pattern_alert_exclusions_select_own" on public.pattern_alert_recipient_exclusions;
create policy "pattern_alert_exclusions_select_own"
  on public.pattern_alert_recipient_exclusions
  for select
  to authenticated
  using (subject_user_id = auth.uid());

-- No insert/update/delete policies for authenticated: mutations only via RPC below.

create or replace function public.set_pattern_alert_excluded_recipients(p_excluded_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subject uuid := auth.uid();
  v_family uuid;
  v_onboarding text;
  e uuid;
begin
  if v_subject is null then
    raise exception 'Not authenticated';
  end if;

  select fm.family_id, fm.onboarding_type
  into v_family, v_onboarding
  from public.family_members fm
  where fm.user_id = v_subject
    and fm.invite_status = 'accepted'
  limit 1;

  if v_family is null then
    raise exception 'No accepted family membership';
  end if;

  if v_onboarding = 'Guided Setup' then
    raise exception 'Pattern alert recipient preferences are not available for Guided Setup.';
  end if;

  delete from public.pattern_alert_recipient_exclusions
  where subject_user_id = v_subject;

  foreach e in array coalesce(p_excluded_user_ids, '{}')
  loop
    if e is null or e = v_subject then
      continue;
    end if;
    if exists (
      select 1
      from public.family_members fm2
      where fm2.family_id = v_family
        and fm2.user_id = e
        and fm2.invite_status = 'accepted'
        and fm2.user_id is not null
    ) then
      insert into public.pattern_alert_recipient_exclusions (subject_user_id, excluded_user_id)
      values (v_subject, e);
    end if;
  end loop;
end;
$$;

comment on function public.set_pattern_alert_excluded_recipients is
  'Replaces subject''s pattern-alert recipient exclusions. Validates same-family accepted members; rejects Guided Setup.';

revoke all on function public.set_pattern_alert_excluded_recipients(uuid[]) from public;
grant execute on function public.set_pattern_alert_excluded_recipients(uuid[]) to authenticated;
grant execute on function public.set_pattern_alert_excluded_recipients(uuid[]) to service_role;

-- Replace enqueue RPC (signature gains p_family_notified_in_app); drop old overload so only one exists.
drop function if exists public.miya_pattern_alert_enqueue_and_bump(
  uuid, uuid, integer, text, text, text, text, double precision, boolean, uuid[]
);

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
  p_family_notified_in_app boolean,
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
    'sole_in_app_family_lead', p_sole_in_app_family_lead,
    'family_notified_in_app', p_family_notified_in_app
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
  'Inserts pattern_alert notification_queue rows (member + optional family recipients) and bumps last_notified_level atomically.';

revoke all on function public.miya_pattern_alert_enqueue_and_bump(
  uuid, uuid, integer, text, text, text, text, double precision, boolean, boolean, uuid[]
) from public;

grant execute on function public.miya_pattern_alert_enqueue_and_bump(
  uuid, uuid, integer, text, text, text, text, double precision, boolean, boolean, uuid[]
) to service_role;
