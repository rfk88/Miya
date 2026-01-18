-- Check vitality scores for your two family members
SELECT 
    user_id,
    vitality_score_current,
    vitality_score_updated_at,
    EXTRACT(EPOCH FROM (NOW() - vitality_score_updated_at)) / 3600 as hours_old,
    CASE 
        WHEN vitality_score_updated_at >= NOW() - INTERVAL '7 days' THEN 'YES'
        ELSE 'NO'
    END as within_7_days
FROM user_profiles
WHERE user_id IN (
    'ab99ca15-2490-4692-90cf-26d03576068e',
    '46ded9db-5488-49ac-92b2-ffd2937e5e16'
);

-- Manual average calculation
SELECT 
    ROUND(AVG(vitality_score_current)) as should_be_family_score,
    COUNT(*) as members_counted
FROM user_profiles
WHERE user_id IN (
    'ab99ca15-2490-4692-90cf-26d03576068e',
    '46ded9db-5488-49ac-92b2-ffd2937e5e16'
)
AND vitality_score_current IS NOT NULL
AND vitality_score_updated_at >= NOW() - INTERVAL '7 days';
