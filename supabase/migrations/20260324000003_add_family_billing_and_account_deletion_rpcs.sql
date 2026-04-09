-- =====================================================
-- Family billing ownership + account deletion flow
-- =====================================================

alter table if exists public.families
  add column if not exists billing_status text not null default 'active'
    check (billing_status in ('active', 'grace_pending_new_owner', 'billing_required')),
  add column if not exists billing_owner_user_id uuid references auth.users(id) on delete set null,
  add column if not exists billing_grace_until timestamptz,
  add column if not exists billing_status_updated_at timestamptz not null default now();

create index if not exists idx_families_billing_status_grace
  on public.families (billing_status, billing_grace_until);

-- Backfill missing billing owner using family creator where available.
update public.families f
set billing_owner_user_id = f.created_by
where f.billing_owner_user_id is null
  and f.created_by is not null;

-- If we still have no owner after backfill, require billing action.
update public.families
set billing_status = 'billing_required',
    billing_status_updated_at = now()
where billing_owner_user_id is null
  and billing_status = 'active';

-- Enforce active => billing owner present.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'families_active_requires_billing_owner'
  ) then
    alter table public.families
      add constraint families_active_requires_billing_owner
      check (
        billing_status <> 'active'
        or billing_owner_user_id is not null
      );
  end if;
end $$;

-- Ensure timestamp moves on updates.
create or replace function public.touch_families_billing_status_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.billing_status is distinct from old.billing_status
     or new.billing_owner_user_id is distinct from old.billing_owner_user_id
     or new.billing_grace_until is distinct from old.billing_grace_until then
    new.billing_status_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_touch_families_billing_status_updated_at on public.families;
create trigger trg_touch_families_billing_status_updated_at
before update on public.families
for each row
execute function public.touch_families_billing_status_updated_at();

-- View-like RPC for app gating.
create or replace function public.get_my_family_billing_state()
returns table (
  family_id uuid,
  billing_status text,
  billing_owner_user_id uuid,
  billing_grace_until timestamptz,
  role text
)
language sql
security definer
set search_path = public
as $$
  select
    f.id as family_id,
    f.billing_status,
    f.billing_owner_user_id,
    f.billing_grace_until,
    fm.role
  from public.family_members fm
  join public.families f
    on f.id = fm.family_id
  where fm.user_id = auth.uid()
    and fm.invite_status = 'accepted'
  limit 1
$$;

comment on function public.get_my_family_billing_state is
  'Returns family billing status for the authenticated member.';

-- Any accepted family member can take over billing.
create or replace function public.claim_family_billing_owner()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  caller_family_id uuid;
begin
  if caller_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select fm.family_id
  into caller_family_id
  from public.family_members fm
  where fm.user_id = caller_user_id
    and fm.invite_status = 'accepted'
  limit 1;

  if caller_family_id is null then
    raise exception 'You are not in an accepted family';
  end if;

  update public.families f
  set billing_owner_user_id = caller_user_id,
      billing_status = 'active',
      billing_grace_until = null
  where f.id = caller_family_id;

  return jsonb_build_object(
    'success', true,
    'family_id', caller_family_id::text,
    'billing_owner_user_id', caller_user_id::text,
    'billing_status', 'active'
  );
end;
$$;

comment on function public.claim_family_billing_owner is
  'Assign current accepted member as billing owner and restore active billing status.';

-- Self-deletion side effects (family membership + billing state only).
create or replace function public.delete_my_account_with_family_billing()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  caller_member_id uuid;
  caller_family_id uuid;
  caller_role text;
  caller_is_billing_owner boolean := false;
  now_ts timestamptz := now();
  grace_until_ts timestamptz := now() + interval '7 days';
begin
  if caller_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select fm.id, fm.family_id, fm.role
  into caller_member_id, caller_family_id, caller_role
  from public.family_members fm
  where fm.user_id = caller_user_id
    and fm.invite_status = 'accepted'
  limit 1;

  -- Idempotent success if user is already not in a family.
  if caller_member_id is null then
    return jsonb_build_object(
      'success', true,
      'was_billing_owner', false,
      'family_changed', false
    );
  end if;

  select (f.billing_owner_user_id = caller_user_id)
  into caller_is_billing_owner
  from public.families f
  where f.id = caller_family_id;

  -- 1) Remove only this member row. This must not mutate other members.
  delete from public.family_members
  where id = caller_member_id;

  -- 2) If payer leaves, shift family into 7-day grace and notify accepted members.
  if caller_is_billing_owner then
    update public.families
    set billing_owner_user_id = null,
        billing_status = 'grace_pending_new_owner',
        billing_grace_until = grace_until_ts,
        billing_status_updated_at = now_ts
    where id = caller_family_id;

    insert into public.notification_queue (
      recipient_user_id,
      member_user_id,
      alert_state_id,
      channel,
      payload,
      status
    )
    select
      fm.user_id,
      caller_user_id,
      null,
      'push',
      jsonb_build_object(
        'kind', 'billing_owner_left',
        'family_id', caller_family_id::text,
        'grace_until', grace_until_ts,
        'takeover_allowed', true
      ),
      'pending'
    from public.family_members fm
    where fm.family_id = caller_family_id
      and fm.invite_status = 'accepted'
      and fm.user_id is not null;
  end if;

  return jsonb_build_object(
    'success', true,
    'was_billing_owner', caller_is_billing_owner,
    'role', coalesce(caller_role, 'member'),
    'family_changed', caller_is_billing_owner,
    'grace_until', case when caller_is_billing_owner then grace_until_ts else null end
  );
end;
$$;

comment on function public.delete_my_account_with_family_billing is
  'Removes current user from family and, if they were billing owner, starts 7-day grace and queues billing notifications.';

-- Expire grace windows and notify family once.
create or replace function public.expire_family_billing_grace()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  fam record;
  affected integer := 0;
begin
  for fam in
    select id
    from public.families
    where billing_status = 'grace_pending_new_owner'
      and billing_owner_user_id is null
      and billing_grace_until is not null
      and billing_grace_until < now()
  loop
    update public.families
    set billing_status = 'billing_required',
        billing_grace_until = null,
        billing_status_updated_at = now()
    where id = fam.id;

    insert into public.notification_queue (
      recipient_user_id,
      member_user_id,
      alert_state_id,
      channel,
      payload,
      status
    )
    select
      fm.user_id,
      fm.user_id,
      null,
      'push',
      jsonb_build_object(
        'kind', 'billing_interrupted',
        'family_id', fam.id::text
      ),
      'pending'
    from public.family_members fm
    where fm.family_id = fam.id
      and fm.invite_status = 'accepted'
      and fm.user_id is not null;

    affected := affected + 1;
  end loop;

  return affected;
end;
$$;

comment on function public.expire_family_billing_grace is
  'Transitions expired grace families to billing_required and queues interruption notifications.';
