-- =====================================================
-- Fix create_challenge: any family member can issue a challenge,
-- not just admins. Remove the admin/superadmin role gate.
-- Also fixes record_alert_intervention param naming (p_ prefix to avoid
-- column name ambiguity) and respond_to_challenge kept with _ prefix.
-- =====================================================

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

  -- Caller just needs to be in a family (any role)
  select fm.family_id
  into caller_family_id
  from public.family_members fm
  where fm.user_id = caller_user_id
  limit 1;

  if caller_family_id is null then
    raise exception 'Caller is not a member of any family';
  end if;

  -- Recipient must be in the same family
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

  -- Enqueue a challenge invite notification for the member
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
  'Create a new pending_invite challenge for a family member. Any family member can issue a challenge. Enforces one active/pending challenge per member.';
