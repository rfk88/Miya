-- =====================================================
-- Add severity to pattern_alert_state
-- Derived from current_level:
--   3-6   -> watch
--   7-13  -> attention
--   14+   -> critical
-- =====================================================

alter table if exists public.pattern_alert_state
  add column if not exists severity text;

do $$
begin
  -- Add check constraint (idempotent)
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pattern_alert_state_severity_check'
  ) then
    alter table public.pattern_alert_state
      add constraint pattern_alert_state_severity_check
      check (severity in ('watch', 'attention', 'critical'));
  end if;
end $$;

-- Backfill existing rows
update public.pattern_alert_state
set severity = case
  when coalesce(current_level, 3) <= 6 then 'watch'
  when coalesce(current_level, 3) <= 13 then 'attention'
  else 'critical'
end
where severity is null;

