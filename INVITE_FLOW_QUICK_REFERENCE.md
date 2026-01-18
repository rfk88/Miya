# Invite User Flow - Quick Reference

## 🎯 Overview

When you invite a user, you choose between **Guided Setup** (you help them) or **Self Setup** (they do it alone). Here's how each path works.

---

## 📊 Quick Comparison

| Aspect | Guided Setup | Self Setup |
|--------|-------------|------------|
| **Admin involvement** | Admin fills health data | User fills own data |
| **User control** | Can accept or decline guidance | Full control from start |
| **Onboarding steps** | Wearables → Wait → Review → Done | Wearables → Full health forms |
| **Time to complete** | Faster (admin does work) | Longer (user completes forms) |
| **Best for** | Elderly, less tech-savvy | Independent, tech-comfortable |

---

## 🔀 Two Main Paths

### Path A: Guided Setup

```
ADMIN                                USER
  │                                   │
  ├─ Create invite                    │
  │  Select "Guided"                  │
  │  Generate code: MIYA-AB12         │
  │                                   │
  │                                   ├─ Enter code MIYA-AB12
  │                                   ├─ Create account
  │                                   │
  │                                   ├─ See prompt:
  │                                   │  "Accept guided?" or "Fill myself?"
  │                                   │
  │                                   ├─ Choose "Accept Guided"
  │                                   ├─ Connect wearable
  │                                   ├─ See "Waiting for admin" screen
  │                                   │
  ├─ Dashboard shows "Pending"        │
  ├─ Click "Fill Out"                 │
  ├─ Complete 3-step form:            │
  │  • About You                      │
  │  • Heart Health                   │
  │  • Medical History                │
  ├─ Save                             │
  │                                   │
  │                                   ├─ Notified "Data ready"
  │                                   ├─ See review screen
  │                                   ├─ Review all data
  │                                   ├─ Click "Confirm"
  │                                   ├─ Risk calculated
  │                                   ├─ → Dashboard ✅
```

### Path B: Self Setup

```
ADMIN                                USER
  │                                   │
  ├─ Create invite                    │
  │  Select "Self"                    │
  │  Generate code: MIYA-XY89         │
  │                                   │
  │                                   ├─ Enter code MIYA-XY89
  │                                   ├─ Create account
  │                                   │
  │                                   ├─ Connect wearable
  │                                   ├─ Fill "About You" form
  │                                   ├─ Fill "Heart Health" form
  │                                   ├─ Fill "Medical History" form
  │                                   ├─ See risk results
  │                                   ├─ Set up alerts & champion
  │                                   ├─ → Dashboard ✅
```

---

## 🔐 Status States (Guided Only)

```
pending_acceptance
    ↓ User enters code
    ↓ User accepts guided
    
accepted_awaiting_data
    ↓ Admin fills health form
    ↓ Admin saves
    
data_complete_pending_review
    ↓ User reviews data
    ↓ User confirms
    
reviewed_complete
    ✅ Done
```

---

## 📱 Screens by User Type

### Admin Screens

| Screen | File Location | Purpose |
|--------|--------------|---------|
| **Build Your Health Team** | ContentView.swift:4069 | Create invites |
| **Guided Data Entry** | ContentView.swift:5380 | Fill member health data |
| **Pending Guided Setups** | DashboardView | See who needs data filled |

### Invited User Screens

| Screen | When Shown | File Location |
|--------|-----------|--------------|
| **Enter Code** | First visit | ContentView.swift:363 |
| **Acceptance Prompt** | Guided invites | ContentView.swift:4918 |
| **Waiting Screen** | After accepting guided | ContentView.swift:5011 |
| **Review Screen** | Admin filled data | ContentView.swift:5064 |
| **Standard Onboarding** | Self setup or switched | Various |

---

## 🎬 User Actions & Results

### For Invited User (Guided Path)

| Action | Result | Status Change |
|--------|--------|---------------|
| Enter code + create account | See acceptance prompt | `pending_acceptance` |
| Click "Accept Guided" | → Wearables, then waiting screen | → `accepted_awaiting_data` |
| Click "Fill myself" | → Self setup flow | → NULL (becomes self) |
| Admin fills data | Notified, see review screen | → `data_complete_pending_review` |
| Click "Confirm" | Risk calculated, → Dashboard | → `reviewed_complete` |
| Click "Make Changes" | → Edit forms manually | Status unchanged |

### For Admin (Guided Path)

