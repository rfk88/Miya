-- =====================================================
-- Add family-sharing RLS policy for vitality_scores
-- - Allows users to read their own daily vitality scores
-- - Allows users to read scores for other members in the same family
-- - Keeps scores hidden from users outside the family
-- =====================================================

-- Ensure we are operating on the public schema table
ALTER TABLE public.vitality_scores ENABLE ROW LEVEL SECURITY;

-- Optional: clean up any existing family-sharing policy to avoid duplicates
DROP POLICY IF EXISTS "family_can_read_vitality_scores" ON public.vitality_scores;

-- Users can always read their own vitality_scores rows
DROP POLICY IF EXISTS "vitality_scores_select_own" ON public.vitality_scores;
CREATE POLICY "vitality_scores_select_own"
ON public.vitality_scores
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Users can read vitality_scores rows for other members in the same family
CREATE POLICY "family_can_read_vitality_scores"
ON public.vitality_scores
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.family_members me
    JOIN public.family_members them
      ON them.family_id = me.family_id
     AND them.user_id = public.vitality_scores.user_id
    WHERE me.user_id = auth.uid()
  )
);

