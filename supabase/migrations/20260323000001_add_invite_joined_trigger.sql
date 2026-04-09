-- =====================================================
-- Trigger: notify family admins when a member accepts their invite
-- =====================================================
-- Fires AFTER UPDATE on family_members when invite_status transitions
-- to 'accepted'. Inserts one notification_queue row per family admin
-- so each family admin gets a push + bell notification.
-- =====================================================

create or replace function public.notify_family_on_invite_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_rec record;
begin
  -- Safety guard: user_id must be set (completeInviteRedemption sets it
  -- in the same UPDATE, but guard defensively).
  if NEW.user_id is null then
    return NEW;
  end if;

  -- Idempotency guard: skip if we already queued an invite_joined notification
  -- for this member (prevents duplicates if the row is updated again).
  if exists (
    select 1
    from public.notification_queue
    where member_user_id = NEW.user_id
      and payload->>'kind' = 'invite_joined'
  ) then
    return NEW;
  end if;

  -- Notify every accepted superadmin/admin in the same family,
  -- excluding the member who just joined.
  for admin_rec in
    select user_id
    from public.family_members
    where family_id     = NEW.family_id
      and role          in ('superadmin', 'admin')
      and invite_status = 'accepted'
      and user_id       is not null
      and user_id       != NEW.user_id
  loop
    insert into public.notification_queue (
      recipient_user_id,
      member_user_id,
      alert_state_id,
      channel,
      status,
      payload
    ) values (
      admin_rec.user_id,
      NEW.user_id,
      null,
      'push',
      'pending',
      jsonb_build_object(
        'kind',              'invite_joined',
        'member_user_id',    NEW.user_id::text,
        'member_first_name', NEW.first_name,
        'family_id',         NEW.family_id::text,
        'severity',          'info'
      )
    );
  end loop;

  return NEW;
end;
$$;

-- Drop and recreate the trigger so this migration is idempotent.
drop trigger if exists trg_notify_invite_accepted on public.family_members;

create trigger trg_notify_invite_accepted
  after update on public.family_members
  for each row
  when (
    NEW.invite_status = 'accepted'
    and OLD.invite_status is distinct from 'accepted'
  )
  execute function public.notify_family_on_invite_accepted();

comment on function public.notify_family_on_invite_accepted() is
  'Inserts a notification_queue row for each family admin when a member accepts their invite.';
