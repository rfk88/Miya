-- Clear AI insight cache to force regeneration with new prompt format
-- Run this in Supabase SQL Editor

-- Option 1: Clear cache for this specific alert
DELETE FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '6a4b42d3-2be9-4bcf-ab70-6cc2a31d37d8';

-- Option 2: Clear ALL cached insights (uncomment to use)
-- DELETE FROM public.pattern_alert_ai_insights;

-- Option 3: Clear only old prompt versions (uncomment to use)
-- DELETE FROM public.pattern_alert_ai_insights
-- WHERE prompt_version IN ('v1', 'v2', 'v3');
