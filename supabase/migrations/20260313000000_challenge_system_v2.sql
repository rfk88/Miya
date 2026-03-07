-- =====================================================
-- Family Challenges v2: challenge_challengers, snooze,
-- my_challenge_status on alerts, get_family_challenges, join_challenge.
-- =====================================================

-- a) challenge_challengers table
create table if not exists public.challenge_challengers (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

comment on table public.challenge_challengers is
  'Users who have sent or joined a challenge; one row per (challenge, user).';

create index if not exists idx_challenge_challengers_user
  on public.challenge_challengers (user_id);

alter table public.challenge_challengers enable row level security;

drop policy if exists "challenge_challengers_read_family" on public.challenge_challengers;
create policy "challenge_challengers_read_family"
  on public.challenge_challengers for select to authenticated
  using (
    exists (
      select 1 from public.challenges c
      join public.family_members fm on fm.family_id = c.family_id and fm.user_id = auth.uid()
      where c.id = challenge_challengers.challenge_id
    )
  );

drop policy if exists "challenge_challengers_block_direct_write" on public.challenge_challengers;
create policy "challenge_challengers_block_direct_write"
  on public.challenge_challengers for all to authenticated
  using (false) with check (false);

-- b) Add snoozed status and snoozed_until to challenges
alter table public.challenges
  add column if not exists snoozed_until date;

alter table public.challenges
  drop constraint if exists challenges_status_check;

alter table public.challenges
  add constraint challenges_status_check
  check (status in ('pending_invite', 'active', 'snoozed', 'completed_success', 'completed_failed'));

comment on column public.challenges.snoozed_until is
  'When a challenge was snoozed (maybe later), resurface after this date.';

-- c) Update create_challenge: insert into challenge_challengers (caller = first challenger)
-- Use param names without leading underscore for PostgREST compatibility.
drop function if exists public.create_challenge(uuid, text, uuid);

create or replace function public.create_challenge(
  member_user_id uuid,
  pillar text,
  source_alert_state_id uuid default null
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

  select fm.family_id into caller_family_id
  from public.family_members fm
  where fm.user_id = caller_user_id limit 1;
  if caller_family_id is null then
    raise exception 'Caller is not a member of any family';
  end if;

  select fm.family_id into member_family_id
  from public.family_members fm
  where fm.user_id = create_challenge.member_user_id
    and fm.family_id = caller_family_id limit 1;
  if member_family_id is null then
    raise exception 'Member not in same family';
  end if;

  select id into existing_id
  from public.challenges c
  where c.member_user_id = create_challenge.member_user_id
    and c.status in ('pending_invite', 'active', 'snoozed')
  limit 1;
  if existing_id is not null then
    return jsonb_build_object(
      'success', false,
      'error', 'active_challenge_exists',
      'challenge_id', existing_id
    );
  end if;

  insert into public.challenges (
    family_id, member_user_id, admin_user_id, pillar, status, source_alert_state_id
  ) values (
    caller_family_id, create_challenge.member_user_id, caller_user_id,
    create_challenge.pillar, 'pending_invite', create_challenge.source_alert_state_id
  )
  returning id into new_id;

  insert into public.challenge_challengers (challenge_id, user_id)
  values (new_id, caller_user_id);

  insert into public.notification_queue (
    recipient_user_id, member_user_id, alert_state_id, channel, payload, status
  ) values (
    create_challenge.member_user_id, create_challenge.member_user_id,
    create_challenge.source_alert_state_id, 'push',
    jsonb_build_object(
      'kind', 'challenge_invite',
      'challenge_id', new_id,
      'pillar', create_challenge.pillar,
      'admin_user_id', caller_user_id
    ),
    'pending'
  );

  return jsonb_build_object('success', true, 'challenge_id', new_id);
end;
$$;

comment on function public.create_challenge is
  'Create a pending_invite challenge; caller is added to challenge_challengers.';

-- d) join_challenge RPC
create or replace function public.join_challenge(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id uuid;
  v_caller_id uuid;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select c.family_id into v_family_id
  from public.challenges c
  where c.id = p_challenge_id;
  if v_family_id is null then
    raise exception 'Challenge not found';
  end if;

  if not exists (
    select 1 from public.family_members fm
    where fm.family_id = v_family_id and fm.user_id = v_caller_id
  ) then
    raise exception 'Not in same family';
  end if;

  insert into public.challenge_challengers (challenge_id, user_id)
  values (p_challenge_id, v_caller_id)
  on conflict (challenge_id, user_id) do nothing;

  return jsonb_build_object('success', true);
end;
$$;

comment on function public.join_challenge is
  'Add the current user as a challenger (join an existing challenge).';

-- e) Update respond_to_challenge: add snooze action
drop function if exists public.respond_to_challenge(uuid, text);