| Action | Result | User Status Change |
|--------|--------|-------------------|
| Create guided invite | Generate code MIYA-XXXX | `pending_acceptance` |
| User accepts | See in "Pending Guided Setups" | `accepted_awaiting_data` |
| Fill out health form | Code in review panel | → `data_complete_pending_review` |
| User confirms | Shows in family members | → `reviewed_complete` |

---

## 🗂️ Database Tables

### family_members Table

```sql
-- Created when admin generates invite
{
  id: UUID,                          -- Member ID
  user_id: NULL,                     -- Set when user redeems
  family_id: UUID,                   -- Admin's family
  first_name: "John",
  relationship: "Parent",
  onboarding_type: "Guided Setup",   -- or "Self Setup"
  invite_code: "MIYA-AB12",
  invite_status: "pending",          -- or "accepted"
  guided_setup_status: "pending_acceptance",
  guided_health_data: NULL           -- JSON filled by admin
}

-- After user redeems
{
  user_id: UUID,                     -- ✓ Now set
  invite_status: "accepted",         -- ✓ Changed
  ...
}

-- After admin fills data
{
  guided_setup_status: "data_complete_pending_review",
  guided_health_data: {              -- ✓ Filled
    aboutYou: {...},
    heartHealth: {...},
    medicalHistory: {...}
  },
  guided_data_filled_at: "2025-01-24T10:30:00Z"
}

-- After user confirms
{
  guided_setup_status: "reviewed_complete",
  guided_data_reviewed_at: "2025-01-24T11:00:00Z"
}
```

---

## 🔧 Key Functions

### Admin Side

| Function | File | What It Does |
|----------|------|-------------|
| `saveFamilyMemberInviteWithId()` | DataManager.swift:2002 | Creates invite record in DB |
| `generateInviteCode()` | DataManager.swift:1825 | Makes unique MIYA-XXXX code |
| `saveGuidedHealthData()` | DataManager.swift:2289 | Saves admin-filled health data |

### User Side

| Function | File | What It Does |
|----------|------|-------------|
| `lookupInviteCode()` | DataManager.swift:2097 | Validates code, returns details |
| `completeInviteRedemption()` | DataManager.swift:2189 | Links user to family |
| `acceptGuidedSetup()` | DataManager.swift:2666 | User accepts guidance |
| `switchToSelfSetup()` | DataManager.swift:2625 | User declines guidance |
| `confirmGuidedDataReview()` | DataManager.swift:2572 | User confirms data, writes to profile |

---

## 🚦 Decision Points

### When Creating Invite

```
Q: Is the user comfortable with technology?
├─ YES → Self Setup
└─ NO  → Guided Setup
```

### When User Enters Code (Guided)

```
Q: Do you want admin help?
├─ YES → Accept Guided
│         • Admin fills your data
│         • You review and confirm
│         • Faster completion
│
└─ NO  → Fill Myself
          • Switches to self setup
          • You fill all forms
          • More control
```

---

## 🎨 UI Components

### Invite Code Card (Admin sees)

```
┌─────────────────────────────────┐
│  Invite Code for John           │
│                                 │
│  MIYA-AB12                      │
│                                 │
│  [Copy Code]  [Share]           │
└─────────────────────────────────┘
```

### Acceptance Prompt (User sees)

```
┌─────────────────────────────────┐
│  Smith Family can help you      │
│  set up your profile            │
│                                 │
│  ┌─────────────────────────┐   │
│  │ ✓ Accept Guided Setup   │   │
│  │   Let them fill it out  │   │
│  └─────────────────────────┘   │
│                                 │
│  ┌─────────────────────────┐   │
│  │ ✎ I'll fill it myself   │   │
│  │   Complete your own     │   │
│  └─────────────────────────┘   │
└─────────────────────────────────┘
```

### Waiting Screen (User sees after accepting)

```
┌─────────────────────────────────┐
│       ⏰                         │
│                                 │
│  Waiting for Smith Family       │
│                                 │
│  Your family admin will         │
│  complete your health info.     │
│  We'll let you know when        │
│  it's ready to review.          │
│                                 │
│         [Got it]                │
└─────────────────────────────────┘
```

---

## 📋 Checklist: Testing the Flow

### Guided Setup Test

