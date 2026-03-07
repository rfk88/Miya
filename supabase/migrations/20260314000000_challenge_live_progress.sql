-- =====================================================
-- Challenge progress: compute days_succeeded and
-- days_evaluated live from vitality_scores instead of
-- relying on stored counters updated by a cron job.
--
-- No schema changes; only the two read RPCs are updated.
-- The days_succeeded / days_evaluated columns on the
-- challenges table are kept but are no longer the source
-- of truth for the UI.
-- =====================================================

-- 1) get_active_challenge_for_member
--    Returns the active challenge for the authenticated user,
--    with days_succeeded and days_evaluated computed directly
--    from vitality_scores for the challenge date range.

drop function if exists public.get_active_challenge_for_member();

create or replace function public.get_active_challenge_for_member()
returns table (
  id                  uuid,
  family_id           uuid,
  member_user_id      uuid,
  admin_user_id       uuid,
  pillar              text,
  status              text,
  start_date          date,
  end_date            date,
  days_succeeded      int,
  days_evaluated      int,
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
    prog.days_succeeded,
    prog.days_evaluated,
    c.required_success_days
  from public.challenges c
  cross join lateral (
    select
      count(*) filter (where score >= 50)::int  as days_succeeded,
      count(*) filter (where score is not null)::int as days_evaluated
    from (
      select
        case c.pillar
          when 'sleep'    then vs.vitality_sleep_pillar_score
          when 'movement' then vs.vitality_movement_pillar_score
          when 'stress'   then vs.vitality_stress_pillar_score
        end as score
      from public.vitality_scores vs
      where vs.user_id = c.member_user_id
        and vs.date between c.start_date and c.end_date
    ) scored
  ) prog
  where c.member_user_id = auth.uid()
    and c.status = 'active'
  order by c.start_date desc
  limit 1;
$$;

comment on function public.get_active_challenge_for_member is
  'Active challenge for the authenticated member with days_succeeded / days_evaluated computed live from vitality_scores.';


-- 2) get_family_challenges
--    Same live-computation approach for the Family Challenges tab,
--    which shows challenges across all family members.

drop function if exists public.get_family_challenges(uuid);

create or replace function public.get_family_challenges(p_family_id uuid)
returns table (
  id                  uuid,
  pillar              text,
  status              text,
  member_user_id      uuid,
  member_name         text,
  days_succeeded      int,
  days_evaluated      int,
  end_date            date,
  source_alert_metric text,
  source_alert_days   int,
  my_role             text,
  challenger_count    bigint
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
    c.pillar,
    c.status,
    c.member_user_id,
    coalesce(up.first_name, 'Member')::text as member_name,
    prog.days_succeeded,
    prog.days_evaluated,
    c.end_date,
    pas.metric_type  as source_alert_metric,
    pas.current_level as source_alert_days,
    case
      when exists (
        select 1 from public.challenge_challengers cc
        where cc.challenge_id = c.id and cc.user_id = auth.uid()
      ) then 'challenger'::text
      when c.member_user_id = auth.uid() then 'challengee'::text
      else null
    end as my_role,
    (
      select count(*) from public.challenge_challengers cc
      where cc.challenge_id = c.id
    ) as challenger_count
  from public.challenges c
  left join public.user_profiles up on up.user_id = c.member_user_id
  left join public.pattern_alert_state pas on pas.id = c.source_alert_state_id
  -- live progress per challenge
  cross join lateral (
    select
      count(*) filter (where score >= 50)::int  as days_succeeded,
      count(*) filter (where score is not null)::int as days_evaluated
    from (
      select
        case c.pillar
          when 'sleep'    then vs.vitality_sleep_pillar_score
          when 'movement' then vs.vitality_movement_pillar_score
          when 'stress'   then vs.vitality_stress_pillar_score
        end as score
      from public.vitality_scores vs
      where vs.user_id = c.member_user_id
        and c.start_date is not null
        and vs.date between c.start_date and c.end_date
    ) scored
  ) prog
  where c.family_id = p_family_id
    and (
      exists (
        select 1 from public.challenge_challengers cc
        where cc.challenge_id = c.id and cc.user_id = auth.uid()
      )
      or c.member_user_id = auth.uid()
    )
  order by c.created_at desc;
end;
$$;

comment on function public.get_family_challenges is
  'Challenges where the caller is a challenger or the challengee; days_succeeded / days_evaluated computed live from vitality_scores.';
