-- Tie-break / rematch RPCs for Phase 4 result screen.
--
-- Tie-break is opt-in: the daily evaluator leaves `winner_user_id` NULL when the
-- aggregate is tied. The user (any participant or family member) can call
-- `resolve_competitive_challenge_tie_break` to fall back to the highest single-day
-- score. If still tied, the call returns success: false / error: 'still_tied'.

create or replace function public.resolve_competitive_challenge_tie_break(
  p_challenge_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_user_id uuid;
  v_challenge public.big_competitive_challenges%rowtype;
  v_winner uuid;
  v_best_value numeric;
  v_winner_count int;
  v_focus text;
  v_event_points int;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  select * into v_challenge
  from public.big_competitive_challenges
  where id = p_challenge_id
  for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'challenge_not_found');
  end if;

  -- Authorisation: caller must be in the challenge's family.
  if not exists (
    select 1 from public.family_members fm
    where fm.family_id = v_challenge.family_id and fm.user_id = caller_user_id
  ) then
    return jsonb_build_object('success', false, 'error', 'not_authorized');
  end if;

  if v_challenge.status <> 'completed' then
    return jsonb_build_object('success', false, 'error', 'challenge_not_completed');
  end if;

  if v_challenge.winner_user_id is not null then
    return jsonb_build_object('success', true, 'winner_user_id', v_challenge.winner_user_id, 'changed', false);
  end if;

  v_focus := v_challenge.focus;

  -- Compute the per-participant "best day" value, then find the singular top.
  with best_per_user as (
    select
      s.user_id,
      case when v_focus = 'steps' then max(coalesce(s.steps, 0))::numeric
           else max(s.pillar_score) end as best_value
    from public.big_competitive_daily_snapshots s
    join public.big_competitive_participants p
      on p.challenge_id = s.challenge_id and p.user_id = s.user_id
    where s.challenge_id = p_challenge_id
      and p.invite_status = 'accepted'
    group by s.user_id
  ),
  ranked as (
    select user_id, best_value,
           rank() over (order by best_value desc nulls last) as rk
    from best_per_user
  )
  select
    (select user_id from ranked where rk = 1 limit 1),
    (select best_value from ranked where rk = 1 limit 1),
    (select count(*) from ranked where rk = 1)
  into v_winner, v_best_value, v_winner_count;

  if v_winner_count is null or v_winner_count < 1 or v_best_value is null then
    return jsonb_build_object('success', false, 'error', 'no_data_for_tie_break');
  end if;

  if v_winner_count > 1 then
    return jsonb_build_object('success', false, 'error', 'still_tied');
  end if;

  update public.big_competitive_challenges
  set winner_user_id = v_winner,
      tie_break_used = true
  where id = p_challenge_id;

  -- Award Champions points (mirrors evaluator's logic for non-draw outcomes).
  if v_challenge.mode = 'head_to_head' then
    insert into public.big_challenge_champion_point_events (
      family_id, user_id, points, reason, competitive_challenge_id, placement
    ) values (
      v_challenge.family_id, v_winner, 50, 'duel_winner_tie_break', p_challenge_id, 1
    );
  else
    -- For brawls, give the resolved winner first-place points (everyone else stays unawarded
    -- because the evaluator already handled <=3 placement when there was a clear winner;
    -- in a top-tie brawl the lower placements were never logged).
    insert into public.big_challenge_champion_point_events (
      family_id, user_id, points, reason, competitive_challenge_id, placement
    ) values (
      v_challenge.family_id, v_winner, 75, 'brawl_first_place_tie_break', p_challenge_id, 1
    );
  end if;

  -- Notify participants of the resolved outcome.
  insert into public.notification_queue (
    recipient_user_id, member_user_id, alert_state_id, channel, payload, status
  )
  select
    p.user_id,
    v_winner,
    null,
    'push',
    jsonb_build_object(
      'kind', 'competitive_challenge_result',
      'challenge_id', p_challenge_id,
      'focus', v_focus,
      'outcome', 'decided',
      'you_won', p.user_id = v_winner,
      'winner_user_id', v_winner,
      'tie_break_used', true
    ),
    'pending'
  from public.big_competitive_participants p
  where p.challenge_id = p_challenge_id
    and p.invite_status = 'accepted';

  return jsonb_build_object(
    'success', true,
    'winner_user_id', v_winner,
    'tie_break_used', true,
    'changed', true
  );
end;
$$;

comment on function public.resolve_competitive_challenge_tie_break is
  'Resolve a completed-but-drawn competitive challenge via highest-single-day tie-break.';

revoke all on function public.resolve_competitive_challenge_tie_break(uuid) from public;
grant execute on function public.resolve_competitive_challenge_tie_break(uuid) to authenticated;
