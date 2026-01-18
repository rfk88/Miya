-- HOTFIX: Change family vitality freshness from 3 days to 7 days
-- Run this in Supabase SQL Editor NOW to fix the issue immediately
-- Then redeploy the migration later

CREATE OR REPLACE FUNCTION public.get_family_vitality(family_id uuid)
RETURNS TABLE (
  family_vitality_score int,
  members_with_data int,
  members_total int,
  last_updated_at timestamptz,
  has_recent_data boolean,
  family_progress_score int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_is_member boolean;
  has_is_active_column boolean;
  has_progress_column boolean;
BEGIN
  -- Authorization check
  SELECT EXISTS (
    SELECT 1
    FROM public.family_members fm
    WHERE fm.family_id = get_family_vitality.family_id
      AND fm.user_id = auth.uid()
  )
  INTO caller_is_member;

  IF NOT caller_is_member THEN
    RAISE EXCEPTION 'Not authorized to access family vitality';
  END IF;

  -- Check if is_active column exists
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'family_members'
      AND c.column_name = 'is_active'
  )
  INTO has_is_active_column;

  -- Check if progress score column exists
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'user_profiles'
      AND c.column_name = 'vitality_progress_score_current'
  )
  INTO has_progress_column;

  -- Main query with 7 DAY freshness window (changed from 3 days)
  IF has_is_active_column THEN
    IF has_progress_column THEN
      RETURN QUERY
      WITH active_members AS (
        SELECT fm.user_id
        FROM public.family_members fm
        WHERE fm.family_id = get_family_vitality.family_id
          AND fm.is_active IS TRUE
      ),
      member_scores AS (
        SELECT
          am.user_id,
          up.vitality_score_current,
          up.vitality_progress_score_current,
          up.vitality_score_updated_at
        FROM active_members am
        LEFT JOIN public.user_profiles up
          ON up.user_id = am.user_id
      )
      SELECT
        ROUND(
          AVG(member_scores.vitality_score_current) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_vitality_score,
        COUNT(member_scores.user_id) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        )::int AS members_with_data,
        (SELECT COUNT(*) FROM active_members)::int AS members_total,
        MAX(member_scores.vitality_score_updated_at) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        ) AS last_updated_at,
        (
          COUNT(member_scores.user_id) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          ) > 0
        ) AS has_recent_data,
        ROUND(
          AVG(member_scores.vitality_progress_score_current) FILTER (
            WHERE member_scores.vitality_progress_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_progress_score
      FROM member_scores;
    ELSE
      -- No progress column
      RETURN QUERY
      WITH active_members AS (
        SELECT fm.user_id
        FROM public.family_members fm
        WHERE fm.family_id = get_family_vitality.family_id
          AND fm.is_active IS TRUE
      ),
      member_scores AS (
        SELECT
          am.user_id,
          up.vitality_score_current,
          up.vitality_score_updated_at
        FROM active_members am
        LEFT JOIN public.user_profiles up
          ON up.user_id = am.user_id
      )
      SELECT
        ROUND(
          AVG(member_scores.vitality_score_current) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_vitality_score,
        COUNT(member_scores.user_id) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        )::int AS members_with_data,
        (SELECT COUNT(*) FROM active_members)::int AS members_total,
        MAX(member_scores.vitality_score_updated_at) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        ) AS last_updated_at,
        (
          COUNT(member_scores.user_id) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          ) > 0
        ) AS has_recent_data,
        NULL::int AS family_progress_score
      FROM member_scores;
    END IF;
  ELSE
    -- No is_active column (treat all as active)
    IF has_progress_column THEN
      RETURN QUERY
      WITH active_members AS (
        SELECT fm.user_id
        FROM public.family_members fm
        WHERE fm.family_id = get_family_vitality.family_id
      ),
      member_scores AS (
        SELECT
          am.user_id,
          up.vitality_score_current,
          up.vitality_progress_score_current,
          up.vitality_score_updated_at
        FROM active_members am
        LEFT JOIN public.user_profiles up
          ON up.user_id = am.user_id
      )
      SELECT
        ROUND(
          AVG(member_scores.vitality_score_current) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_vitality_score,
        COUNT(member_scores.user_id) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        )::int AS members_with_data,
        (SELECT COUNT(*) FROM active_members)::int AS members_total,
        MAX(member_scores.vitality_score_updated_at) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        ) AS last_updated_at,
        (
          COUNT(member_scores.user_id) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          ) > 0
        ) AS has_recent_data,
        ROUND(
          AVG(member_scores.vitality_progress_score_current) FILTER (
            WHERE member_scores.vitality_progress_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_progress_score
      FROM member_scores;
    ELSE
      -- No progress column, no is_active column
      RETURN QUERY
      WITH active_members AS (
        SELECT fm.user_id
        FROM public.family_members fm
        WHERE fm.family_id = get_family_vitality.family_id
      ),
      member_scores AS (
        SELECT
          am.user_id,
          up.vitality_score_current,
          up.vitality_score_updated_at
        FROM active_members am
        LEFT JOIN public.user_profiles up
          ON up.user_id = am.user_id
      )
      SELECT
        ROUND(
          AVG(member_scores.vitality_score_current) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          )
        )::int AS family_vitality_score,
        COUNT(member_scores.user_id) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        )::int AS members_with_data,
        (SELECT COUNT(*) FROM active_members)::int AS members_total,
        MAX(member_scores.vitality_score_updated_at) FILTER (
          WHERE member_scores.vitality_score_current IS NOT NULL
            AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
        ) AS last_updated_at,
        (
          COUNT(member_scores.user_id) FILTER (
            WHERE member_scores.vitality_score_current IS NOT NULL
              AND member_scores.vitality_score_updated_at >= NOW() - INTERVAL '7 days'
          ) > 0
        ) AS has_recent_data,
        NULL::int AS family_progress_score
      FROM member_scores;
    END IF;
  END IF;
END;
$$;
