-- Phase 2 RPCs for BIG competitive challenges.
-- All RPCs are SECURITY DEFINER and validate family membership via auth.uid().
--
-- Public surface:
--   * create_competitive_challenge(focus, invitee_user_ids[])  -> jsonb (challenge_id)
--   * respond_competitive_invite(challenge_id, action)         -> jsonb (status, all_accepted)
--   * get_competitive_challenges_for_family(family_id)         -> table
--   * get_competitive_challenge_detail(challenge_id)           -> table  (one-row-per-participant)

-- ============================================================================
-- 1) create_competitive_challenge
-- ============================================================================
drop function if exists public.create_competitive_challenge(text, uuid[]);

create or replace function public.create_competitive_challenge(
  focus text,
  invitee_user_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid;
  caller_family_id uuid;
  participant_user_ids uuid[];
  unique_invitees uuid[];
  invitee uuid;
  new_id uuid;
  mode_value text;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if focus not in ('sleep', 'movement', 'stress', 'steps') then
    return jsonb_build_object('success', false, 'error', 'invalid_focus');
  end if;

  if invitee_user_ids is null or array_length(invitee_user_ids, 1) is null then
    return jsonb_build_object('success', false, 'error', 'no_participants_selected');
  end if;

  -- Deduplicate + filter self out of invitee list. The caller is always a participant.
  select array_agg(distinct x)
    into unique_invitees
    from unnest(invitee_user_ids) as x
    where x is not null and x <> caller_user_id;

  if unique_invitees is null or array_length(unique_invitees, 1) is null then
    return jsonb_build_object('success', false, 'error', 'no_participants_selected');
  end if;

  -- The caller's family is the source of truth; all invitees must share it.
  select fm.family_id into caller_family_id
  from public.family_members fm
  where fm.user_id = caller_user_id
  limit 1;

  if caller_family_id is null then
    return jsonb_build_object('success', false, 'error', 'not_in_family');
  end if;

  -- Validate every invitee is in the same family (accepted status not required:
  -- pending members can still be invited and accept once onboarded if product allows;
  -- in practice the client filters to status='accepted').
  perform 1
    from unnest(unique_invitees) as inv(uid)
    where not exists (
      select 1 from public.family_members fm
      where fm.family_id = caller_family_id and fm.user_id = inv.uid
    )
    limit 1;
  if found then
    return jsonb_build_object('success', false, 'error', 'member_not_in_same_family');
  end if;

  participant_user_ids := array_prepend(caller_user_id, unique_invitees);

  if array_length(participant_user_ids, 1) < 2 then
    return jsonb_build_object('success', false, 'error', 'no_participants_selected');
  end if;
  if array_length(participant_user_ids, 1) > 6 then
    return jsonb_build_object('success', false, 'error', 'family_brawl_max_6_participants');
  end if;

  mode_value := case when array_length(participant_user_ids, 1) > 2
                     then 'family_brawl' else 'head_to_head' end;

  insert into public.big_competitive_challenges (family_id, mode, focus, status, created_by)
  values (caller_family_id, mode_value, focus, 'pending_accepts', caller_user_id)
  returning id into new_id;

  -- Caller auto-accepts at creation (they're proposing it).
  insert into public.big_competitive_participants (challenge_id, user_id, invite_status, accepted_at)
  values (new_id, caller_user_id, 'accepted', now());

  -- Insert invitee rows + enqueue invite notifications.
  foreach invitee in array unique_invitees loop
    insert into public.big_competitive_participants (challenge_id, user_id, invite_status)
    values (new_id, invitee, 'pending');

    insert into public.notification_queue (
      recipient_user_id, member_user_id, alert_state_id, channel, payload, status
    ) values (
      invitee, caller_user_id, null, 'push',
      jsonb_build_object(
        'kind', 'competitive_challenge_invite',
        'challenge_id', new_id,
        'focus', focus,
        'mode', mode_value,
        'from_user_id', caller_user_id
      ),
      'pending'
    );
  end loop;

  return jsonb_build_object(
    'success', true,
    'challenge_id', new_id,
    'mode', mode_value,
    'participant_count', array_length(participant_user_ids, 1)
  );
end;
$$;

comment on function public.create_competitive_challenge is
  'Create a competitive challenge in pending_accepts; invitees get push invites.';

revoke all on function public.create_competitive_challenge(text, uuid[]) from public;
grant execute on function public.create_competitive_challenge(text, uuid[]) to authenticated;

-- ============================================================================
-- 2) respond_competitive_invite
-- ============================================================================
drop function if exists public.respond_competitive_invite(uuid, text);

create or replace function public.respond_competitive_invite(
  p_challenge_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid;
  v_challenge public.big_competitive_challenges%rowtype;
  v_participant public.big_competitive_participants%rowtype;
  v_pending_count int;
  v_all_accepted boolean := false;
  v_now timestamptz := now();
  v_start_date date;
  v_end_date date;
  v_recipient_user_id uuid;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if p_action not in ('accept', 'decline') then
    return jsonb_build_object('success', false, 'error', 'invalid_action');
  end if;

  select * into v_challenge
  from public.big_competitive_challenges
  where id = p_challenge_id
  for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'challenge_not_found');
  end if;

  if v_challenge.status <> 'pending_accepts' then
    return jsonb_build_object('success', false, 'error', 'challenge_not_pending');
  end if;

  select * into v_participant
  from public.big_competitive_participants
  where challenge_id = p_challenge_id and user_id = caller_user_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'not_a_participant');
  end if;

  if v_participant.invite_status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'already_responded');
  end if;

  if p_action = 'accept' then
    update public.big_competitive_participants
    set invite_status = 'accepted', accepted_at = v_now
    where id = v_participant.id;

    select count(*) into v_pending_count
    from public.big_competitive_participants
    where challenge_id = p_challenge_id and invite_status = 'pending';

    if v_pending_count = 0 then
      -- Compute Mon..Sun anchored on the date the last accept landed (server local).
      v_start_date := (date_trunc('week', v_now)::date); -- Postgres week starts Monday by default.
      v_end_date := v_start_date + 6;

      update public.big_competitive_challenges
      set status = 'active',
          start_date = v_start_date,
          end_date = v_end_date,
          activated_at = v_now
      where id = p_challenge_id;

      v_all_accepted := true;

      -- Inform all participants that the challenge has started.
      insert into public.notification_queue (
        recipient_user_id, member_user_id, alert_state_id, channel, payload, status
      )
      select
        p.user_id,
        v_challenge.created_by,
        null,
        'push',
        jsonb_build_object(
          'kind', 'competitive_challenge_started',
          'challenge_id', p_challenge_id,
          'focus', v_challenge.focus,
          'mode', v_challenge.mode,
          'start_date', v_start_date,
          'end_date', v_end_date
        ),
        'pending'
      from public.big_competitive_participants p
      where p.challenge_id = p_challenge_id;
    else
      -- Notify the creator that someone accepted.
      insert into public.notification_queue (
        recipient_user_id, member_user_id, alert_state_id, channel, payload, status
      ) values (
        v_challenge.created_by, caller_user_id, null, 'push',
        jsonb_build_object(
          'kind', 'competitive_challenge_invite_accepted',
          'challenge_id', p_challenge_id,
          'by_user_id', caller_user_id,
          'pending_count', v_pending_count
        ),
        'pending'
      );
    end if;

  elsif p_action = 'decline' then
    update public.big_competitive_participants
    set invite_status = 'declined'
    where id = v_participant.id;

    -- A single decline collapses the challenge. Cancel everyone (refund the rest's pending state).
    update public.big_competitive_challenges
    set status = 'cancelled'
    where id = p_challenge_id;

    -- Notify all other participants once.
    for v_recipient_user_id in
      select user_id from public.big_competitive_participants
      where challenge_id = p_challenge_id and user_id <> caller_user_id
    loop
      insert into public.notification_queue (
        recipient_user_id, member_user_id, alert_state_id, channel, payload, status
      ) values (
        v_recipient_user_id, caller_user_id, null, 'push',
        jsonb_build_object(
          'kind', 'competitive_challenge_declined',
          'challenge_id', p_challenge_id,
          'by_user_id', caller_user_id
        ),
        'pending'
      );
    end loop;
  end if;

  return jsonb_build_object(
    'success', true,
    'status', case when p_action = 'accept' and v_all_accepted then 'active'
                   when p_action = 'accept' then 'pending_accepts'
                   else 'cancelled' end,
    'all_accepted', v_all_accepted
  );
end;
$$;

comment on function public.respond_competitive_invite is
  'Accept or decline a competitive challenge invite. Mutual accept activates the Mon–Sun window.';

revoke all on function public.respond_competitive_invite(uuid, text) from public;
grant execute on function public.respond_competitive_invite(uuid, text) to authenticated;

-- ============================================================================
-- 3) get_competitive_challenges_for_family
-- ============================================================================
create or replace function public.get_competitive_challenges_for_family(p_family_id uuid)
returns table (
  id uuid,
  family_id uuid,
  mode text,
  focus text,
  status text,
  start_date date,
  end_date date,
  created_at timestamptz,
  completed_at timestamptz,
  created_by uuid,
  winner_user_id uuid,
  tie_break_used boolean,
  my_invite_status text,
  participant_count bigint,
  accepted_count bigint,
  pending_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.family_members fm
    where fm.family_id = p_family_id and fm.user_id = auth.uid()
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select
    c.id,
    c.family_id,
    c.mode,
    c.focus,
    c.status,
    c.start_date,
    c.end_date,
    c.created_at,
    c.completed_at,
    c.created_by,
    c.winner_user_id,
    c.tie_break_used,
    (select bp.invite_status from public.big_competitive_participants bp
       where bp.challenge_id = c.id and bp.user_id = auth.uid() limit 1) as my_invite_status,
    (select count(*) from public.big_competitive_participants bp where bp.challenge_id = c.id) as participant_count,
    (select count(*) from public.big_competitive_participants bp where bp.challenge_id = c.id and bp.invite_status = 'accepted') as accepted_count,
    (select count(*) from public.big_competitive_participants bp where bp.challenge_id = c.id and bp.invite_status = 'pending') as pending_count
  from public.big_competitive_challenges c
  where c.family_id = p_family_id
    and exists (
      select 1 from public.big_competitive_participants p
      where p.challenge_id = c.id and p.user_id = auth.uid()
    )
  order by c.created_at desc;
end;
$$;

comment on function public.get_competitive_challenges_for_family is
  'Returns competitive challenges visible to the caller in the given family (where the caller is a participant).';

revoke all on function public.get_competitive_challenges_for_family(uuid) from public;
grant execute on function public.get_competitive_challenges_for_family(uuid) to authenticated;

-- ============================================================================
-- 4) get_competitive_challenge_detail
--    One row per participant for a single challenge, with display + score info.
-- ============================================================================
create or replace function public.get_competitive_challenge_detail(p_challenge_id uuid)
returns table (
  challenge_id uuid,
  family_id uuid,
  mode text,
  focus text,
  status text,
  start_date date,
  end_date date,
  created_at timestamptz,
  activated_at timestamptz,
  completed_at timestamptz,
  created_by uuid,
  winner_user_id uuid,
  tie_break_used boolean,
  participant_user_id uuid,
  participant_first_name text,
  participant_invite_status text,
  participant_accepted_at timestamptz,
  participant_aggregate numeric,
  participant_best_day numeric,
  participant_daily jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id uuid;
begin
  select c.family_id into v_family_id
  from public.big_competitive_challenges c
  where c.id = p_challenge_id;

  if v_family_id is null then
    raise exception 'Challenge not found';
  end if;

  if not exists (
    select 1 from public.family_members fm
    where fm.family_id = v_family_id and fm.user_id = auth.uid()
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  with c as (
    select * from public.big_competitive_challenges where id = p_challenge_id
  ),
  per_participant as (
    select
      p.user_id,
      coalesce(up.first_name, fm.first_name, 'Member')::text as first_name,
      p.invite_status,
      p.accepted_at,
      -- aggregate: pillars use AVG of pillar_score (ignoring nulls); steps use SUM (treating null as 0).
      case
        when (select focus from c) = 'steps' then coalesce(sum(s.steps), 0)::numeric
        else avg(s.pillar_score)
      end as aggregate_value,
      -- best_day: pillars use max(pillar_score); steps use max(steps).
      case
        when (select focus from c) = 'steps' then coalesce(max(s.steps), 0)::numeric
        else max(s.pillar_score)
      end as best_day_value,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'local_date', s.local_date,
            'pillar_score', s.pillar_score,
            'steps', s.steps
          )
          order by s.local_date
        ) filter (where s.local_date is not null),
        '[]'::jsonb
      ) as daily
    from public.big_competitive_participants p
    left join public.user_profiles up on up.user_id = p.user_id
    left join public.family_members fm
      on fm.user_id = p.user_id
     and fm.family_id = (select family_id from c)
    left join public.big_competitive_daily_snapshots s
      on s.challenge_id = p.challenge_id and s.user_id = p.user_id
    where p.challenge_id = p_challenge_id
    group by p.user_id, up.first_name, fm.first_name, p.invite_status, p.accepted_at
  )
  select
    c.id, c.family_id, c.mode, c.focus, c.status, c.start_date, c.end_date,
    c.created_at, c.activated_at, c.completed_at, c.created_by, c.winner_user_id, c.tie_break_used,
    pp.user_id, pp.first_name, pp.invite_status, pp.accepted_at,
    pp.aggregate_value, pp.best_day_value, pp.daily
  from c, per_participant pp;
end;
$$;

comment on function public.get_competitive_challenge_detail is
  'Detail view for one competitive challenge; row per participant with aggregate + best-day + daily JSON.';

revoke all on function public.get_competitive_challenge_detail(uuid) from public;
grant execute on function public.get_competitive_challenge_detail(uuid) to authenticated;
