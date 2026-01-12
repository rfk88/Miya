-- =====================================================
-- AI cache for pattern alert insights (GPT output)
-- NOTE: If your migration pipeline is blocked, you can paste/run this file
-- in Supabase SQL Editor.
-- =====================================================

create table if not exists public.pattern_alert_ai_insights (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  alert_state_id uuid not null references public.pattern_alert_state(id) on delete cascade,
  evaluated_end_date date not null,
  prompt_version text not null,

  model text not null,
  headline text not null,
  summary text not null,
  contributors jsonb,
  actions jsonb,
  message_suggestions jsonb,
  confidence text,
  confidence_reason text,

  evidence jsonb not null
);

create unique index if not exists idx_pattern_alert_ai_insights_unique
  on public.pattern_alert_ai_insights(alert_state_id, evaluated_end_date, prompt_version);

-- updated_at trigger reuse
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'update_updated_at_column') then
    create or replace function public.update_updated_at_column()
    returns trigger as $fn$
    begin
      new.updated_at = now();
      return new;
    end;
    $fn$ language plpgsql;
  end if;
end $$;

drop trigger if exists update_pattern_alert_ai_insights_updated_at on public.pattern_alert_ai_insights;
create trigger update_pattern_alert_ai_insights_updated_at
  before update on public.pattern_alert_ai_insights
  for each row
  execute function public.update_updated_at_column();

-- RLS
alter table public.pattern_alert_ai_insights enable row level security;

-- Allow family members to read AI insights for alerts in their family.
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'pattern_alert_ai_insights' and policyname = 'pattern_alert_ai_insights_read_family'
  ) then
    create policy pattern_alert_ai_insights_read_family
    on public.pattern_alert_ai_insights
    for select
    to authenticated
    using (
      exists (
        select 1
        from public.pattern_alert_state pas
        join public.family_members me
          on me.user_id = auth.uid()
        join public.family_members them
          on them.family_id = me.family_id
         and them.user_id = pas.user_id
        where pas.id = pattern_alert_ai_insights.alert_state_id
      )
    );
  end if;
end $$;

