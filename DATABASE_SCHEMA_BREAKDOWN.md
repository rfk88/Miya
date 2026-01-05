# COMPLETE SUPABASE DATABASE SCHEMA BREAKDOWN

## Overview
Miya Health uses 6 custom tables + Supabase Auth (`auth.users`). All tables reference `auth.users(id)` via `user_id` foreign keys.

---

## TABLE 1: `families`
**Purpose:** Stores family group information  
**Created:** When superadmin completes Step 2 (Family Setup)

### Fields:
- `id` (UUID, PRIMARY KEY) - Family unique identifier
- `name` (TEXT, NOT NULL) - Family display name (e.g., "The Johnson Family")
- `size_category` (TEXT, NOT NULL) - Family size tier
  - Valid values: `'twoToFour'`, `'fourToEight'`, `'ninePlus'`
- `max_members` (INTEGER) - Maximum members allowed (2-15)
- `created_by` (UUID, REFERENCES auth.users) - User who created the family (superadmin)
- `created_at` (TIMESTAMP) - When family was created

### Indexes:
- `idx_families_created_by` on `created_by`

---

## TABLE 2: `family_members`
**Purpose:** Links users to families, stores family-specific member data  
**Created:** 
- When superadmin creates family (superadmin row)
- When member is invited (Step 8)

### Fields:
- `id` (UUID, PRIMARY KEY) - Member record unique identifier
- `user_id` (UUID, REFERENCES auth.users, NULLABLE) - User account (NULL if invite not accepted)
- `family_id` (UUID, REFERENCES families, NOT NULL) - Which family they belong to
- `role` (TEXT, NOT NULL, DEFAULT 'member') - Role in family
  - Valid values: `'superadmin'`, `'admin'`, `'member'`
