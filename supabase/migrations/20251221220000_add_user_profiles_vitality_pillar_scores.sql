-- =====================================================
-- Add pillar-level vitality snapshot columns to user_profiles
-- These store the latest (0–100) pillar scores alongside vitality_score_current.
-- Idempotent: safe to run multiple times.
-- =====================================================

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_sleep_pillar_score INTEGER
CHECK (vitality_sleep_pillar_score BETWEEN 0 AND 100);

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_movement_pillar_score INTEGER
CHECK (vitality_movement_pillar_score BETWEEN 0 AND 100);

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_stress_pillar_score INTEGER
CHECK (vitality_stress_pillar_score BETWEEN 0 AND 100);


