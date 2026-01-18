-- Show me everything about this family's vitality scores
SELECT 
    fm.first_name,
    up.vitality_score_current,
    up.vitality_score_updated_at,
    EXTRACT(EPOCH FROM (NOW() - up.vitality_score_updated_at)) / 3600 as hours_old,
    CASE 
        WHEN up.vitality_score_updated_at >= NOW() - INTERVAL '7 days' THEN 'INCLUDED'
        ELSE 'EXCLUDED'
    END as will_be_included
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = 'de510539-b812-4312-9f61-812cec10f8c5';

-- Test the RPC
SELECT * FROM get_family_vitality('de510539-b812-4312-9f61-812cec10f8c5'::uuid);
