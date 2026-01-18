-- =====================================================
-- Add quiet hours preferences with granular control
-- Add timezone support
-- Extend snooze functionality
-- =====================================================

-- 1. Add quiet hours notification level and timezone to user_profiles
alter table public.user_profiles
add column if not exists quiet_hours_notification_level text default 'none' check (quiet_hours_notification_level in ('all', 'critical_only', 'none')),
add column if not exists timezone text default 'UTC';

comment on column public.user_profiles.quiet_hours_notification_level is 
'Notification behavior during quiet hours: all (send all), critical_only (only critical alerts), none (no notifications)';

comment on column public.user_profiles.timezone is 
'User timezone in IANA format (e.g., America/New_York, Europe/London). Used to determine quiet hours in local time.';

-- 2. Add snooze_days to pattern_alert_state for easier snooze calculation
alter table public.pattern_alert_state
add column if not exists snooze_days int;

comment on column public.pattern_alert_state.snooze_days is 
'Number of days the alert was snoozed for (1, 3, 7 days). Stored for UI display.';

-- 3. Add notification_queue status 'skipped' for quiet hours/preferences
alter table public.notification_queue
drop constraint if exists notification_queue_status_check;

alter table public.notification_queue
add constraint notification_queue_status_check
check (status in ('pending', 'sent', 'failed', 'skipped'));

comment on column public.notification_queue.status is 
'Notification status: pending (waiting to send), sent (delivered), failed (delivery failed), skipped (blocked by user preferences/quiet hours)';

-- 4. Create device_tokens table for push notifications
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,

  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null, -- APNs or FCM token
  platform text not null check (platform in ('ios', 'android')),
  app_version text,
  os_version text,
  is_active boolean default true,
  last_used_at timestamptz default now()
);

create unique index if not exists idx_device_tokens_user_token
  on public.device_tokens (user_id, device_token);

create index if not exists idx_device_tokens_active
  on public.device_tokens (user_id, is_active);

comment on table public.device_tokens is 
'Stores device push notification tokens for APNs (iOS) and FCM (Android/cross-platform)';

-- 5. Add updated_at trigger for device_tokens
drop trigger if exists update_device_tokens_updated_at on public.device_tokens;
create trigger update_device_tokens_updated_at
  before update on public.device_tokens
  for each row
  execute function public.update_updated_at_column();

-- 6. RPC: Snooze notification alert
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

  -- Update alert state
  update public.pattern_alert_state
  set 
    snooze_until = snooze_until_date,
    snooze_days = snooze_for_days,
    updated_at = now()
  where id = snooze_pattern_alert.alert_id;

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
'Snooze a pattern alert for specified number of days. Only family members can snooze alerts.';

-- 7. RPC: Dismiss notification alert
drop function if exists public.dismiss_pattern_alert(uuid);
create or replace function public.dismiss_pattern_alert(
  alert_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  alert_user_id uuid;
  result jsonb;
begin
  -- Verify caller has access to this alert (is family member)
  select pas.user_id
  from public.pattern_alert_state pas
  join public.family_members fm on fm.user_id = pas.user_id
  where pas.id = dismiss_pattern_alert.alert_id
    and fm.family_id in (
      select family_id
      from public.family_members
      where user_id = auth.uid()
    )
  into alert_user_id;

  if alert_user_id is null then
    raise exception 'Not authorized to dismiss this alert';
  end if;

  -- Update alert state
  update public.pattern_alert_state
  set 
    dismissed_at = now(),
    updated_at = now()
  where id = dismiss_pattern_alert.alert_id;

  -- Return result
  result := jsonb_build_object(
    'success', true,
    'alert_id', dismiss_pattern_alert.alert_id,
    'dismissed_at', now()
  );

  return result;
end;
$$;

comment on function public.dismiss_pattern_alert is 
'Dismiss a pattern alert permanently. Only family members can dismiss alerts.';

-- 8. RPC: Register device token for push notifications
drop function if exists public.register_device_token(text, text, text, text);
create or replace function public.register_device_token(
  token text,
  platform_type text,
  app_ver text default null,
  os_ver text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  -- Upsert device token
  insert into public.device_tokens (
    user_id,
    device_token,
    platform,
    app_version,
    os_version,
    is_active,
    last_used_at
  ) values (
    auth.uid(),
    token,
    platform_type,
    app_ver,
    os_ver,
    true,
    now()
  )
  on conflict (user_id, device_token)
  do update set
    is_active = true,
    app_version = excluded.app_version,
    os_version = excluded.os_version,
    last_used_at = now(),
    updated_at = now();

  result := jsonb_build_object(
    'success', true,
    'token', token,
    'platform', platform_type
  );

  return result;
end;
$$;

comment on function public.register_device_token is 
'Register or update device push notification token for current user';

-- 9. Update get_family_pattern_alerts to respect snooze and dismissal
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
    pas.snooze_until,
    pas.snooze_days,
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
    and pas.dismissed_at is null
    and (pas.snooze_until is null or pas.snooze_until < current_date)
  order by pas.current_level desc, pas.active_since desc;
end;
$$;

comment on function public.get_family_pattern_alerts is 
'Get active pattern alerts for family, excluding dismissed and currently snoozed alerts';
