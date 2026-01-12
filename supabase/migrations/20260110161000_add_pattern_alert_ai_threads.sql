-- =====================================================
-- AI contextual chat threads/messages for Ask Miya
-- NOTE: If your migration pipeline is blocked, you can paste/run this file
-- in Supabase SQL Editor.
-- =====================================================

create table if not exists public.pattern_alert_ai_threads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  alert_state_id uuid not null references public.pattern_alert_state(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active'
);

create unique index if not exists idx_pattern_alert_ai_threads_unique
  on public.pattern_alert_ai_threads(alert_state_id, created_by);

create table if not exists public.pattern_alert_ai_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  thread_id uuid not null references public.pattern_alert_ai_threads(id) on delete cascade,
  role text not null check (role in ('user','assistant','system')),
  content text not null,
  tokens int
);

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

drop trigger if exists update_pattern_alert_ai_threads_updated_at on public.pattern_alert_ai_threads;
create trigger update_pattern_alert_ai_threads_updated_at
  before update on public.pattern_alert_ai_threads
  for each row
  execute function public.update_updated_at_column();

-- RLS
alter table public.pattern_alert_ai_threads enable row level security;
alter table public.pattern_alert_ai_messages enable row level security;

-- Threads: own only
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'pattern_alert_ai_threads' and policyname = 'pattern_alert_ai_threads_own'
  ) then
    create policy pattern_alert_ai_threads_own
    on public.pattern_alert_ai_threads
    for all
    to authenticated
    using (created_by = auth.uid())
    with check (created_by = auth.uid());
  end if;
end $$;

-- Messages: select/insert only via own thread
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'pattern_alert_ai_messages' and policyname = 'pattern_alert_ai_messages_select_via_thread'
  ) then
    create policy pattern_alert_ai_messages_select_via_thread
    on public.pattern_alert_ai_messages
    for select
    to authenticated
    using (
      exists (
        select 1 from public.pattern_alert_ai_threads t
        where t.id = pattern_alert_ai_messages.thread_id
          and t.created_by = auth.uid()
      )
    );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'pattern_alert_ai_messages' and policyname = 'pattern_alert_ai_messages_insert_via_thread'
  ) then
    create policy pattern_alert_ai_messages_insert_via_thread
    on public.pattern_alert_ai_messages
    for insert
    to authenticated
    with check (
      exists (
        select 1 from public.pattern_alert_ai_threads t
        where t.id = pattern_alert_ai_messages.thread_id
          and t.created_by = auth.uid()
      )
    );
  end if;
end $$;

