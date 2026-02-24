-- =====================================================
-- FAMILY CHALLENGES (NOTIFICATION-DRIVEN)
-- =====================================================
-- Lightweight 7-day challenges that can be started from
-- family trend notifications to help members get back
-- to their baseline for a given vitality pillar.
--
-- All state lives in this table; iOS is a thin client.
-- =====================================================

-- 1) Core table

create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  family_id uuid not null references public.families(id) on delete cascade,
  member_user_id uuid not null references auth.users(id) on delete cascade,
  admin_user_id uuid not null references auth.users(id) on delete cascade,

  -- Vitality pillar this challenge is targeting
  pillar text not null check (pillar in ('sleep', 'movement', 'stress')),

  -- pending_invite: member has not accepted/declined yet
  -- active: member accepted, 7-day window in progress
  -- completed_success: finished with >= required_success_days
  -- completed_failed: finished with < required_success_days or explicitly failed
  status text not null default 'pending_invite'
    check (status in ('pending_invite', 'active', 'completed_success', 'completed_failed')),

  -- When the member accepted the challenge (day 1) and when it should end
  start_date date,
  end_date date,

  -- Progress tracking (computed by a daily job)
  days_succeeded int not null default 0,
  days_evaluated int not null default 0,
  required_success_days int not null default 5,
  last_evaluated_at date,

  -- Optional link back to the pattern alert / insight that spawned this
  source_alert_state_id uuid references public.pattern_alert_state(id),

  -- Free-form JSON for future extensions (copy, thresholds, etc.)
  metadata jsonb default '{}'::jsonb
);

comment on table public.challenges is
  '7-day challenges started from family notifications to help members get back to baseline for a given vitality pillar.';

comment on column public.challenges.family_id is
  'Family that owns this challenge; used to enforce that only family members/admins can see it.';

comment on column public.challenges.member_user_id is
  'Family member who is doing the challenge.';

comment on column public.challenges.admin_user_id is
  'Admin/superadmin who initiated the challenge from a family notification.';

comment on column public.challenges.pillar is
  'Vitality pillar targeted by this challenge: sleep, movement, or stress.';

comment on column public.challenges.status is
  'Challenge lifecycle status: pending_invite, active, completed_success, completed_failed.';

comment on column public.challenges.required_success_days is
  'Number of successful days required within the 7-day window (default 5).';

create index if not exists idx_challenges_member_status
  on public.challenges (member_user_id, status);

create index if not exists idx_challenges_family
  on public.challenges (family_id);

-- 2) Updated_at trigger

drop trigger if exists update_challenges_updated_at on public.challenges;
create trigger update_challenges_updated_at
  before update on public.challenges
  for each row
  execute function public.update_updated_at_column();

-- 3) Row Level Security

alter table public.challenges enable row level security;

-- Family members can read challenges for their family
drop policy if exists "challenges_read_family" on public.challenges;
create policy "challenges_read_family"
  on public.challenges
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = challenges.family_id
        and fm.user_id = auth.uid()
    )
  );

-- Inserts/updates will be performed via RPCs with security definer,
-- so we do not expose direct insert/update/delete to clients.
drop policy if exists "challenges_block_write_direct" on public.challenges;
create policy "challenges_block_write_direct"
  on public.challenges
  for all
  to authenticated
  using (false)
  with check (false);

-- 4) RPC: Create challenge (called by admin from iOS)