create or replace function public.respond_to_challenge(
  _challenge_id uuid,
  _action text  -- 'accept', 'decline', or 'snooze'
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

  select * into challenge_record
  from public.challenges c where c.id = _challenge_id;
  if not found then
    raise exception 'Challenge not found';
  end if;

  if challenge_record.member_user_id <> caller_user_id then
    raise exception 'Only the challenged member can respond';
  end if;

  if challenge_record.status not in ('pending_invite', 'snoozed') then
    return jsonb_build_object('success', false, 'error', 'challenge_not_pending');
  end if;

  if _action = 'accept' then
    today := current_date;
    update public.challenges
    set status = 'active', start_date = today, end_date = today + 6,
        days_succeeded = 0, days_evaluated = 0, last_evaluated_at = null,
        snoozed_until = null, updated_at = now()
    where id = _challenge_id;
    new_status := 'active';
  elsif _action = 'decline' then
    update public.challenges
    set status = 'completed_failed', snoozed_until = null, updated_at = now()
    where id = _challenge_id;
    new_status := 'completed_failed';
  elsif _action = 'snooze' then
    update public.challenges
    set status = 'snoozed', snoozed_until = current_date + 2, updated_at = now()
    where id = _challenge_id;
    new_status := 'snoozed';
  else
    raise exception 'Invalid action. Must be accept, decline, or snooze';
  end if;

  return jsonb_build_object('success', true, 'status', new_status);
end;
$$;

comment on function public.respond_to_challenge is
  'Member response: accept (start 7-day window), decline, or snooze (maybe later).';

-- f) Update get_family_pattern_alerts: add my_challenge_status
drop function if exists public.get_family_pattern_alerts(uuid);

create or replace function public.get_family_pattern_alerts(family_id uuid)
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
  recent_value numeric,
  care_state text,
  acted_by_user_id uuid,
  acted_at timestamptz,
  follow_up_due_date date,
  outcome_message text,
  cycle_count int,
  last_intervention_type text,
  my_challenge_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
begin
  select exists (
    select 1 from public.family_members fm
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id = auth.uid()
  ) into caller_is_member;
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
    asn.snoozed_until as snooze_until,
    asn.snooze_days,
    pas.dismissed_at,
    pas.deviation_percent,
    pas.baseline_value,
    pas.recent_value,
    acs.care_state,
    acs.acted_by_user_id,
    acs.acted_at,
    acs.follow_up_due_date,
    acs.outcome_message,
    coalesce(acs.cycle_count, 0) as cycle_count,
    acs.last_intervention_type,
    (
      select c.status
      from public.challenges c
      join public.challenge_challengers cc on cc.challenge_id = c.id
      where c.source_alert_state_id = pas.id and cc.user_id = auth.uid()
      limit 1
    ) as my_challenge_status
  from public.pattern_alert_state pas
  left join public.alert_snoozes asn
    on asn.alert_id = pas.id and asn.user_id = auth.uid()
  left join public.alert_care_state acs on acs.alert_id = pas.id
  where pas.user_id in (
    select fm.user_id from public.family_members fm
    where fm.family_id = get_family_pattern_alerts.family_id
      and fm.user_id is not null
      and fm.user_id != auth.uid()
  )
    and pas.episode_status = 'active'
    and pas.dismissed_at is null
    and (asn.snoozed_until is null or asn.snoozed_until < current_date)
    and (acs.care_state is null or acs.care_state != 'archived')
  order by pas.current_level desc, pas.active_since desc;
end;
$$;

comment on function public.get_family_pattern_alerts is
  'Family pattern alerts with per-user my_challenge_status (from challenge_challengers).';

-- g) get_family_challenges RPC
create or replace function public.get_family_challenges(p_family_id uuid)
returns table (
  id uuid,
  pillar text,
  status text,
  member_user_id uuid,
  member_name text,
  days_succeeded int,
  days_evaluated int,
  end_date date,
  source_alert_metric text,
  source_alert_days int,
  my_role text,
  challenger_count bigint
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
    c.days_succeeded,
    c.days_evaluated,
    c.end_date,
    pas.metric_type as source_alert_metric,
    pas.current_level as source_alert_days,
    case
      when exists (select 1 from public.challenge_challengers cc where cc.challenge_id = c.id and cc.user_id = auth.uid())
        then 'challenger'::text
      when c.member_user_id = auth.uid() then 'challengee'::text
      else null
    end as my_role,
    (select count(*) from public.challenge_challengers cc where cc.challenge_id = c.id) as challenger_count
  from public.challenges c
  left join public.user_profiles up on up.user_id = c.member_user_id
  left join public.pattern_alert_state pas on pas.id = c.source_alert_state_id
  where c.family_id = p_family_id
    and (
      exists (select 1 from public.challenge_challengers cc where cc.challenge_id = c.id and cc.user_id = auth.uid())
      or c.member_user_id = auth.uid()
    )
  order by c.created_at desc;
end;
$$;

comment on function public.get_family_challenges is
  'Challenges where the caller is a challenger or the challengee; for Family Challenges tab.';

-- h) Cron: run challenges_daily_evaluate daily at 6:00 UTC.
-- In Supabase Dashboard: Edge Functions > challenges_daily_evaluate > add Cron schedule "0 6 * * *".
-- If using pg_cron + pg_net, uncomment and set your project URL and secret:
/*
select cron.schedule(
  'challenges-daily-evaluate',
  '0 6 * * *',
  $$ select net.http_post(
    url := 'https://YOUR_REF.supabase.co/functions/v1/challenges_daily_evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-miya-admin-secret', current_setting('app.miya_admin_secret', true)),
    body := '{}'
  ) as request_id $$
);
*/
