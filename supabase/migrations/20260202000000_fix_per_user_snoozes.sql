-- =====================================================
-- Fix per-user notification snoozing
-- Problem: Snoozing alerts was global (affected entire family)
-- Solution: Create per-user snooze tracking table
-- =====================================================

-- 1. Create per-user snooze tracking table
create table if not exists public.alert_snoozes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,

  user_id uuid not null references auth.users(id) on delete cascade,
  alert_id uuid not null references public.pattern_alert_state(id) on delete cascade,
  snoozed_until date not null,
  snooze_days int not null,

  constraint alert_snoozes_unique_user_alert unique (user_id, alert_id)
);

create index if not exists idx_alert_snoozes_user 
  on public.alert_snoozes (user_id, snoozed_until);

create index if not exists idx_alert_snoozes_alert 
  on public.alert_snoozes (alert_id);

comment on table public.alert_snoozes is 
'Per-user snooze state for alerts. Each user can independently snooze/un-snooze alerts.';

comment on column public.alert_snoozes.user_id is 
'User who snoozed the alert (not the person the alert is about)';

comment on column public.alert_snoozes.alert_id is 
'Alert that was snoozed';

comment on column public.alert_snoozes.snoozed_until is 
'Date when snooze expires (alert becomes visible again)';

comment on column public.alert_snoozes.snooze_days is 
'Number of days the alert was snoozed for (1, 3, or 7). Stored for UI display.';

-- 2. Add updated_at trigger for alert_snoozes
drop trigger if exists update_alert_snoozes_updated_at on public.alert_snoozes;
create trigger update_alert_snoozes_updated_at
  before update on public.alert_snoozes
  for each row
  execute function public.update_updated_at_column();

-- 3. Replace snooze_pattern_alert function to use per-user snooze table
drop function if exists public.snooze_pattern_alert(uuid, int);
create or replace function public.snooze_pattern_alert(
  alert_id uuid,
  snooze_for_days int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  alert_user_id uuid;
  snooze_until_date date;
  result jsonb;
begin
  -- Verify caller has access to this alert (is family member)
  select pas.user_id
  from public.pattern_alert_state pas
  join public.family_members fm on fm.user_id = pas.user_id
  where pas.id = snooze_pattern_alert.alert_id
    and fm.family_id in (
      select family_id
      from public.family_members
      where user_id = auth.uid()
    )
  into alert_user_id;

  if alert_user_id is null then
    raise exception 'Not authorized to snooze this alert';
  end if;

  -- Calculate snooze until date
  snooze_until_date := current_date + snooze_for_days;

  -- Insert or update per-user snooze (NOT updating pattern_alert_state)
  insert into public.alert_snoozes (
    user_id,
    alert_id,
    snoozed_until,
    snooze_days
  ) values (
    auth.uid(),           -- Current user only
    snooze_pattern_alert.alert_id,
    snooze_until_date,
    snooze_for_days
  )
  on conflict (user_id, alert_id)
  do update set
    snoozed_until = excluded.snoozed_until,
    snooze_days = excluded.snooze_days,
    updated_at = now();

  -- Return result
  result := jsonb_build_object(
    'success', true,
    'alert_id', snooze_pattern_alert.alert_id,
    'snooze_until', snooze_until_date,
    'snooze_days', snooze_for_days
  );

  return result;
end;
$$;

comment on function public.snooze_pattern_alert is 
'Snooze a pattern alert for specified number of days FOR THE CURRENT USER ONLY. Other family members still see the alert.';

-- 4. Add unsnooze_pattern_alert function
drop function if exists public.unsnooze_pattern_alert(uuid);
create or replace function public.unsnooze_pattern_alert(
  alert_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
  rows_deleted int;
begin
  -- Delete the snooze record for current user
  delete from public.alert_snoozes
  where alert_id = unsnooze_pattern_alert.alert_id
    and user_id = auth.uid();
  
  get diagnostics rows_deleted = row_count;

  result := jsonb_build_object(
    'success', true,
    'alert_id', alert_id,
    'was_snoozed', rows_deleted > 0
  );

  return result;
end;
$$;

comment on function public.unsnooze_pattern_alert is 
'Remove snooze for current user, making alert visible immediately.';

-- 5. Update get_family_pattern_alerts to check per-user snoozes
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
    asn.snoozed_until,        -- From alert_snoozes (per-user)
    asn.snooze_days,           -- From alert_snoozes (per-user)
    pas.dismissed_at,
    pas.deviation_percent,
    pas.baseline_value,
    pas.recent_value
  from public.pattern_alert_state pas
  left join public.alert_snoozes asn 
    on asn.alert_id = pas.id 
    and asn.user_id = auth.uid()  -- Current viewer only!
  where pas.user_id in (
    select fm.user_id
    from public.family_members fm
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id is not null
  )
    and pas.episode_status = 'active'
    and pas.dismissed_at is null
    -- Check snooze for CURRENT user only (not global)
    and (asn.snoozed_until is null or asn.snoozed_until < current_date)
  order by pas.current_level desc, pas.active_since desc;
end;
$$;

comment on function public.get_family_pattern_alerts is 
'Get active pattern alerts for family. Snooze and visibility are per-user - each family member sees their own filtered view.';

-- 6. Deprecate old global snooze columns (keep for backwards compatibility)
comment on column public.pattern_alert_state.snooze_until is 
'DEPRECATED: Use alert_snoozes table instead. This column is no longer used. Each user now has their own snooze state.';

comment on column public.pattern_alert_state.snooze_days is 
'DEPRECATED: Use alert_snoozes table instead. This column is no longer used. Each user now has their own snooze state.';

-- Note: In future migration, these columns can be dropped:
-- alter table public.pattern_alert_state drop column snooze_until;
-- alter table public.pattern_alert_state drop column snooze_days;
