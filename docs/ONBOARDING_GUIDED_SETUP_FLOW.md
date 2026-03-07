# Guided setup onboarding flow (invite code → status transitions)

Single reference for the guided path: admin invites with "I'll fill out their health info," invitee accepts or chooses self-setup, admin fills the form, invitee reviews and confirms. All status transitions and UI entry points are documented here.

## Overview (plain language)

- **Guided setup** = the family admin invites someone and chooses "I'll fill out their health info for them."
- The admin creates an invite and gets a code to share (e.g. by text).
- The invited person enters that code, creates an account, and sees: **Accept guided setup** (admin will fill the form) or **I'll fill it myself** (self-setup).
- If they accept guided: the system marks them as waiting for the admin to fill data. The admin sees that person on the dashboard and taps **Start guided setup** to open a 3-step form (About You, Heart Health, Family History). When the admin saves, the system marks **data complete, waiting for member review**. The invited person is taken to a **review screen**, then taps **Confirm & Continue** to finish; the system marks them **complete**.

**Flow in one line:** invite code → accept or fill yourself → admin fills form (if accepted) → member reviews and confirms.

## Status values and who triggers each transition

| Status | Meaning | Who triggers next transition |
|--------|---------|------------------------------|
| `pending_acceptance` | Invite created; user has not entered code yet | Invitee (enters code, creates account, accepts or fills self) |
| `accepted_awaiting_data` | User accepted guided; waiting for admin to fill data | Admin (fills 3-step form and saves) |
| `data_complete_pending_review` | Admin filled data; user needs to review | Invitee (reviews and taps Confirm & Continue) |
| `reviewed_complete` | User confirmed; profile is done | — |

- **Guided → Self:** At the acceptance step, if the invitee chooses "I'll fill it myself," `switchToSelfSetup` clears `guided_setup_status` and sets `onboarding_type` to "Self Setup"; the invitee then follows the standard self-setup flow (see [ONBOARDING_SELF_SETUP_FLOW.md](ONBOARDING_SELF_SETUP_FLOW.md)).

## Step map (files and functions)

| Step | Actor | View / component | DataManager / persistence | Transition |
|------|--------|-------------------|---------------------------|------------|
| Create invite (Guided) | Admin | `FamilyMembersInviteView` (ContentView) | `DataManager.saveFamilyMemberInviteWithId(..., guidedSetupStatus: .pendingAcceptance)` | `guided_setup_status = 'pending_acceptance'` |
| Enter code, create account | Invitee | `EnterCodeView` (ContentView): `validateCode()` → `createAccountAndJoin()` | `DataManager.lookupInviteCode(code:)`, `AuthManager.signUp`, `DataManager.createInitialProfile`, `DataManager.completeInviteRedemption` | For guided: show `GuidedSetupAcceptancePrompt` sheet |
| Accept or fill myself | Invitee | `EnterCodeView`: `acceptGuidedSetup()` or `switchToSelfSetup()` | `DataManager.acceptGuidedSetup(memberId)` or `DataManager.switchToSelfSetup(memberId)` | `pending_acceptance` → `accepted_awaiting_data` or clear status (self) |
| Admin opens data entry | Admin | Dashboard → `GuidedSetupStatusCard` → `GuidedSetupMemberRow` (DashboardMemberViews): NavigationLink for `accepted_awaiting_data` | — | Navigate to `GuidedHealthDataEntryFlow` |
| Admin fills and saves | Admin | `GuidedHealthDataEntryFlow` (ContentView): 3 steps (About You, Heart Health, Medical History), final Save | `DataManager.saveGuidedHealthData(memberId, healthData)`, `DataManager.updateGuidedSetupStatus(memberId, .dataCompletePendingReview)` | `accepted_awaiting_data` → `data_complete_pending_review` |
| Invitee sees review | Invitee | ContentView body: hard gate when `onboardingManager.guidedSetupStatus == .dataCompletePendingReview` → `GuidedSetupReviewView(memberId)` | — | User sees review screen |
| Invitee confirms | Invitee | `GuidedSetupReviewView`: "Confirm & Continue" → `confirmData()` | `DataManager.confirmGuidedDataReview(memberId)` (upserts user_profiles, sets `guided_data_reviewed_at`, updates status) | `data_complete_pending_review` → `reviewed_complete` |

## Database and schema dependency

- **Table:** `family_members`; column `guided_setup_status` (TEXT), plus `guided_data_filled_at`, `guided_data_reviewed_at`.
- **Migration:** [guided_setup_v2_migration.sql](../guided_setup_v2_migration.sql) **must** be applied for guided status and transitions to work. If the migration has not been run, `DataManager.detectGuidedSetupSchemaAvailability()` returns false and all guided status writes are skipped (accept, admin save, confirm review), so the flow will appear broken.
- **Swift enum:** `GuidedSetupStatus` in `Miya Health/GuidedSetupStatus.swift`; raw values match DB: `pending_acceptance`, `accepted_awaiting_data`, `data_complete_pending_review`, `reviewed_complete`.

## Production vs legacy entry point

- **Production invite flow:** `EnterCodeView` in ContentView is the real path (validate code with `DataManager.lookupInviteCode`, create account, redemption, then for guided invites show acceptance sheet and call `acceptGuidedSetup` / `switchToSelfSetup`).
- **Legacy / non-production:** `InviteCodeEntryView` (InviteCodeEntryView.swift) uses mock lookup (`InviteInfo.mockFrom(code:)`) and empty callbacks for accept/fill-myself; it is **not** the production invite flow. Do not use it as the main way to enter an invite code; production uses EnterCodeView.

## Verification checklist (QA)

1. Run [guided_setup_v2_migration.sql](../guided_setup_v2_migration.sql) on the target project.
2. As admin, create a **Guided Setup** invite; confirm in DB that `family_members.guided_setup_status = 'pending_acceptance'` for that row.
3. As invitee, use the **production** invite flow (EnterCodeView): enter code, create account, tap **Accept guided setup**; confirm status becomes `accepted_awaiting_data` and invitee reaches the next screen (e.g. wearables).
4. As admin, open dashboard, find the member in the "Guided setup" card, tap **Start guided setup**, fill the 3-step form, Save; confirm status becomes `data_complete_pending_review`.
5. As invitee, open app; confirm they are routed to the review screen (`GuidedSetupReviewView`), tap **Confirm & Continue**; confirm status becomes `reviewed_complete` and they reach the intended completion state.
6. Repeat once with **I'll fill it myself** at the acceptance step: confirm `switchToSelfSetup` is called and `guided_setup_status` is cleared / `onboarding_type` is "Self Setup".