drop function if exists public.create_challenge(uuid, text, uuid) cascade;
create or replace function public.create_challenge(
  _member_user_id uuid,
  _pillar text,
  _source_alert_state_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid;
  caller_family_id uuid;
  member_family_id uuid;
  existing_id uuid;
  new_id uuid;
begin
  caller_user_id := auth.uid();

  if caller_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Verify caller is admin/superadmin in a family that also contains the member
  select fm.family_id
  into caller_family_id
  from public.family_members fm
  where fm.user_id = caller_user_id
    and fm.role in ('admin', 'superadmin')
  limit 1;

  if caller_family_id is null then
    raise exception 'Only family admins can start challenges';
  end if;

  select fm.family_id
  into member_family_id
  from public.family_members fm
  where fm.user_id = _member_user_id
    and fm.family_id = caller_family_id
  limit 1;

  if member_family_id is null then
    raise exception 'Member not in same family';
  end if;

  -- Enforce one active/pending challenge per member
  select id
  into existing_id
  from public.challenges c
  where c.member_user_id = _member_user_id
    and c.status in ('pending_invite', 'active')
  limit 1;

  if existing_id is not null then
    return jsonb_build_object(
      'success', false,
      'error', 'active_challenge_exists',
      'challenge_id', existing_id
    );
  end if;

  -- Create challenge in pending_invite state
  insert into public.challenges (
    family_id,
    member_user_id,
    admin_user_id,
    pillar,
    status,
    source_alert_state_id
  ) values (
    caller_family_id,
    _member_user_id,
    caller_user_id,
    _pillar,
    'pending_invite',
    _source_alert_state_id
  )
  returning id into new_id;

  -- Enqueue a challenge invite notification for the member.
  insert into public.notification_queue (
    recipient_user_id,
    member_user_id,
    alert_state_id,
    channel,
    payload,
    status
  ) values (
    _member_user_id,
    _member_user_id,
    _source_alert_state_id,
    'push',
    jsonb_build_object(
      'kind', 'challenge_invite',
      'challenge_id', new_id,
      'pillar', _pillar,
      'admin_user_id', caller_user_id
    ),
    'pending'
  );

  return jsonb_build_object(
    'success', true,
    'challenge_id', new_id
  );
end;
$$;

comment on function public.create_challenge is
  'Create a new pending_invite challenge for a family member and pillar. Enforces one active/pending challenge per member.';

-- 5) RPC: Accept/decline challenge (called by member)

drop function if exists public.respond_to_challenge(uuid, text) cascade;
create or replace function public.respond_to_challenge(
  _challenge_id uuid,
  _action text -- 'accept' or 'decline'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid;
  challenge_record public.challenges%rowtype;
  new_status text;
  today date;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into challenge_record
  from public.challenges c
  where c.id = _challenge_id;

  if not found then
    raise exception 'Challenge not found';
  end if;

  if challenge_record.member_user_id <> caller_user_id then
    raise exception 'Only the challenged member can respond';
  end if;

  if challenge_record.status <> 'pending_invite' then
    return jsonb_build_object(
      'success', false,
      'error', 'challenge_not_pending'
    );
  end if;

  if _action = 'accept' then
    today := current_date;
    update public.challenges
    set
      status = 'active',
      start_date = today,
      end_date = today + 6,
      days_succeeded = 0,
      days_evaluated = 0,
      last_evaluated_at = null,
      updated_at = now()
    where id = _challenge_id;
    new_status := 'active';
  elsif _action = 'decline' then
    update public.challenges
    set
      status = 'completed_failed',
      updated_at = now()
    where id = _challenge_id;
    new_status := 'completed_failed';
  else
    raise exception 'Invalid action. Must be accept or decline';
  end if;

  return jsonb_build_object(
    'success', true,
    'status', new_status
  );
end;
$$;

comment on function public.respond_to_challenge is
  'Member response to a pending challenge: accept (starts 7-day window) or decline.';

-- 6) RPC: Get active challenge for current user (helper)

drop function if exists public.get_active_challenge_for_member() cascade;
create or replace function public.get_active_challenge_for_member()
returns table (
  id uuid,
  family_id uuid,
  member_user_id uuid,
  admin_user_id uuid,
  pillar text,
  status text,
  start_date date,
  end_date date,
  days_succeeded int,
  days_evaluated int,
  required_success_days int
)
language sql
security definer
set search_path = public
as $$
  select
    c.id,
    c.family_id,
    c.member_user_id,
    c.admin_user_id,
    c.pillar,
    c.status,
    c.start_date,
    c.end_date,
    c.days_succeeded,
    c.days_evaluated,
    c.required_success_days
  from public.challenges c
  where c.member_user_id = auth.uid()
    and c.status = 'active'
  order by c.start_date desc
  limit 1;
$$;

comment on function public.get_active_challenge_for_member is
  'Return the current active challenge for the authenticated member, if any.';

