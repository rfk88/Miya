-- Backfill date_of_birth for users missing it
-- Sets DOB to 30 years ago for all users without a date_of_birth
-- This unblocks the scoring pipeline which requires age to compute scores

-- Calculate date 30 years ago from today
WITH default_dob AS (
  SELECT (CURRENT_DATE - INTERVAL '30 years')::date AS dob
)
UPDATE user_profiles
SET date_of_birth = (SELECT dob FROM default_dob)
WHERE date_of_birth IS NULL
  OR date_of_birth::text = '';

-- Verify the update
SELECT 
  COUNT(*) AS total_users,
  COUNT(date_of_birth) AS users_with_dob,
  COUNT(*) - COUNT(date_of_birth) AS users_missing_dob
FROM user_profiles;