- [ ] Admin creates guided invite
- [ ] Code generated (MIYA-XXXX format)
- [ ] User enters code → sees family name
- [ ] User creates account
- [ ] User sees acceptance prompt
- [ ] User clicks "Accept Guided"
- [ ] User connects wearable
- [ ] User sees waiting screen
- [ ] Admin sees "Pending Guided Setups" in dashboard
- [ ] Admin clicks "Fill Out"
- [ ] Admin completes 3-step form
- [ ] Admin saves → status updates
- [ ] User sees review screen
- [ ] User reviews data
- [ ] User clicks "Confirm"
- [ ] Risk calculated
- [ ] User sees dashboard

### Self Setup Test

- [ ] Admin creates self invite
- [ ] Code generated
- [ ] User enters code
- [ ] User creates account
- [ ] User goes directly to wearables (no prompt)
- [ ] User completes all forms
- [ ] User sees dashboard

### Switch Test

- [ ] Admin creates guided invite
- [ ] User enters code
- [ ] User clicks "Fill myself" (not "Accept")
- [ ] System switches to self setup
- [ ] User completes forms normally
- [ ] Check DB: onboarding_type changed to "Self Setup"

---

## 🚨 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Code already used" | User trying to reuse | Each code is one-time use |
| Stuck in waiting screen | Admin hasn't filled data | Admin needs to complete form |
| Can't find pending setup | Status not updated | Check `guided_setup_status` in DB |
| Review screen not showing | `hasGuidedData` is false | Admin must save the form |

---

## 📞 Code Locations Cheat Sheet

```
ContentView.swift
├─ Line 4069: FamilyMembersInviteView (create invites)
├─ Line 4416: generateInviteCodeAsync() (code generation)
├─ Line 363:  EnterCodeView (user enters code)
├─ Line 640:  createAccountAndJoin() (signup + link)
├─ Line 704:  acceptGuidedSetup() (user accepts)
├─ Line 720:  switchToSelfSetup() (user declines)
├─ Line 4918: GuidedSetupAcceptancePrompt (choice UI)
├─ Line 5011: GuidedWaitingForAdminView (waiting UI)
├─ Line 5064: GuidedSetupReviewView (review UI)
└─ Line 5380: GuidedHealthDataEntryFlow (admin form)

DataManager.swift
├─ Line 1825: generateInviteCode()
├─ Line 2002: saveFamilyMemberInviteWithId()
├─ Line 2097: lookupInviteCode()
├─ Line 2189: completeInviteRedemption()
├─ Line 2289: saveGuidedHealthData()
├─ Line 2257: loadGuidedHealthData()
├─ Line 2572: confirmGuidedDataReview()
├─ Line 2625: switchToSelfSetup()
└─ Line 2666: acceptGuidedSetup()

OnboardingManager.swift
├─ Line 27:  isInvitedUser (bool flag)
├─ Line 33:  guidedSetupStatus (enum)
├─ Line 36:  invitedMemberId (string)
└─ Line 39:  invitedFamilyId (string)

GuidedSetupStatus.swift
└─ Line 4:   GuidedSetupStatus enum (4 states)
```

---

## 🎓 Key Concepts

### Invite Code Format
- Format: `MIYA-XXXX` (4 random characters)
- Characters: A-Z, 0-9
- Unique: Checked against existing codes
- One-time use: Can't be redeemed twice

### Status Transitions
- Each transition is **explicit** (via function call)
- Never skip states
- Status drives UI routing
- Stored in database (`guided_setup_status` column)

### User Types
- **Superadmin**: Creates family, invites others
- **Invited Member**: Uses invite code, joins family
- **Self Setup Member**: Fills own forms
- **Guided Setup Member**: Admin fills forms

### Data Flow
1. Admin creates → family_members row (user_id = NULL)
2. User redeems → user_id set, invite_status = "accepted"
3. Admin fills → guided_health_data populated
4. User confirms → data copied to user_profiles
5. Complete → onboarding_complete = true

---

## 💡 Pro Tips

1. **Always check `guided_setup_status`** - it's the source of truth for routing
2. **NULL status = Self Setup** - guided features not applicable
3. **Invited users skip family creation** - they're already in a family
4. **Status transitions are one-way** - can't go backwards (except switch to self)
5. **Admin can fill data anytime** - even before user accepts (shows in review)

---

## 🔗 Related Files

- `INVITE_USER_FLOW_COMPLETE.md` - Full detailed documentation
- `GUIDED_SETUP_V2_IMPLEMENTATION.md` - Implementation guide
- `GUIDED_ONBOARDING_FIX.md` - Bug fixes history
- `guided_setup_v2_migration.sql` - Database schema
