-- Query 4: Manual calculation (what it SHOULD return)
-- REPLACE 'YOUR_FAMILY_ID_HERE' with the family_id from Query 1

SELECT 
    ROUND(AVG(up.vitality_score_current)) as family_score,
    COUNT(*) FILTER (WHERE up.vitality_score_current IS NOT NULL 
                     AND up.vitality_score_updated_at >= NOW() - INTERVAL '7 days') as members_with_data,
    COUNT(*) as total_members
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = 'YOUR_FAMILY_ID_HERE'
AND up.vitality_score_current IS NOT NULL
AND up.vitality_score_updated_at >= NOW() - INTERVAL '7 days';
