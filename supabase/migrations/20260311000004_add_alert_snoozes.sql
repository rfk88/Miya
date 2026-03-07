-- =====================================================
-- alert_snoozes: per-user snooze on a pattern alert.
-- Referenced by get_family_pattern_alerts (LEFT JOIN).
-- Also used by snooze_pattern_alert and dismiss_pattern_alert RPCs.
-- =====================================================

-- 1. Create alert_snoozes table
create table if not exists public.alert_snoozes (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  alert_id       uuid not null references public.pattern_alert_state(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,

  -- When to stop hiding the alert (null = permanent / dismissed)
  snoozed_until  date,
  snooze_days    int,

  -- If true, never show this alert to this user again (permanent dismiss)
  is_dismissed   boolean not null default false,

  unique (alert_id, user_id)
);

create index if not exists idx_alert_snoozes_alert  on public.alert_snoozes (alert_id);
create index if not exists idx_alert_snoozes_user   on public.alert_snoozes (user_id);
create index if not exists idx_alert_snoozes_active on public.alert_snoozes (user_id, snoozed_until)
  where is_dismissed = false;

-- 2. updated_at trigger
drop trigger if exists update_alert_snoozes_updated_at on public.alert_snoozes;
create trigger update_alert_snoozes_updated_at
  before update on public.alert_snoozes
  for each row execute function public.update_updated_at_column();

comment on table public.alert_snoozes is
'Per-user snooze/dismiss state for a pattern alert. A snoozed alert is hidden until snoozed_until. A dismissed alert is hidden permanently.';

-- 3. RLS: family members can read their own snooze records
alter table public.alert_snoozes enable row level security;

drop policy if exists "alert_snoozes_read_own" on public.alert_snoozes;
create policy "alert_snoozes_read_own"
  on public.alert_snoozes
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "alert_snoozes_block_direct_write" on public.alert_snoozes;
create policy "alert_snoozes_block_direct_write"
  on public.alert_snoozes
  for all
  to authenticated
  using (false)
  with check (false);

-- =====================================================
-- snooze_pattern_alert RPC
-- Hides an alert for N days for the calling user.
-- =====================================================
create or replace function public.snooze_pattern_alert(
  alert_id     uuid,
  snooze_for_days int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  snooze_date date;
begin
  -- Verify the caller is in the same family as the alert's subject
  if not exists (
    select 1
    from public.pattern_alert_state pas
    join public.family_members fm_subject on fm_subject.user_id = pas.user_id
    join public.family_members fm_caller  on fm_caller.family_id = fm_subject.family_id
    where pas.id = snooze_pattern_alert.alert_id
      and fm_caller.user_id = auth.uid()
  ) then
    raise exception 'Not authorized to snooze this alert';
  end if;

  snooze_date := current_date + snooze_for_days;

  insert into public.alert_snoozes (alert_id, user_id, snoozed_until, snooze_days, is_dismissed)
  values (snooze_pattern_alert.alert_id, auth.uid(), snooze_date, snooze_for_days, false)
  on conflict (alert_id, user_id) do update
    set snoozed_until = excluded.snoozed_until,
        snooze_days   = excluded.snooze_days,
        is_dismissed  = false,
        updated_at    = now();

  return jsonb_build_object('success', true, 'snoozed_until', snooze_date);
end;
$$;

comment on function public.snooze_pattern_alert is
'Snooze a pattern alert for N days for the calling user.';

-- =====================================================
-- dismiss_pattern_alert RPC
-- Permanently hides an alert for the calling user.
-- =====================================================
create or replace function public.dismiss_pattern_alert(
  alert_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verify the caller is in the same family as the alert's subject
  if not exists (
    select 1
    from public.pattern_alert_state pas
    join public.family_members fm_subject on fm_subject.user_id = pas.user_id
    join public.family_members fm_caller  on fm_caller.family_id = fm_subject.family_id
    where pas.id = dismiss_pattern_alert.alert_id
      and fm_caller.user_id = auth.uid()
  ) then
    raise exception 'Not authorized to dismiss this alert';
  end if;

  insert into public.alert_snoozes (alert_id, user_id, snoozed_until, snooze_days, is_dismissed)
  values (dismiss_pattern_alert.alert_id, auth.uid(), null, null, true)
  on conflict (alert_id, user_id) do update
    set snoozed_until = null,
        snooze_days   = null,
        is_dismissed  = true,
        updated_at    = now();

  return jsonb_build_object('success', true);
end;
$$;

comment on function public.dismiss_pattern_alert is
'Permanently hide a pattern alert for the calling user.';
