-- =====================================================
-- Add daily pillar-level vitality scores to vitality_scores history table
-- (Option A: extend existing vitality_scores)
-- Idempotent and safe to run on existing projects.
-- =====================================================

ALTER TABLE IF EXISTS vitality_scores
ADD COLUMN IF NOT EXISTS vitality_sleep_pillar_score INTEGER
CHECK (vitality_sleep_pillar_score BETWEEN 0 AND 100);

ALTER TABLE IF EXISTS vitality_scores
ADD COLUMN IF NOT EXISTS vitality_movement_pillar_score INTEGER
CHECK (vitality_movement_pillar_score BETWEEN 0 AND 100);

ALTER TABLE IF EXISTS vitality_scores
ADD COLUMN IF NOT EXISTS vitality_stress_pillar_score INTEGER
CHECK (vitality_stress_pillar_score BETWEEN 0 AND 100);


