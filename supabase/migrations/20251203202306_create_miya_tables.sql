-- =====================================================
-- MIYA HEALTH DATABASE SCHEMA
-- =====================================================
-- Copy and paste this entire file into Supabase SQL Editor
-- Then click "Run" to create all tables
-- 
-- IMPORTANT: All enum values match exactly with Swift code
-- =====================================================


-- =====================================================
-- TABLE 1: FAMILIES
-- =====================================================
-- Created when superadmin completes Step 2
-- Stores the family group information

CREATE TABLE families (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Family name (e.g., "The Johnson Family")
    name TEXT NOT NULL,
    
    -- Family size - MUST match Swift enum FamilySizeOption.rawValue exactly:
    -- Valid values: 'twoToFour', 'fourToEight', 'ninePlus'
    size_category TEXT NOT NULL CHECK (size_category IN ('twoToFour', 'fourToEight', 'ninePlus')),
    
    -- The user who created this family (superadmin)
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups by creator
CREATE INDEX idx_families_created_by ON families(created_by);


-- =====================================================
-- TABLE 2: FAMILY_MEMBERS
-- =====================================================
-- Links users to families
-- Created for:
--   1. The superadmin themselves (when they create the family)
--   2. Each invited member (Step 8)

CREATE TABLE family_members (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- The user account (NULL if they haven't accepted invite yet)
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Which family they belong to
    family_id UUID REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    
    -- Their role in the family
    -- 'superadmin' = created the family, full control
    -- 'admin' = can manage family settings
    -- 'member' = regular family member
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('superadmin', 'admin', 'member')),
    
    -- Relationship to family - MUST match Swift enum MemberRelationship.rawValue:
    -- Valid values: 'Partner', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Other'
    -- NULL for superadmin (they don't select a relationship for themselves)
    relationship TEXT CHECK (relationship IN ('Partner', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Other')),
    
    -- Their first name
    first_name TEXT NOT NULL,
    
    -- Invite code (e.g., 'MIYA-AB12') - only for invited members
    invite_code TEXT UNIQUE,
    
    -- Invite status
    -- 'pending' = invited but hasn't joined yet
    -- 'accepted' = has joined the family
    invite_status TEXT DEFAULT 'accepted' CHECK (invite_status IN ('pending', 'accepted')),
    
    -- How they'll be onboarded - MUST match Swift enum MemberOnboardingType.rawValue:
    -- Valid values: 'Guided Setup', 'Self Setup'
    onboarding_type TEXT CHECK (onboarding_type IN ('Guided Setup', 'Self Setup')),
    
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for faster lookups
CREATE INDEX idx_family_members_user_id ON family_members(user_id);
CREATE INDEX idx_family_members_family_id ON family_members(family_id);
CREATE INDEX idx_family_members_invite_code ON family_members(invite_code);


-- =====================================================
-- TABLE 3: USER_PROFILES
-- =====================================================
-- Health profile data from Step 4 (About You)
-- One profile per user

CREATE TABLE user_profiles (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Links to the user account
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
    
    -- Gender - MUST match Swift enum Gender.rawValue:
    -- Valid values: 'Male', 'Female'
    gender TEXT CHECK (gender IN ('Male', 'Female')),
    
    -- Date of birth
    date_of_birth DATE,
    
    -- Ethnicity - MUST match Swift enum Ethnicity.rawValue:
    -- Valid values: 'White', 'Black', 'Asian', 'Hispanic', 'Other'
    ethnicity TEXT CHECK (ethnicity IN ('White', 'Black', 'Asian', 'Hispanic', 'Other')),
    
    -- Smoking status - MUST match Swift enum SmokingStatus.rawValue:
    -- Valid values: 'Never', 'Former', 'Current'
    smoking_status TEXT CHECK (smoking_status IN ('Never', 'Former', 'Current')),
    
    -- Height in centimeters (e.g., 175.5)
    height_cm DECIMAL(5,2),
    
    -- Weight in kilograms (e.g., 70.5)
    weight_kg DECIMAL(5,2),
    
    -- Nutrition quality rating (1 = low, 5 = high)
    nutrition_quality INTEGER CHECK (nutrition_quality >= 1 AND nutrition_quality <= 5),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);


-- =====================================================
-- TABLE 4: HEALTH_CONDITIONS
-- =====================================================
-- Medical conditions from Step 5 (Heart Health) and Step 6 (Medical History)
-- Users can have multiple conditions (one row per condition)

CREATE TABLE health_conditions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Links to the user account
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    
    -- The type of condition
    -- From Step 5 (Heart Health):
    --   'hypertension', 'diabetes', 'cholesterol', 'prior_heart_stroke'
    -- From Step 6 (Medical History):
    --   'ckd', 'atrial_fibrillation', 'family_history_heart'
    -- Special:
    --   'heart_health_unsure', 'medical_history_unsure'
    condition_type TEXT NOT NULL CHECK (condition_type IN (
        'hypertension',
        'diabetes', 
        'cholesterol',
        'prior_heart_stroke',
        'ckd',
        'atrial_fibrillation',
        'family_history_heart',
        'heart_health_unsure',
        'medical_history_unsure'
    )),
    
    -- Which step this came from
    source_step TEXT NOT NULL CHECK (source_step IN ('heart_health', 'medical_history')),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_health_conditions_user_id ON health_conditions(user_id);

-- Prevent duplicate conditions for same user
CREATE UNIQUE INDEX idx_health_conditions_unique ON health_conditions(user_id, condition_type);


-- =====================================================
-- TABLE 5: CONNECTED_WEARABLES
-- =====================================================
-- Wearable devices connected in Step 3
-- A user can connect multiple wearables

CREATE TABLE connected_wearables (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Links to the user account
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    
    -- Type of wearable - MUST match Swift enum WearableType.rawValue:
    -- Valid values: 'appleWatch', 'whoop', 'oura', 'fitbit'
    wearable_type TEXT NOT NULL CHECK (wearable_type IN ('appleWatch', 'whoop', 'oura', 'fitbit')),
    
    -- Whether currently connected
    is_connected BOOLEAN DEFAULT TRUE,
    
    -- When the connection was made
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_connected_wearables_user_id ON connected_wearables(user_id);

-- Prevent duplicate wearable types for same user
CREATE UNIQUE INDEX idx_connected_wearables_unique ON connected_wearables(user_id, wearable_type);


-- =====================================================
-- TABLE 6: PRIVACY_SETTINGS
-- =====================================================
-- Privacy preferences from Step 7
-- One settings record per user

CREATE TABLE privacy_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Links to the user account
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
    
    -- Tier 1 visibility (everyday wellbeing) - MUST match Swift enum Tier1SharingOption.rawValue:
    -- Valid values: 'meOnly', 'family', 'custom'
    tier1_visibility TEXT DEFAULT 'family' CHECK (tier1_visibility IN ('meOnly', 'family', 'custom')),
    
    -- Tier 2 visibility (advanced health) - MUST match Swift enum Tier2SharingOption.rawValue:
    -- Valid values: 'meOnly', 'custom'
    tier2_visibility TEXT DEFAULT 'meOnly' CHECK (tier2_visibility IN ('meOnly', 'custom')),
    
    -- Emergency backup contact (optional)
    backup_contact_name TEXT,
    backup_contact_phone TEXT,
    backup_contact_email TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_privacy_settings_user_id ON privacy_settings(user_id);


-- =====================================================
-- ENUM VALUES REFERENCE (for your Swift code)
-- =====================================================
-- 
-- FamilySizeOption:     'twoToFour', 'fourToEight', 'ninePlus'
-- WearableType:         'appleWatch', 'whoop', 'oura', 'fitbit'
-- Gender:               'Male', 'Female'
-- Ethnicity:            'White', 'Black', 'Asian', 'Hispanic', 'Other'
-- SmokingStatus:        'Never', 'Former', 'Current'
-- Tier1SharingOption:   'meOnly', 'family', 'custom'
-- Tier2SharingOption:   'meOnly', 'custom'
-- MemberRelationship:   'Partner', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Other'
-- MemberOnboardingType: 'Guided Setup', 'Self Setup'
-- 
-- =====================================================


-- =====================================================
-- SUCCESS! 
-- If you see "Success. No rows returned" - that's correct!
-- Check Table Editor to see your 6 new tables.
-- =====================================================

