-- =====================================================
-- GUIDED SETUP V2 MIGRATION
-- =====================================================
-- New flow: Admin can "Fill out now" or "Fill out later"
-- User can accept guided setup or choose self-setup
-- User reviews data before finalizing
--
-- Run this in Supabase SQL Editor

BEGIN;

-- Add guided setup status tracking
ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_setup_status TEXT DEFAULT NULL;

-- Add timestamp tracking
ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_data_filled_at TIMESTAMP DEFAULT NULL;

ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_data_reviewed_at TIMESTAMP DEFAULT NULL;

-- Add constraint for valid status values
-- (Only add if it doesn't exist)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'family_members_guided_setup_status_check'
    ) THEN
        ALTER TABLE family_members
        ADD CONSTRAINT family_members_guided_setup_status_check
        CHECK (guided_setup_status IN (
            NULL,
            'pending_acceptance',           -- Invite created, user hasn't entered code yet
            'accepted_awaiting_data',       -- User accepted guided, waiting for admin to fill data
            'data_complete_pending_review', -- Admin filled data, user needs to review
            'reviewed_complete'             -- User confirmed, profile is done
        ));
    END IF;
END $$;

-- Set status for existing guided setup invites
UPDATE family_members
SET guided_setup_status = CASE
    WHEN onboarding_type = 'Guided Setup' AND guided_data_complete = true THEN 'data_complete_pending_review'
    WHEN onboarding_type = 'Guided Setup' AND (guided_data_complete = false OR guided_data_complete IS NULL) THEN 'pending_acceptance'
    ELSE NULL
END
WHERE guided_setup_status IS NULL;

COMMIT;

-- =====================================================
-- Status Flow:
-- =====================================================
-- 
-- Self Setup:
--   guided_setup_status = NULL (not applicable)
--
-- Guided Setup "Fill out later":
--   1. Admin creates invite → 'pending_acceptance'
--   2. User enters code, accepts → 'accepted_awaiting_data'
--   3. Admin fills data → 'data_complete_pending_review'
--   4. User reviews & confirms → 'reviewed_complete'
--
-- Guided Setup "Fill out now":
--   1. Admin creates invite + fills data → 'data_complete_pending_review'
--   2. User enters code → sees review screen
--   3. User reviews & confirms → 'reviewed_complete'
--
-- User switches to self-setup:
--   At step 2, if user chooses "I'll fill it myself":
--   → onboarding_type changes to 'Self Setup'
--   → guided_setup_status = NULL
--   → User proceeds with self-setup onboarding
-- =====================================================

