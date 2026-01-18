-- EXACT DIAGNOSTIC - No assumptions, just facts
-- Run each query separately to see exactly what's happening

-- QUERY 1: Check if you're in any family at all
SELECT 
    'YOUR AUTH STATUS' as check_type,
    auth.uid() as your_user_id,
    COUNT(*) as families_count
FROM family_members
WHERE user_id = auth.uid();

-- QUERY 2: Your exact family membership info
SELECT 
    'YOUR FAMILY MEMBERSHIP' as check_type,
    fm.id as member_id,
    fm.family_id,
    fm.user_id,
    fm.first_name,
    fm.role,
    fm.invite_status
FROM family_members fm
WHERE fm.user_id = auth.uid();

-- QUERY 3: All members in YOUR family (if you're in one)
SELECT 
    'ALL FAMILY MEMBERS' as check_type,
    fm.first_name,
    fm.user_id,
    up.vitality_score_current,
    up.vitality_score_updated_at,
    NOW() - up.vitality_score_updated_at as score_age,
    CASE 
        WHEN up.vitality_score_current IS NULL THEN 'NO_SCORE'
        WHEN up.vitality_score_updated_at >= NOW() - INTERVAL '7 days' THEN 'FRESH_7D'
        ELSE 'STALE_7D'
    END as status_7day,
    CASE 
        WHEN up.vitality_score_current IS NULL THEN 'NO_SCORE'
        WHEN up.vitality_score_updated_at >= NOW() - INTERVAL '3 days' THEN 'FRESH_3D'
        ELSE 'STALE_3D'
    END as status_3day
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid() 
    LIMIT 1
)
ORDER BY up.vitality_score_updated_at DESC NULLS LAST;

-- QUERY 4: Test RPC directly with YOUR family_id
-- If this fails, we'll see the exact error
DO $$
DECLARE
    my_family_id uuid;
    rpc_result RECORD;
BEGIN
    -- Get your family_id
    SELECT family_id INTO my_family_id
    FROM family_members
    WHERE user_id = auth.uid()
    LIMIT 1;
    
    IF my_family_id IS NULL THEN
        RAISE NOTICE 'ERROR: You are not in any family (family_id is NULL)';
        RETURN;
    END IF;
    
    RAISE NOTICE 'Your family_id: %', my_family_id;
    
    -- Try calling the RPC
    BEGIN
        SELECT * INTO rpc_result 
        FROM get_family_vitality(my_family_id);
        
        RAISE NOTICE 'RPC SUCCESS:';
        RAISE NOTICE '  family_vitality_score: %', rpc_result.family_vitality_score;
        RAISE NOTICE '  members_with_data: %', rpc_result.members_with_data;
        RAISE NOTICE '  members_total: %', rpc_result.members_total;
        RAISE NOTICE '  has_recent_data: %', rpc_result.has_recent_data;
        RAISE NOTICE '  last_updated_at: %', rpc_result.last_updated_at;
        
        IF rpc_result.family_vitality_score IS NULL THEN
            RAISE NOTICE 'PROBLEM: Score is NULL even though RPC succeeded';
            RAISE NOTICE 'This means: members_with_data = 0';
            RAISE NOTICE 'Reason: Either no members have scores, or all scores are too old';
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'RPC FAILED WITH ERROR: %', SQLERRM;
        RAISE NOTICE 'SQLSTATE: %', SQLSTATE;
    END;
END $$;

-- QUERY 5: Manual calculation to see what SHOULD be returned
SELECT 
    'MANUAL CALCULATION (7 DAY WINDOW)' as check_type,
    ROUND(AVG(up.vitality_score_current)) as calculated_family_score,
    COUNT(*) FILTER (WHERE up.vitality_score_current IS NOT NULL 
                     AND up.vitality_score_updated_at >= NOW() - INTERVAL '7 days') as members_with_fresh_data,
    COUNT(*) as total_members,
    MAX(up.vitality_score_updated_at) as most_recent_update
FROM family_members fm
LEFT JOIN user_profiles up ON up.user_id = fm.user_id
WHERE fm.family_id = (
    SELECT family_id 
    FROM family_members 
    WHERE user_id = auth.uid() 
    LIMIT 1
)
AND up.vitality_score_current IS NOT NULL
AND up.vitality_score_updated_at >= NOW() - INTERVAL '7 days';

-- QUERY 6: Check if vitality_progress_score_current column exists
SELECT 
    'SCHEMA CHECK' as check_type,
    EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_profiles'
          AND column_name = 'vitality_progress_score_current'
    ) as has_progress_column,
    EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'family_members'
          AND column_name = 'is_active'
    ) as has_is_active_column;
