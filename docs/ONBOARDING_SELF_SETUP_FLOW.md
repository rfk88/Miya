# Self-setup onboarding flow (account → wearable → health data)

Single reference for the step-by-step path from account creation through health data to database. All view structs below live in `Miya Health/ContentView.swift`.

## Overview

- **Self-setup** = superadmin path: step 1 (account) through step 7 (alerts/champion).
- **State:** `OnboardingManager` holds all form data (account, family, wearables, about you, heart health, family history, champion, family members).
- **Progress:** `user_profiles.onboarding_step` (1–7) and `user_profiles.onboarding_complete`. Written by `DataManager.saveOnboardingProgress(step:complete:)` and on step change via `OnboardingManager.currentStep` didSet.
- **Resume:** On login, `LoginView` calls `DataManager.loadUserProfile()`, then `onboardingManager.setCurrentStep(profile.onboarding_step ?? 1)` so the user returns to the correct step.

## Step map

| Step | View | OnboardingManager data | Persistence | Transition to next |
|------|------|------------------------|------------|--------------------|
| 1 | `SuperadminOnboardingView` | firstName, lastName, email, password | `AuthManager.signUp()` then `DataManager.createInitialProfile(userId, firstName, step: 1)` | `setCurrentStep(2)` after signUp success |
| 2 | `WearableSelectionView` | connectedWearables | `DataManager.saveWearable(wearableType)` when device connected | `advanceOnboardingAfterWearableConnection()` → `setCurrentStep(3)` (or `completeOnboarding()` for guided invite) |
| 3 | `AboutYouView` | gender, dateOfBirth, ethnicity, smokingStatus, heightCm, weightKg, nutritionQuality | `DataManager.saveUserProfile(...)` with OnboardingManager fields | `setCurrentStep(4)` after save |
| 4 | `HeartHealthView` | bloodPressureStatus, diabetesStatus, hasPriorHeartAttack, hasPriorStroke, hasChronicKidneyDisease, hasAtrialFibrillation, hasHighCholesterol | `DataManager.saveUserProfile(...)` | `setCurrentStep(5)` after save |
| 5 | `MedicalHistoryView` | familyHeartDiseaseEarly, familyStrokeEarly, familyType2Diabetes | `DataManager.saveUserProfile(...)` | `setCurrentStep(6)` (or branch to Breakout views / AlertsChampionView for invited) |
| 6 | `FamilyMembersInviteView` or `AlertsChampionView` | invitedMembers (superadmin); champion/alerts (invited) | Profile and family/invite data as applicable | Navigate to step 7 (e.g. AlertsChampionView) or Breakout2View |
| 7 | `AlertsChampionView` | championName, championEmail, championPhone, championEnabled, notifyInApp, notifyPush, notifyEmail, championNotifyEmail, championNotifySms, quietHours* | `DataManager.saveUserProfile(...)` | `completeOnboarding()` then `OnboardingCompleteView(membersCount)` or equivalent |

Step 8 in OnboardingManager is “Family Members” (invited members list); in the UI it is covered by step 6 (FamilyMembersInviteView) and step 7. The database stores `onboarding_step` 1–7 only.

## Account creation path

**Step 1:** `SuperadminOnboardingView` → user taps Continue → `signUp()` → `AuthManager.signUp(email, password, firstName)` → on success `DataManager.createInitialProfile(userId, firstName, step: 1)` → `onboardingManager.setCurrentStep(2)`.

## Wearable path

**Step 2:** `WearableSelectionView` → user connects device → connection verified → `DataManager.saveWearable(wearableType)` → `advanceOnboardingAfterWearableConnection()` → `onboardingManager.setCurrentStep(3)` (or `completeOnboarding()` for guided invitee).

## Final submission

The “full” profile (all health and preference data) is not written in one shot. Each of AboutYouView (step 3), HeartHealthView (step 4), MedicalHistoryView (step 5), and AlertsChampionView (step 7) calls `DataManager.saveUserProfile(...)` with the relevant OnboardingManager fields for that step. `completeOnboarding()` sets `OnboardingManager.isOnboardingComplete = true`, which triggers `saveOnboardingProgress(step:currentStep, complete: true)`. It is called from WearableSelectionView (guided invitee after wearable connect), AlertsChampionView, or OnboardingCompleteView.

## Invited-user branch

Invited users do not create an account in-app (they already have one). They are routed with `currentStep` from the database; if `currentStep <= 1` they see `WearableSelectionView` first. Step 6 for invited users shows `AlertsChampionView` instead of `FamilyMembersInviteView`. The guided (admin-filled) flow and status transitions are documented separately; this doc focuses on self-setup.
