-- =====================================================
-- Add age_group × risk_band optimal targets (20 variants)
-- Add derived vitality progress score (0–100 capped)
-- Does NOT change vitality scoring; only adds a derived normalization layer.
-- =====================================================

-- 1) Matrix table: age_group × risk_band -> optimal_target (1..100)
create table if not exists public.vitality_optimal_targets (
  age_group text not null check (age_group in ('young','middle','senior','elderly')),
  risk_band text not null check (risk_band in ('low','moderate','high','very_high','critical')),
  optimal_target integer not null check (optimal_target between 1 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (age_group, risk_band)
);

comment on table public.vitality_optimal_targets is
  'Age-group × risk-band recommended optimal targets used to normalize vitality into a capped progress score. Does not affect vitality scoring.';

-- Seed the 20 rows.
-- NOTE: Initial seeding uses the existing risk-only targets duplicated across age groups.
--       You can later tune per age_group without schema/code changes.
insert into public.vitality_optimal_targets (age_group, risk_band, optimal_target)
values
  -- young
  ('young',   'low',       90),
  ('young',   'moderate',  85),
  ('young',   'high',      80),
  ('young',   'very_high', 75),
  ('young',   'critical',  70),
  -- middle
  ('middle',  'low',       90),
  ('middle',  'moderate',  85),
  ('middle',  'high',      80),
  ('middle',  'very_high', 75),
  ('middle',  'critical',  70),
  -- senior
  ('senior',  'low',       90),
  ('senior',  'moderate',  85),
  ('senior',  'high',      80),
  ('senior',  'very_high', 75),
  ('senior',  'critical',  70),
  -- elderly
  ('elderly', 'low',       90),
  ('elderly', 'moderate',  85),
  ('elderly', 'high',      80),
  ('elderly', 'very_high', 75),
  ('elderly', 'critical',  70)
on conflict (age_group, risk_band) do update
set optimal_target = excluded.optimal_target,
    updated_at = now();

-- 2) Helper: derive age_group from DOB (matches Swift AgeGroup buckets)
create or replace function public.age_group_from_dob(dob date)
returns text
language sql
stable
as $$
  select case
    when dob is null then null
    when date_part('year', age(dob)) < 40 then 'young'
    when date_part('year', age(dob)) < 60 then 'middle'
    when date_part('year', age(dob)) < 75 then 'senior'
    else 'elderly'
  end;
$$;

comment on function public.age_group_from_dob(date) is
  'Maps DOB to age_group buckets: young(<40), middle(40-59), senior(60-74), elderly(75+).';

-- 3) Derived score: progress-to-optimal, capped at 100
create or replace function public.vitality_progress_score(
  vitality_score integer,
  dob date,
  risk_band text
)
returns integer
language plpgsql
stable
as $$
declare
  ag text;
  target integer;
  raw_progress numeric;
begin
  if vitality_score is null or dob is null or risk_band is null then
    return null;
  end if;

  ag := public.age_group_from_dob(dob);
  if ag is null then
    return null;
  end if;

  select vot.optimal_target
    into target
  from public.vitality_optimal_targets vot
  where vot.age_group = ag
    and vot.risk_band = vitality_progress_score.risk_band;

  if target is null or target <= 0 then
    return null;
  end if;

  raw_progress := round((vitality_score::numeric / target::numeric) * 100);
  return least(100, raw_progress)::int;
end;
$$;

comment on function public.vitality_progress_score(integer, date, text) is
  'Returns capped progress score (0-100) = min(100, round(vitality_score/optimal_target*100)), where optimal_target comes from age_group×risk_band matrix.';

-- 4) Persist latest progress score alongside existing current vitality snapshot
alter table public.user_profiles
  add column if not exists vitality_progress_score_current integer
  check (vitality_progress_score_current is null or (vitality_progress_score_current between 0 and 100));

alter table public.user_profiles
  add column if not exists vitality_progress_score_updated_at timestamptz;

-- 5) Keep progress score updated when inputs change
create or replace function public.trg_set_vitality_progress_score_current()
returns trigger
language plpgsql
as $$
begin
  -- Only compute when we have enough information; otherwise clear it.
  if new.vitality_score_current is null or new.date_of_birth is null or new.risk_band is null then
    new.vitality_progress_score_current := null;
    new.vitality_progress_score_updated_at := null;
    return new;
  end if;

  new.vitality_progress_score_current :=
    public.vitality_progress_score(new.vitality_score_current, new.date_of_birth, new.risk_band);

  new.vitality_progress_score_updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_vitality_progress_score_current on public.user_profiles;
create trigger set_vitality_progress_score_current
before insert or update of vitality_score_current, date_of_birth, risk_band
on public.user_profiles
for each row
execute function public.trg_set_vitality_progress_score_current();

-- 6) Backfill existing profiles
update public.user_profiles
set
  vitality_progress_score_current = public.vitality_progress_score(vitality_score_current, date_of_birth, risk_band),
  vitality_progress_score_updated_at = now()
where vitality_score_current is not null
  and date_of_birth is not null
  and risk_band is not null;