- `relationship` (TEXT, NULLABLE) - Relationship to family
  - Valid values: `'Partner'`, `'Parent'`, `'Child'`, `'Sibling'`, `'Grandparent'`, `'Other'`
  - NULL for superadmin (they don't select relationship)
- **`first_name` (TEXT, NOT NULL)** - **THIS IS WHERE USER NAMES ARE STORED**
- `invite_code` (TEXT, UNIQUE) - Invite code (e.g., 'MIYA-AB12') - only for invited members
- `invite_status` (TEXT, DEFAULT 'accepted') - Invite status
  - Valid values: `'pending'`, `'accepted'`
- `onboarding_type` (TEXT) - How they'll be onboarded
  - Valid values: `'Guided Setup'`, `'Self Setup'`
- `joined_at` (TIMESTAMP) - When they joined the family

### Indexes:
- `idx_family_members_user_id` on `user_id`
- `idx_family_members_family_id` on `family_id`
- `idx_family_members_invite_code` on `invite_code`

### Key Points:
- **Superadmins ARE in this table** (they have a row with `role='superadmin'`)
- **Members ARE in this table** (they have a row with `role='member'`)
- **`first_name` is the ONLY place user display names are stored**

---

## TABLE 3: `user_profiles`
**Purpose:** Health profile data from Step 4 (About You)  
**Created:** When user completes Step 4 onboarding

### Fields:
- `id` (UUID, PRIMARY KEY) - Profile unique identifier
- `user_id` (UUID, REFERENCES auth.users, UNIQUE, NOT NULL) - Links to user account
- `gender` (TEXT) - Gender
  - Valid values: `'Male'`, `'Female'`
- `date_of_birth` (DATE) - Date of birth
- `ethnicity` (TEXT) - Ethnicity
  - Valid values: `'White'`, `'Black'`, `'Asian'`, `'Hispanic'`, `'Other'`
- `smoking_status` (TEXT) - Smoking status
  - Valid values: `'Never'`, `'Former'`, `'Current'`
- `height_cm` (DECIMAL(5,2)) - Height in centimeters
- `weight_kg` (DECIMAL(5,2)) - Weight in kilograms
- `nutrition_quality` (INTEGER) - Nutrition quality rating (1-5)
- `created_at` (TIMESTAMP) - When profile was created
- `updated_at` (TIMESTAMP) - When profile was last updated

### Indexes:
- `idx_user_profiles_user_id` on `user_id`

### Key Points:
- **NO `first_name` field** - Names are stored in `family_members.first_name`
- One profile per user (UNIQUE constraint on `user_id`)
- Contains health/onboarding data, not identity data

---

## TABLE 4: `health_conditions`
**Purpose:** Medical conditions from Step 5 (Heart Health) and Step 6 (Medical History)  
**Created:** When user selects conditions during onboarding

### Fields:
- `id` (UUID, PRIMARY KEY) - Condition record unique identifier
- `user_id` (UUID, REFERENCES auth.users, NOT NULL) - Links to user account
- `condition_type` (TEXT, NOT NULL) - Type of condition
  - Valid values:
    - Blood Pressure: `'bp_normal'`, `'bp_elevated_untreated'`, `'bp_elevated_treated'`, `'bp_unknown'`
    - Diabetes: `'diabetes_none'`, `'diabetes_pre_diabetic'`, `'diabetes_type_1'`, `'diabetes_type_2'`, `'diabetes_unknown'`
    - Prior Events: `'prior_heart_attack'`, `'prior_stroke'`
    - Family History: `'family_history_heart_early'`, `'family_history_stroke_early'`, `'family_history_type2_diabetes'`
    - Unsure: `'heart_health_unsure'`, `'medical_history_unsure'`
- `source_step` (TEXT, NOT NULL) - Which step this came from
  - Valid values: `'heart_health'`, `'medical_history'`
- `created_at` (TIMESTAMP) - When condition was recorded

### Indexes:
- `idx_health_conditions_user_id` on `user_id`
- `idx_health_conditions_unique` UNIQUE on (`user_id`, `condition_type`) - Prevents duplicates

### Key Points:
- Users can have multiple conditions (one row per condition)
- Same condition type cannot be added twice for same user

---

## TABLE 5: `connected_wearables`
**Purpose:** Wearable devices connected in Step 3  
**Created:** When user connects a wearable device

### Fields:
- `id` (UUID, PRIMARY KEY) - Wearable record unique identifier
- `user_id` (UUID, REFERENCES auth.users, NOT NULL) - Links to user account
- `wearable_type` (TEXT, NOT NULL) - Type of wearable
  - Valid values: `'appleWatch'`, `'whoop'`, `'oura'`, `'fitbit'`
- `is_connected` (BOOLEAN, DEFAULT TRUE) - Whether currently connected
- `connected_at` (TIMESTAMP) - When connection was made

### Indexes:
- `idx_connected_wearables_user_id` on `user_id`
- `idx_connected_wearables_unique` UNIQUE on (`user_id`, `wearable_type`) - Prevents duplicate types

### Key Points:
- Users can connect multiple wearables (one row per type)
- Same wearable type cannot be connected twice for same user

---

## TABLE 6: `privacy_settings`
**Purpose:** Privacy preferences from Step 7  
**Created:** When user completes privacy settings

### Fields:
- `id` (UUID, PRIMARY KEY) - Settings record unique identifier
- `user_id` (UUID, REFERENCES auth.users, UNIQUE, NOT NULL) - Links to user account
- `tier1_visibility` (TEXT, DEFAULT 'family') - Tier 1 visibility (everyday wellbeing)
  - Valid values: `'meOnly'`, `'family'`, `'custom'`
- `tier2_visibility` (TEXT, DEFAULT 'meOnly') - Tier 2 visibility (advanced health)
  - Valid values: `'meOnly'`, `'custom'`
- `backup_contact_name` (TEXT, NULLABLE) - Emergency backup contact name
- `backup_contact_phone` (TEXT, NULLABLE) - Emergency backup contact phone
- `backup_contact_email` (TEXT, NULLABLE) - Emergency backup contact email
- `created_at` (TIMESTAMP) - When settings were created
- `updated_at` (TIMESTAMP) - When settings were last updated

### Indexes:
- `idx_privacy_settings_user_id` on `user_id`

### Key Points:
- One settings record per user (UNIQUE constraint on `user_id`)

---

## SUMMARY: WHERE DATA IS STORED

### User Identity/Name:
- **`family_members.first_name`** ← **ONLY place names are stored**
- `auth.users.email` - Email/login

### User Health Data:
- `user_profiles.*` - Demographics, health metrics
- `health_conditions.*` - Medical conditions

### Family Structure:
- `families.*` - Family group info
- `family_members.*` - Who belongs to which family, roles, relationships

### Device Connections:
- `connected_wearables.*` - Wearable devices

### Privacy:
- `privacy_settings.*` - Sharing preferences

---

## CRITICAL ARCHITECTURE NOTES:

1. **Names are ONLY in `family_members.first_name`** - NOT in `user_profiles`
2. **Superadmins ARE in `family_members`** - They have a row with `role='superadmin'`
3. **Members ARE in `family_members`** - They have a row with `role='member'`
4. **Every authenticated user has a `user_profiles` row** (created during onboarding)
5. **Every user in a family has a `family_members` row** (including superadmin)

---

## FIXED CODE BEHAVIOR:

`updateMyMemberName()` now:
- Updates ONLY `family_members.first_name` by `user_id`
- Does NOT require `family_id` (avoids mismatched state issues)
- Provides clear error messages if user not found in `family_members`

