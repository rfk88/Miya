# Complete Invite User Flow Documentation

## Overview

When an admin invites a user and selects **"Guided"** or **"Self"** setup, the system implements a sophisticated multi-step flow with different paths based on the selection. This document provides a complete breakdown of all files, code, and flows involved.

---

## Table of Contents

1. [Database Schema](#database-schema)
2. [Key Data Models](#key-data-models)
3. [Flow Diagrams](#flow-diagrams)
4. [File Structure](#file-structure)
5. [Detailed Code Flows](#detailed-code-flows)
6. [Guided Setup Status States](#guided-setup-status-states)

---

## Database Schema

### `family_members` Table (Key Columns)

```sql
CREATE TABLE family_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),  -- NULL until invite redeemed
  family_id UUID REFERENCES families(id),
  first_name TEXT NOT NULL,
  relationship TEXT,                       -- Partner, Parent, Child, etc.
  onboarding_type TEXT,                    -- "Guided Setup" or "Self Setup"
  invite_code TEXT UNIQUE,                 -- e.g. "MIYA-AB12"
  invite_status TEXT,                      -- "pending" or "accepted"
  role TEXT DEFAULT 'member',              -- "superadmin" or "member"
  
  -- Guided Setup columns
  guided_setup_status TEXT,                -- See status states below
  guided_health_data JSONB,                -- Admin-filled health data
  guided_data_complete BOOLEAN,
  guided_data_filled_at TIMESTAMP,
  guided_data_reviewed_at TIMESTAMP,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

---

## Key Data Models

### 1. GuidedSetupStatus Enum
**File:** `Miya Health/GuidedSetupStatus.swift`

```swift
enum GuidedSetupStatus: String, Codable, CaseIterable {
    case pendingAcceptance = "pending_acceptance"
    case acceptedAwaitingData = "accepted_awaiting_data"
    case dataCompletePendingReview = "data_complete_pending_review"
    case reviewedComplete = "reviewed_complete"
}
```

### 2. InviteDetails Struct
**File:** `Miya Health/DataManager.swift` (line 3123)

```swift
struct InviteDetails {
    let memberId: String              // family_members.id
    let familyId: String
    let familyName: String
    let firstName: String
    let relationship: String
    let onboardingType: String        // "Guided Setup" or "Self Setup"
    let isGuidedSetup: Bool           // true if "Guided Setup"
    let guidedSetupStatus: GuidedSetupStatus?
    let hasGuidedData: Bool           // true if admin filled data
}
```

### 3. FamilyMemberRecord Struct
**File:** `Miya Health/DataManager.swift` (line 3156)

```swift
struct FamilyMemberRecord: Codable {
    let id: UUID
    let userId: UUID?                 // NULL until invite redeemed
    let familyId: UUID?
    let role: String
    let relationship: String?
    let firstName: String
    let inviteCode: String?
    let inviteStatus: String          // "pending" or "accepted"
    let onboardingType: String?       // "Guided Setup" or "Self Setup"
    let guidedDataComplete: Bool?
    let guidedSetupStatus: String?
    let guidedHealthData: GuidedHealthDataJSON?
    // ... other fields
}
```

### 4. GuidedHealthData Struct
**File:** `Miya Health/DataManager.swift`

Stores health information filled by admin:
- About You: gender, DOB, height, weight, ethnicity, smoking
- Heart Health: blood pressure, diabetes, prior conditions
- Medical History: family history flags

---

## Flow Diagrams

### Flow 1: Admin Creates Invite (Guided Setup)

```
┌─────────────────────────────────────────────────────────────┐
│ FamilyMembersInviteView (ContentView.swift:4069)            │
│                                                               │
│ Admin fills:                                                  │
│  - First Name                                                 │
│  - Relationship (Partner/Parent/Child/etc.)                   │
│  - Onboarding Type: "Guided Setup" ✓                         │
│                                                               │
│ Clicks: "Generate invite code"                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ generateInviteCodeAsync() (ContentView.swift:4416)          │
│                                                               │
│ Calls: dataManager.saveFamilyMemberInviteWithId(             │
│   firstName: "...",                                           │
│   relationship: "...",                                        │
│   onboardingType: "Guided Setup",                            │
│   guidedSetupStatus: .pendingAcceptance                      │
│ )                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ DataManager.saveFamilyMemberInviteWithId()                   │
│ (DataManager.swift:2002)                                      │
│                                                               │
│ 1. Generate unique code (e.g. "MIYA-AB12")                  │
│ 2. Insert to family_members table:                           │
│    - user_id: NULL                                           │
│    - family_id: admin's family                               │
│    - first_name, relationship                                │
│    - onboarding_type: "Guided Setup"                         │
│    - invite_code: "MIYA-AB12"                                │
│    - invite_status: "pending"                                │
│    - role: "member"                                          │
│ 3. Update guided_setup_status: "pending_acceptance"          │
│ 4. Return: (inviteCode, memberId)                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ InviteCodeSheet (ContentView.swift:4378)                     │
│                                                               │
│ Shows: "MIYA-AB12"                                           │
│ "Share this code with [Name]"                                │
└─────────────────────────────────────────────────────────────┘
```

### Flow 2: Admin Creates Invite (Self Setup)

Same as above, but:
- `onboardingType: "Self Setup"`
- `guidedSetupStatus: NULL` (not applicable for self setup)

---

### Flow 3: Invited User Enters Code (Guided Setup - No Data Yet)

```
┌─────────────────────────────────────────────────────────────┐
│ EnterCodeView (ContentView.swift:363)                        │
│                                                               │
│ User enters: "MIYA-AB12"                                     │
│ Clicks: "Continue"                                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ validateInviteCode() (ContentView.swift:604)                 │
│                                                               │
│ Calls: dataManager.lookupInviteCode(code: "MIYA-AB12")      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ DataManager.lookupInviteCode() (DataManager.swift:2097)      │
│                                                               │
│ 1. Query family_members where invite_code = "MIYA-AB12"     │
│ 2. Check invite_status != "accepted"                         │
│ 3. Check user_id is NULL                                     │
│ 4. Fetch family name                                         │
│ 5. Parse guided_setup_status                                 │
│ 6. Return InviteDetails:                                     │
│    - isGuidedSetup: true                                     │
│    - guidedSetupStatus: .pendingAcceptance                   │
│    - hasGuidedData: false                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ EnterCodeView - createAccountSection                         │
│ (ContentView.swift:480)                                       │
│                                                               │
│ Shows: "Join the [Family] family"                            │
│ User fills: email, password                                  │
│ Clicks: "Create account and join"                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ createAccountAndJoin() (ContentView.swift:640)               │
│                                                               │
│ 1. authManager.signUp(email, password, firstName)           │
│    └─> Creates user in auth.users                            │
│                                                               │
│ 2. dataManager.createInitialProfile(userId, firstName, 2)    │
│    └─> Creates user_profiles row                             │
│                                                               │
│ 3. dataManager.completeInviteRedemption(code, userId)        │
│    └─> Updates family_members:                               │
│        - user_id: [new user's id]                            │
│        - invite_status: "accepted"                           │
│                                                               │
│ 4. Store in OnboardingManager:                               │
│    - isInvitedUser = true                                    │
│    - guidedSetupStatus = .pendingAcceptance                  │
│    - invitedMemberId = [member_id]                           │
│    - invitedFamilyId = [family_id]                           │
│                                                               │
│ 5. Show GuidedSetupAcceptancePrompt sheet                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ GuidedSetupAcceptancePrompt (ContentView.swift:4918)         │
│                                                               │
│ "Your admin can help you set up your profile"                │
│                                                               │
│ Option 1: [Accept Guided Setup]                              │
│           "Let them fill out your health info"               │
│                                                               │
│ Option 2: [I'll fill it out myself]                         │
│           "Complete your own health profile"                 │
└────────────┬───────────────────────┬────────────────────────┘
             │                       │
             │ Accept Guided         │ Fill Myself
             ▼                       ▼
┌──────────────────────────┐  ┌─────────────────────────────┐
│ acceptGuidedSetup()      │  │ switchToSelfSetup()         │
│ (ContentView.swift:704)   │  │ (ContentView.swift:720)      │
│                          │  │                             │
│ Calls:                   │  │ Calls:                      │
│ dataManager              │  │ dataManager                 │
│  .acceptGuidedSetup()    │  │  .switchToSelfSetup()       │
│                          │  │                             │
│ Updates DB:              │  │ Updates DB:                 │
│ guided_setup_status:     │  │ onboarding_type:            │
│  "accepted_awaiting_data"│  │  "Self Setup"               │
│                          │  │ guided_setup_status: NULL   │
│                          │  │                             │
│ Navigate to:             │  │ Navigate to:                │
│ WearableSelectionView    │  │ WearableSelectionView       │
│ (Guided mode)            │  │ (Self mode)                 │
└──────────────────────────┘  └─────────────────────────────┘
```

### Flow 4: Admin Fills Guided Data

```
┌─────────────────────────────────────────────────────────────┐
│ DashboardView - Pending Guided Setups Section                │
│                                                               │
│ Shows members with status = "accepted_awaiting_data"         │
│ Admin clicks: "Fill Out" for [Member Name]                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ GuidedHealthDataEntryFlow (ContentView.swift:5380+)          │
│                                                               │
│ Step 1: About You                                            │
│  - Gender, Date of Birth                                     │
│  - Height, Weight                                            │
│  - Ethnicity, Smoking Status                                 │
│                                                               │
│ Step 2: Heart Health                                         │
│  - Blood Pressure Status                                     │
│  - Diabetes Status                                           │
│  - Prior Heart Attack / Stroke                               │
│  - Chronic Kidney Disease, A-Fib, High Cholesterol          │
│                                                               │
│ Step 3: Medical History                                      │
│  - Family history of early heart disease                     │
│  - Family history of early stroke                            │
│  - Family history of Type 2 diabetes                         │
│                                                               │
│ Clicks: "Save & Complete"                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ saveGuidedData() (ContentView.swift:5900+)                   │
│                                                               │
│ 1. Build GuidedHealthData struct from form values            │
│                                                               │
│ 2. dataManager.saveGuidedHealthData(memberId, data)          │
│    └─> Updates family_members:                               │
│        - guided_health_data: {JSON blob}                     │
│        - guided_data_complete: true                          │
│                                                               │
│ 3. dataManager.updateGuidedSetupStatus(                      │
│      memberId,                                               │
│      .dataCompletePendingReview                              │
│    )                                                          │
│    └─> Updates:                                              │
│        - guided_setup_status: "data_complete_pending_review" │
│        - guided_data_filled_at: NOW()                        │
└─────────────────────────────────────────────────────────────┘
```

### Flow 5: Invited User Reviews & Confirms Data

```
┌─────────────────────────────────────────────────────────────┐
│ User logs in / resumes onboarding                            │
│                                                               │
│ LandingView checks OnboardingManager.guidedSetupStatus       │
│ Status = "data_complete_pending_review"                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ GuidedSetupReviewView (ContentView.swift:5064)               │
│                                                               │
│ Loads: dataManager.loadGuidedHealthData(memberId)            │
│                                                               │
│ Displays all health information in review format:            │
│  - About You section (read-only cards)                       │
│  - Heart Health section                                      │
│  - Medical History section                                   │
│                                                               │
│ Option 1: [Confirm & Continue]                               │
│ Option 2: [Make Changes]                                     │
└────────────┬───────────────────────┬────────────────────────┘
             │                       │
             │ Confirm               │ Make Changes
             ▼                       ▼
┌──────────────────────────┐  ┌─────────────────────────────┐
│ confirmData()            │  │ Navigate to:                │
│ (ContentView.swift:5308)  │  │ AboutYouView (edit mode)    │
│                          │  │                             │
│ 1. dataManager           │  │ User manually edits         │
│    .confirmGuidedData    │  │ their profile through       │
│    Review(memberId)      │  │ standard onboarding         │
│                          │  │ screens                     │
│ 2. Writes guided data to │  └─────────────────────────────┘
│    user_profiles table   │
│                          │
│ 3. Updates:              │
│    guided_setup_status:  │
│     "reviewed_complete"  │
│    guided_data_reviewed  │
│     _at: NOW()           │
│                          │
│ 4. Calculate risk        │
│    assessment            │
│                          │
│ 5. Save risk to DB       │
│                          │
│ 6. Mark onboarding       │
│    complete              │
│                          │
│ 7. Navigate to Dashboard │
└──────────────────────────┘
```

### Flow 6: Self Setup User Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User enters code for "Self Setup" invite                     │
│                                                               │
│ After createAccountAndJoin():                                 │
│  - isInvitedUser = true                                      │
│  - guidedSetupStatus = null                                  │
│                                                               │
│ Navigate directly to: WearableSelectionView                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Standard Onboarding Flow (Self-Paced)                        │
│                                                               │
│ Step 2: WearableSelectionView                                │
│ Step 3: AboutYouView (user fills own data)                  │
│ Step 4: HeartHealthView                                      │
│ Step 5: MedicalHistoryView                                   │
│ Step 6: RiskResultsView                                      │
│ Step 7: AlertsChampionView (NOT FamilyMembersInviteView)    │
│         ↑ Invited users skip family creation                 │
│                                                               │
│ Complete → Navigate to Dashboard                             │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

### Core Files

| File | Lines | Purpose |
|------|-------|---------|
| `Miya Health/ContentView.swift` | 6385 | Main view container with all onboarding views |
| `Miya Health/DataManager.swift` | 3400+ | Database operations and business logic |
| `Miya Health/OnboardingManager.swift` | 317 | State management for onboarding process |
| `Miya Health/GuidedSetupStatus.swift` | 26 | Enum for guided setup states |

### Key Views in ContentView.swift

| View | Line Range | Purpose |
|------|------------|---------|
| `FamilyMembersInviteView` | 4069-4560 | Admin creates invites |
| `EnterCodeView` | 363-735 | User enters invite code & creates account |
| `GuidedSetupAcceptancePrompt` | 4918-5007 | User chooses guided vs self |
| `GuidedWaitingForAdminView` | 5011-5059 | Waiting screen after accepting guided |
| `GuidedSetupReviewView` | 5064-5377 | User reviews admin-filled data |
| `GuidedHealthDataEntryFlow` | 5380-6380 | Admin fills health data for member |

### Key DataManager Functions

| Function | Line | Purpose |
|----------|------|---------|
| `generateInviteCode()` | 1825 | Generate unique "MIYA-XXXX" code |
| `saveFamilyMemberInviteWithId()` | 2002 | Create invite record in DB |
| `lookupInviteCode()` | 2097 | Validate code and fetch invite details |
| `completeInviteRedemption()` | 2189 | Link new user to family |
| `acceptGuidedSetup()` | 2666 | User accepts guided setup |
| `switchToSelfSetup()` | 2625 | User switches to self setup |
| `saveGuidedHealthData()` | 2289 | Admin saves health data |
| `loadGuidedHealthData()` | 2257 | Load saved health data |
| `confirmGuidedDataReview()` | 2572 | User confirms data, write to profile |
| `updateGuidedSetupStatus()` | ~2400 | Update status state machine |

---

## Guided Setup Status States

### Status State Machine

```
NULL
  └─> Used for "Self Setup" invites (guided features not applicable)

pending_acceptance
  └─> Admin creates "Guided Setup" invite
  └─> Waiting for invited user to accept
  
  User Actions:
  ├─> Accept Guided Setup → accepted_awaiting_data
  └─> Fill Myself → Switch to Self Setup (status → NULL)

accepted_awaiting_data
  └─> User accepted guided setup
  └─> Waiting for admin to fill health data
  
  Admin Action:
  └─> Complete GuidedHealthDataEntryFlow → data_complete_pending_review

data_complete_pending_review
  └─> Admin filled health data
  └─> Waiting for user to review and confirm
  
  User Actions:
  ├─> Confirm & Continue → reviewed_complete
  └─> Make Changes → Edit via standard onboarding (can still confirm later)

reviewed_complete
  └─> User confirmed data
  └─> Data written to user_profiles
  └─> Onboarding complete → Navigate to Dashboard
```

### Database Columns Updated per Status

| Status | DB Columns Updated |
|--------|-------------------|
| `pending_acceptance` | `guided_setup_status` |
| `accepted_awaiting_data` | `guided_setup_status` |
| `data_complete_pending_review` | `guided_setup_status`, `guided_health_data`, `guided_data_complete`, `guided_data_filled_at` |
| `reviewed_complete` | `guided_setup_status`, `guided_data_reviewed_at`, plus writes to `user_profiles` table |

---

## Detailed Code Flows

### 1. Admin Generates Invite Code

**File:** `Miya Health/ContentView.swift`

```swift
// Line 4289-4308: Generate button in FamilyMembersInviteView
Button {
    generateInviteCode(fillOutNow: false)
} label: {
    HStack(spacing: 8) {
        if dataManager.isLoading {
            ProgressView()
        }
        Text(dataManager.isLoading ? "Generating..." : "Generate invite code")
    }
}
.disabled(!canGenerateInvite || dataManager.isLoading)

// Line 4416-4460: Async invite generation
private func generateInviteCodeAsync(fillOutNow: Bool) async {
    guard let relationship = selectedRelationship,
          let onboardingType = selectedOnboardingType
    else { return }
    
    // Determine the initial guided setup status
    let guidedStatus: GuidedSetupStatus? = 
        onboardingType == .guided ? .pendingAcceptance : nil
    
    // Save to database and get invite code + member ID
    let (inviteCode, memberId) = try await dataManager.saveFamilyMemberInviteWithId(
        firstName: firstName.trimmingCharacters(in: .whitespaces),
        relationship: relationship.rawValue,
        onboardingType: onboardingType.rawValue,
        guidedSetupStatus: guidedStatus
    )
    
    // Show invite code sheet
    currentInviteCode = inviteCode
    currentInviteName = firstName
    showInviteSheet = true
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2002-2090: Save invite with ID
func saveFamilyMemberInviteWithId(
    firstName: String,
    relationship: String,
    onboardingType: String,
    guidedSetupStatus: GuidedSetupStatus? = nil
) async throws -> (inviteCode: String, memberId: String) {
    
    // Generate unique invite code
    let inviteCode = try await generateInviteCode()
    
    // Build insert data
    let insertData: [String: AnyJSON] = [
        "user_id": .null,
        "family_id": .string(familyId),
        "first_name": .string(firstName),
        "relationship": .string(relationship),
        "onboarding_type": .string(onboardingType),
        "invite_code": .string(inviteCode),
        "invite_status": .string("pending"),
        "role": .string("member")
    ]
    
    // Insert and get the ID back
    let response: [InsertResponse] = try await supabase
        .from("family_members")
        .insert(insertData)
        .select("id")
        .execute()
        .value
    
    let memberId = response.first?.id.uuidString
    
    // Set guided_setup_status if provided
    if let status = guidedSetupStatus {
        try await updateGuidedSetupStatus(memberId: memberId, status: status)
    }
    
    return (inviteCode, memberId)
}

// Line 1825-1853: Generate unique code
func generateInviteCode() async throws -> String {
    let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    var attempts = 0
    let maxAttempts = 5
    
    while attempts < maxAttempts {
        // Generate random code
        let randomCode = String((0..<4).compactMap { _ in characters.randomElement() })
        let inviteCode = "MIYA-\(randomCode)"
        
        // Check if code already exists
        let existing: [InviteCodeRow] = try await supabase
            .from("family_members")
            .select("invite_code")
            .eq("invite_code", value: inviteCode)
            .execute()
            .value
        
        if existing.isEmpty {
            return inviteCode
        }
        
        attempts += 1
    }
    
    throw DataError.databaseError("Failed to generate unique invite code")
}
```

### 2. User Enters Invite Code

**File:** `Miya Health/ContentView.swift`

```swift
// Line 604-638: Validate invite code
private func validateInviteCode() async {
    showError = false
    isValidatingCode = true
    
    let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    inviteCode = normalizedCode
    
    do {
        // Look up the invite code
        let details = try await dataManager.lookupInviteCode(code: normalizedCode)
        inviteDetails = details
        codeValidated = true
        
        print("✅ Invite code validated:")
        print("   - Family: \(details.familyName)")
        print("   - Member: \(details.firstName)")
        print("   - Type: \(details.onboardingType)")
        print("   - Is Guided: \(details.isGuidedSetup)")
        print("   - Status: \(details.guidedSetupStatus?.rawValue ?? "nil")")
        
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    isValidatingCode = false
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2097-2183: Lookup invite code
func lookupInviteCode(code: String) async throws -> InviteDetails {
    let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    
    // Look up the invite code in family_members
    let invites: [FamilyMemberRecord] = try await supabase
        .from("family_members")
        .select()
        .eq("invite_code", value: normalizedCode)
        .limit(1)
        .execute()
        .value
    
    guard let invite = invites.first else {
        throw DataError.invalidData("Invalid invite code. Please check and try again.")
    }
    
    // Check if already redeemed
    if invite.inviteStatus == "accepted" {
        throw DataError.invalidData("This invite code has already been used.")
    }
    
    // Fetch the family name
    guard let familyId = invite.familyId else {
        throw DataError.invalidData("Invalid invite: no family associated.")
    }
    
    let families: [FamilyRecord] = try await supabase
        .from("families")
        .select()
        .eq("id", value: familyId.uuidString)
        .execute()
        .value
    
    guard let family = families.first else {
        throw DataError.invalidData("Family not found.")
    }
    
    // Parse guided setup status
    let guidedStatus = parseGuidedSetupStatus(invite.guidedSetupStatus)
    
    // Check if guided data exists
    let hasGuidedData = invite.guidedHealthData != nil
    
    return InviteDetails(
        memberId: invite.id.uuidString,
        familyId: familyId.uuidString,
        familyName: family.name,
        firstName: invite.firstName,
        relationship: invite.relationship ?? "",
        onboardingType: invite.onboardingType ?? "Self Setup",
        isGuidedSetup: invite.onboardingType == "Guided Setup",
        guidedSetupStatus: guidedStatus,
        hasGuidedData: hasGuidedData
    )
}
```

### 3. User Creates Account and Joins Family

**File:** `Miya Health/ContentView.swift`

```swift
// Line 640-693: Create account and join
private func createAccountAndJoin() async {
    guard let details = inviteDetails else { return }
    
    do {
        let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Create the user account
        let userId = try await authManager.signUp(
            email: email,
            password: password,
            firstName: details.firstName
        )
        
        // 2. Create initial user_profile (step 2 since they've already "joined" a family)
        try await dataManager.createInitialProfile(
            userId: userId,
            firstName: details.firstName,
            step: 2
        )
        
        // 3. Complete the invite redemption (link user to family)
        try await dataManager.completeInviteRedemption(
            code: normalizedCode,
            userId: userId
        )
        
        // 4. Store info in onboarding manager
        onboardingManager.firstName = details.firstName
        onboardingManager.email = email
        onboardingManager.currentUserId = userId
        onboardingManager.isInvitedUser = true
        onboardingManager.familyName = details.familyName
        onboardingManager.guidedSetupStatus = details.guidedSetupStatus
        onboardingManager.invitedMemberId = details.memberId
        onboardingManager.invitedFamilyId = details.familyId
        
        // 5. Routing:
        // - Guided Setup invites: show acceptance prompt first.
        // - Self Setup invites: proceed through standard onboarding screens.
        if details.isGuidedSetup {
            showGuidedAcceptancePrompt = true
        } else {
            wearablesIsGuidedSetupInvite = false
            onboardingManager.setCurrentStep(2) // Wearables
            navigateToWearables = true
        }
        
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2189-2244: Complete invite redemption
func completeInviteRedemption(code: String, userId: String) async throws {
    let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    
    // Update the family_members record
    let updateData: [String: AnyJSON] = [
        "user_id": .string(userId),
        "invite_status": .string("accepted")
    ]
    
    try await supabase
        .from("family_members")
        .update(updateData)
        .eq("invite_code", value: normalizedCode)
        .execute()
    
    // Fetch and set the family info for this session
    let invites: [FamilyMemberRecord] = try await supabase
        .from("family_members")
        .select()
        .eq("invite_code", value: normalizedCode)
        .execute()
        .value
    
    if let invite = invites.first, let familyId = invite.familyId {
        currentFamilyId = familyId.uuidString
        
        // Fetch family name
        let families: [FamilyRecord] = try await supabase
            .from("families")
            .select()
            .eq("id", value: familyId.uuidString)
            .execute()
            .value
        
        if let family = families.first {
            familyName = family.name
        }
    }
    
    print("✅ DataManager: Invite redeemed successfully for user \(userId)")
}
```

### 4. User Accepts Guided Setup or Switches to Self

**File:** `Miya Health/ContentView.swift`

```swift
// Line 4918-5007: Acceptance prompt UI
struct GuidedSetupAcceptancePrompt: View {
    let memberName: String
    let adminName: String
    let onAcceptGuidedSetup: () -> Void
    let onFillMyself: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("\(adminName) can help you set up your profile")
                .font(.system(size: 20, weight: .bold))
            
            // Option 1: Accept Guided Setup
            Button(action: onAcceptGuidedSetup) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accept Guided Setup")
                        Text("Let them fill out your health info")
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                }
                .background(Color.miyaPrimary)
            }
            
            // Option 2: Fill out myself
            Button(action: onFillMyself) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I'll fill it out myself")
                        Text("Complete your own health profile")
                    }
                    Spacer()
                    Image(systemName: "pencil.circle")
                }
                .background(Color.white)
            }
        }
    }
}

// Line 704-718: Accept guided setup
private func acceptGuidedSetup() async {
    guard let details = inviteDetails else { return }
    do {
        try await dataManager.acceptGuidedSetup(memberId: details.memberId)
        onboardingManager.guidedSetupStatus = .acceptedAwaitingData
        
        // Next: connect wearable while admin completes health profile
        wearablesIsGuidedSetupInvite = true
        onboardingManager.setCurrentStep(2) // Wearables
        navigateToWearables = true
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// Line 720-734: Switch to self setup
private func switchToSelfSetup() async {
    guard let details = inviteDetails else { return }
    do {
        try await dataManager.switchToSelfSetup(memberId: details.memberId)
        onboardingManager.guidedSetupStatus = nil
        
        // Standard onboarding
        wearablesIsGuidedSetupInvite = false
        onboardingManager.setCurrentStep(2) // Wearables
        navigateToWearables = true
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2666-2679: Accept guided setup
func acceptGuidedSetup(memberId: String) async throws {
    let supported = await detectGuidedSetupSchemaAvailability()
    guard supported else {
        throw DataError.databaseError("Couldn't accept guided setup. Please try again.")
    }
    
    // Transition: pending_acceptance -> accepted_awaiting_data
    try await updateGuidedSetupStatus(memberId: memberId, status: .acceptedAwaitingData)
    print("✅ DataManager: User accepted guided setup for member \(memberId)")
}

// Line 2625-2662: Switch to self setup
func switchToSelfSetup(memberId: String) async throws {
    let supported = await detectGuidedSetupSchemaAvailability()
    
    let updateData: [String: AnyJSON] = supported
        ? ["onboarding_type": .string("Self Setup"), "guided_setup_status": .null]
        : ["onboarding_type": .string("Self Setup")]
    
    try await supabase
        .from("family_members")
        .update(updateData)
        .eq("id", value: memberId)
        .execute()
    
    print("✅ DataManager: Switched member \(memberId) to Self Setup")
}
```

### 5. Admin Fills Guided Data

**File:** `Miya Health/ContentView.swift`

```swift
// Line 5900-6023: Save guided data
private func saveGuidedData() async {
    // Build GuidedHealthData struct
    let aboutYou = GuidedHealthData.AboutYouData(
        gender: gender,
        dateOfBirth: dateOfBirth,  // formatted as yyyy-MM-dd
        heightCm: heightCm,
        weightKg: weightKg,
        ethnicity: ethnicity,
        smokingStatus: smokingStatus
    )
    
    let heartHealth = GuidedHealthData.HeartHealthData(
        bloodPressureStatus: bloodPressureStatus,
        diabetesStatus: diabetesStatus,
        hasPriorHeartAttack: hasPriorHeartAttack,
        hasPriorStroke: hasPriorStroke
    )
    
    let medicalHistory = GuidedHealthData.MedicalHistoryData(
        familyHeartDiseaseEarly: familyHeartDiseaseEarly,
        familyStrokeEarly: familyStrokeEarly,
        familyType2Diabetes: familyType2Diabetes
    )
    
    let guidedData = GuidedHealthData(
        aboutYou: aboutYou,
        heartHealth: heartHealth,
        medicalHistory: medicalHistory
    )
    
    // Save to database
    try await dataManager.saveGuidedHealthData(
        memberId: memberId,
        healthData: guidedData
    )
    
    // Required transition: accepted_awaiting_data -> data_complete_pending_review
    try await dataManager.updateGuidedSetupStatus(
        memberId: memberId,
        status: .dataCompletePendingReview
    )
    
    // Navigate back to dashboard
    dismiss()
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2289-2310: Save guided health data
func saveGuidedHealthData(memberId: String, healthData: GuidedHealthData) async throws {
    // Convert to JSON structure
    let jsonData = healthData.toJSON()
    
    let updateData: [String: AnyJSON] = [
        "guided_health_data": .object(jsonData),
        "guided_data_complete": .bool(true)
    ]
    
    try await supabase
        .from("family_members")
        .update(updateData)
        .eq("id", value: memberId)
        .execute()
    
    print("✅ DataManager: Guided health data saved for member \(memberId)")
}
```

### 6. User Reviews and Confirms Data

**File:** `Miya Health/ContentView.swift`

```swift
// Line 5308-5377: Confirm data
private func confirmData() async {
    do {
        // Confirm review:
        // - Upserts user_profiles from guided data (DataManager)
        // - Transitions guided_setup_status -> reviewed_complete
        try await dataManager.confirmGuidedDataReview(memberId: memberId)
        onboardingManager.guidedSetupStatus = .reviewedComplete
        
        // Keep in-memory onboarding state in sync
        if let data = guidedData {
            // Parse date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let dob = dateFormatter.date(from: data.aboutYou.dateOfBirth) {
                onboardingManager.dateOfBirth = dob
            }
            
            // Sync all fields
            onboardingManager.gender = data.aboutYou.gender
            onboardingManager.ethnicity = data.aboutYou.ethnicity
            onboardingManager.smokingStatus = data.aboutYou.smokingStatus
            onboardingManager.heightCm = data.aboutYou.heightCm
            onboardingManager.weightKg = data.aboutYou.weightKg
            
            onboardingManager.bloodPressureStatus = data.heartHealth.bloodPressureStatus
            onboardingManager.diabetesStatus = data.heartHealth.diabetesStatus
            onboardingManager.hasPriorHeartAttack = data.heartHealth.hasPriorHeartAttack
            onboardingManager.hasPriorStroke = data.heartHealth.hasPriorStroke
            
            onboardingManager.familyHeartDiseaseEarly = data.medicalHistory.familyHeartDiseaseEarly
            onboardingManager.familyStrokeEarly = data.medicalHistory.familyStrokeEarly
            onboardingManager.familyType2Diabetes = data.medicalHistory.familyType2Diabetes
            
            // Calculate risk assessment
            let riskResult = RiskCalculator.calculateRisk(
                dateOfBirth: onboardingManager.dateOfBirth,
                smokingStatus: onboardingManager.smokingStatus,
                bloodPressureStatus: onboardingManager.bloodPressureStatus,
                diabetesStatus: onboardingManager.diabetesStatus,
                hasPriorHeartAttack: onboardingManager.hasPriorHeartAttack,
                hasPriorStroke: onboardingManager.hasPriorStroke,
                familyHeartDiseaseEarly: onboardingManager.familyHeartDiseaseEarly,
                familyStrokeEarly: onboardingManager.familyStrokeEarly,
                familyType2Diabetes: onboardingManager.familyType2Diabetes
            )
            
            // Store risk in OnboardingManager
            onboardingManager.riskBand = riskResult.band.rawValue
            onboardingManager.riskPoints = riskResult.points
            onboardingManager.optimalVitalityTarget = riskResult.optimalTarget
            
            // Save risk to database
            try await dataManager.saveRiskAssessment(
                riskBand: riskResult.band.rawValue,
                riskPoints: riskResult.points,
                optimalTarget: riskResult.optimalTarget
            )
        }
        
        // Mark onboarding complete
        onboardingManager.completeOnboarding()
        
        // Navigate to dashboard (LandingView will detect isOnboardingComplete)
        
    } catch {
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

**File:** `Miya Health/DataManager.swift`

```swift
// Line 2572-2621: Confirm guided data review
func confirmGuidedDataReview(memberId: String) async throws {
    let supported = await detectGuidedSetupSchemaAvailability()
    guard supported else {
        throw DataError.databaseError("Couldn't complete guided setup. Please try again.")
    }
    
    guard let _ = await currentUserId else {
        throw DataError.notAuthenticated
    }
    
    guard let guided = try await loadGuidedHealthData(memberId: memberId) else {
        throw DataError.databaseError("Couldn't load your guided profile data.")
    }
    
    // Parse yyyy-MM-dd to Date
    let dob: Date? = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: guided.aboutYou.dateOfBirth)
    }()
    
    // Upsert profile fields for the authenticated user
    try await saveUserProfile(
        lastName: nil,
        gender: guided.aboutYou.gender,
        dateOfBirth: dob,
        ethnicity: guided.aboutYou.ethnicity,
        smokingStatus: guided.aboutYou.smokingStatus,
        heightCm: guided.aboutYou.heightCm,
        weightKg: guided.aboutYou.weightKg,
        nutritionQuality: nil,
        bloodPressureStatus: guided.heartHealth.bloodPressureStatus,
        diabetesStatus: guided.heartHealth.diabetesStatus,
        hasPriorHeartAttack: guided.heartHealth.hasPriorHeartAttack,
        hasPriorStroke: guided.heartHealth.hasPriorStroke,
        familyHeartDiseaseEarly: guided.medicalHistory.familyHeartDiseaseEarly,
        familyStrokeEarly: guided.medicalHistory.familyStrokeEarly,
        familyType2Diabetes: guided.medicalHistory.familyType2Diabetes,
        onboardingStep: nil
    )
    
    // Transition: data_complete_pending_review -> reviewed_complete
    try await updateGuidedSetupStatus(memberId: memberId, status: .reviewedComplete)
    print("✅ DataManager: User confirmed guided data review for member \(memberId)")
}
```

---

## Summary

The invite user flow implements a comprehensive system with:

1. **Two distinct paths**: Guided Setup and Self Setup
2. **State machine**: `guided_setup_status` tracks progress through 4 states
3. **Database-driven**: All state stored in `family_members` table
4. **Flexible**: Users can switch from guided to self at acceptance
5. **Validated**: Multiple checks prevent invalid state transitions
6. **Complete**: Covers admin creation through user dashboard access

### Key Design Decisions

- **Invite codes** are unique 4-character codes (MIYA-XXXX)
- **user_id is NULL** until invite is redeemed
- **guided_setup_status** controls routing and permissions
- **Guided data stored as JSON** in `guided_health_data` column
- **Invited users skip family creation** screens
- **Status transitions are explicit** via dedicated functions

### Files Summary

- **ContentView.swift**: 6385 lines, contains all onboarding views
- **DataManager.swift**: 3400+ lines, handles all DB operations
- **OnboardingManager.swift**: 317 lines, manages state
- **GuidedSetupStatus.swift**: 26 lines, defines status enum

This flow ensures a smooth experience for both administrators creating invites and family members joining with either guided assistance or self-directed onboarding.
