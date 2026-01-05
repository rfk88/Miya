-- Diagnostic query to check why weekly badges aren't appearing
-- Run this in Supabase SQL editor to see:
-- 1. What dates are actually in vitality_scores
-- 2. What the week window should be (last 7 days ending yesterday)
-- 3. Whether there's overlap

-- Replace with your actual user_id
-- SET @user_id = 'C03C289A-10CD-440C-BF32-F0AC5E61832C';

-- 1. Check what dates are in the database
SELECT 
    user_id,
    score_date,
    total_score,
    vitality_sleep_pillar_score,
    vitality_movement_pillar_score,
    vitality_stress_pillar_score,
    created_at
FROM vitality_scores
WHERE user_id = 'C03C289A-10CD-440C-BF32-F0AC5E61832C'
ORDER BY score_date DESC
LIMIT 20;

-- 2. Calculate what the week window should be (last 7 days ending yesterday)
SELECT 
    CURRENT_DATE as today,
    CURRENT_DATE - INTERVAL '1 day' as week_end_date,
    CURRENT_DATE - INTERVAL '7 days' as week_start_date,
    (CURRENT_DATE - INTERVAL '1 day')::text as week_end_key,
    (CURRENT_DATE - INTERVAL '7 days')::text as week_start_key;

-- 3. Check if any rows fall in the week window
WITH week_window AS (
    SELECT 
        (CURRENT_DATE - INTERVAL '7 days')::text as week_start,
        (CURRENT_DATE - INTERVAL '1 day')::text as week_end
)
SELECT 
    vs.user_id,
    vs.score_date::text,
    vs.total_score,
    ww.week_start,
    ww.week_end,
    CASE 
        WHEN vs.score_date::text >= ww.week_start AND vs.score_date::text <= ww.week_end 
        THEN 'IN_WINDOW' 
        ELSE 'OUT_OF_WINDOW' 
    END as status
FROM vitality_scores vs
CROSS JOIN week_window ww
WHERE vs.user_id = 'C03C289A-10CD-440C-BF32-F0AC5E61832C'
ORDER BY vs.score_date DESC;



