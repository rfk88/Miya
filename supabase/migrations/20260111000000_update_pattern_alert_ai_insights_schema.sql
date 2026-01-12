-- =====================================================
-- Update pattern_alert_ai_insights schema for clinical prompt structure
-- Adds new fields while keeping old ones for backwards compatibility
-- =====================================================

-- Add new columns
alter table public.pattern_alert_ai_insights 
  add column if not exists clinical_interpretation text,
  add column if not exists data_connections text,
  add column if not exists possible_causes jsonb,
  add column if not exists action_steps jsonb;

-- Update prompt version tracking comment
comment on column public.pattern_alert_ai_insights.prompt_version is 
  'v2 = original format (summary, contributors, actions), v3 = clinical format (clinical_interpretation, data_connections, possible_causes, action_steps)';
