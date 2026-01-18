-- Diagnostic Query: Why isn't family vitality loading?
-- Run this in Supabase SQL Editor

-- 1. Check your family_id
SELECT 
    fm.family_id,
    fm.user_id,
    fm.first_name
FROM family_members fm
WHERE fm.user_id = auth.uid();

-- 2. Check all family members and their vitality scores
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT 
    fm.first_name,
    up.vitality_score_current,
    up.vitality_score_updated_at,
    CASE 
        WHEN up.vitality_score_updated_at IS NULL THEN 'No score yet'
        WHEN up.vitality_score_updated_at >= NOW() - INTERVAL '7 days' THEN 'FRESH (within 7 days)'
        ELSE 'STALE (older than 7 days) - WILL BE EXCLUDED'
    END as freshness_status,
    EXTRACT(EPOCH FROM (NOW() - up.vitality_score_updated_at)) / 3600 as hours_old
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = (SELECT family_id FROM your_family)
ORDER BY up.vitality_score_updated_at DESC NULLS LAST;

-- 3. Test the get_family_vitality RPC directly
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT * FROM get_family_vitality((SELECT family_id FROM your_family));

-- 4. Check if vitality_progress_score_current column exists
SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'user_profiles'
      AND c.column_name = 'vitality_progress_score_current'
) as has_progress_column;

-- 5. Check recent vitality_scores table entries
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT 
    fm.first_name,
    vs.score_date,
    vs.total_score,
    vs.sleep_score,
    vs.movement_score,
    vs.stress_score
FROM vitality_scores vs
JOIN family_members fm ON fm.user_id = vs.user_id
WHERE fm.family_id = (SELECT family_id FROM your_family)
  AND vs.score_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY vs.score_date DESC, fm.first_name;
