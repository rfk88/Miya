-- Query 2: All members and their vitality scores
-- REPLACE 'YOUR_FAMILY_ID_HERE' with the family_id from Query 1

SELECT 
    fm.first_name,
    up.vitality_score_current,
    up.vitality_score_updated_at,
    NOW() - up.vitality_score_updated_at as age
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = 'YOUR_FAMILY_ID_HERE'
ORDER BY up.vitality_score_updated_at DESC NULLS LAST;
