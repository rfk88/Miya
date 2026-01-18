-- Force refresh the RPC (drop and recreate)
DROP FUNCTION IF EXISTS public.get_family_vitality(uuid);

-- Then immediately run HOTFIX_change_freshness_to_7_days.sql
-- Or copy/paste its contents here
