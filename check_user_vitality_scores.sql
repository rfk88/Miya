-- Check if users actually have vitality scores in the database
-- Run this to see what's really happening

-- 1. Check user_profiles vitality scores
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT 
    fm.first_name,
    up.vitality_score_current,
    up.vitality_score_source,
    up.vitality_score_updated_at,
    up.date_of_birth,
    up.onboarding_complete,
    CASE 
        WHEN up.vitality_score_current IS NULL THEN '❌ NO SCORE'
        WHEN up.vitality_score_updated_at >= NOW() - INTERVAL '7 days' THEN '✅ FRESH'
        ELSE '⚠️ STALE'
    END as status
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = (SELECT family_id FROM your_family)
ORDER BY up.vitality_score_updated_at DESC NULLS LAST;

-- 2. Check vitality_scores table (historical daily scores)
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT 
    fm.first_name,
    COUNT(*) as daily_scores_count,
    MIN(vs.score_date) as earliest_date,
    MAX(vs.score_date) as latest_date,
    MAX(vs.total_score) as latest_total_score
FROM vitality_scores vs
JOIN family_members fm ON fm.user_id = vs.user_id
WHERE fm.family_id = (SELECT family_id FROM your_family)
GROUP BY fm.first_name
ORDER BY latest_date DESC;

-- 3. Check wearable_daily_metrics (raw health data)
WITH your_family AS (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid()
    LIMIT 1
)
SELECT 
    fm.first_name,
    COUNT(*) as metrics_count,
    MIN(wdm.metric_date) as earliest_date,
    MAX(wdm.metric_date) as latest_date,
    MAX(wdm.steps) as latest_steps
FROM wearable_daily_metrics wdm
JOIN family_members fm ON fm.user_id = wdm.user_id
WHERE fm.family_id = (SELECT family_id FROM your_family)
GROUP BY fm.first_name
ORDER BY latest_date DESC;
