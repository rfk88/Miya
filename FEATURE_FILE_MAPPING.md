# Feature-to-File Mapping Guide

This document maps each feature in the Miya Health application to its corresponding files.

---

## 📱 Core App Structure

### App Entry Point
- **`Miya Health/Miya_HealthApp.swift`** - Main app entry point, initializes managers and session management
- **`Miya Health/ContentView.swift`** - Root view with routing logic for onboarding and main app
- **`Miya Health/AppDelegate.swift`** - UIKit app delegate for background tasks

### Core Managers
- **`Miya Health/AuthManager.swift`** - Authentication and session management
- **`Miya Health/DataManager.swift`** - Data fetching and caching from Supabase
- **`Miya Health/OnboardingManager.swift`** - Onboarding flow state management
- **`Miya Health/Miya.swift`** - Core data models and utilities

---

## 🔐 Authentication & Login

### Login Flow
- **`Miya Health/ContentView.swift`** (LoginView struct) - Login screen UI
- **`Miya Health/AuthManager.swift`** - Login logic, session restoration

### Invite Code Entry
- **`Miya Health/InviteCodeEntryView.swift`** - Enter invite code screen
- **`Miya Health/InviteInfo.swift`** - Invite code data models
- **`Miya Health/ContentView.swift`** (EnterCodeView struct) - Invite code validation and account creation

---

## 🚀 Onboarding Features

### Super Admin Onboarding (Account Creator)
- **`Miya Health/ContentView.swift`** (SuperadminOnboardingView struct) - Step 1: Create account and family
- **`Miya Health/ContentView.swift`** (FamilySetupView struct) - Family creation form

### Wearable Selection
- **`Miya Health/ContentView.swift`** (WearableSelectionView struct) - Step 2: Choose wearable device
- **`Miya Health/RookAuthorizationView.swift`** - ROOK SDK authorization flow
- **`Miya Health/RookAuthorizationView.swift`** (RookWebAuthView) - Web-based ROOK auth UI

### Health Data Collection
- **`Miya Health/ContentView.swift`** (AboutYouView struct) - Step 3: Personal info (age, sex, height, weight, smoking)
- **`Miya Health/ContentView.swift`** (HeartHealthView struct) - Step 4: Heart health (BP, diabetes, medical conditions)
- **`Miya Health/ContentView.swift`** (MedicalHistoryView struct) - Step 5: Family health history

### Risk Assessment
- **`Miya Health/RiskCalculator.swift`** - WHO cardiovascular risk calculation engine
- **`Miya Health/RiskResultsView.swift`** - Step 6: Display risk band, BMI, vitality target

### Family Invites
- **`Miya Health/ContentView.swift`** (FamilyMembersInviteView struct) - Step 7: Invite family members
- **`Miya Health/ContentView.swift`** (PendingGuidedSetupsView struct) - View pending guided setups

### Alerts & Champions
- **`Miya Health/ContentView.swift`** (AlertsChampionView struct) - Step 8: Choose alerts champion
- **`Miya Health/ContentView.swift`** (WellbeingPrivacyView struct) - Privacy settings

### Onboarding Completion
- **`Miya Health/ContentView.swift`** (OnboardingCompleteView struct) - Step 9: Completion screen

### Guided Setup Flow (Admin-Filled Data)
- **`Miya Health/ContentView.swift`** (GuidedAccountControlView struct) - Accept/decline guided setup prompt
- **`Miya Health/ContentView.swift`** (GuidedWaitingForAdminView struct) - Waiting screen for admin to fill data
- **`Miya Health/GuidedHealthDataEditView.swift`** - Admin fills member's health data (3-step form)
- **`Miya Health/ContentView.swift`** (GuidedSetupReviewView struct) - Member reviews and approves admin-filled data
- **`Miya Health/GuidedSetupStatus.swift`** - Guided setup status models

### Self Setup Flow
- **`Miya Health/SelfOnboardingFlowView.swift`** (SelfSetupFlowView struct) - Self-paced onboarding for invited users

---

## 📊 Dashboard Features

### Main Dashboard
- **`Miya Health/DashboardView.swift`** - Main dashboard view with all cards and sections
- **`Miya Health/DashboardBaseComponents.swift`** - Shared dashboard UI components

### Dashboard Components
- **`Miya Health/Dashboard/DashboardMemberViews.swift`** - Family members strip with vitality rings
- **`Miya Health/Dashboard/DashboardVitalityCards.swift`** - Family and personal vitality score cards
- **`Miya Health/Dashboard/DashboardVitalityDetail.swift`** - Detailed vitality breakdown view
- **`Miya Health/Dashboard/DashboardInsights.swift`** - AI insights and recommendations
- **`Miya Health/Dashboard/DashboardNotifications.swift`** - Pattern alerts and notifications
- **`Miya Health/Dashboard/DashboardModels.swift`** - Dashboard data models
- **`Miya Health/Dashboard/DashboardLoadingStates.swift`** - Loading state UI
- **`Miya Health/Dashboard/DashboardExtensions.swift`** - Dashboard helper extensions

### Dashboard Extensions
- **`Miya Health/Dashboard/DashboardView+DataLoading.swift`** - Data fetching logic
- **`Miya Health/Dashboard/DashboardView+Helpers.swift`** - Helper functions
- **`Miya Health/Dashboard/DashboardView+ShareText.swift`** - Share functionality
- **`Miya Health/Dashboard/DashboardView+SidebarMenu.swift`** - Sidebar menu logic

### Dashboard Sidebar
- **`Miya Health/Dashboard/DashboardSidebar.swift`** (AccountSidebarView) - Account settings sidebar
- **`Miya Health/Dashboard/DashboardSidebar.swift`** (ManageMembersView) - Family member management

### Notifications System
- **`Miya Health/Dashboard/AllNotificationsView.swift`** - Full notifications list
- **`Miya Health/Dashboard/FamilyNotificationsCard.swift`** - Family notifications card
- **`Miya Health/Dashboard/MissingWearableNotification.swift`** - Missing wearable alerts
- **`Miya Health/Dashboard/NotificationModels.swift`** - Notification data models
- **`Miya Health/Dashboard/NotificationHelpers.swift`** - Notification utilities
- **`Miya Health/Dashboard/NotificationDetailComponents.swift`** - Notification detail UI
- **`Miya Health/Dashboard/MessageTemplatesSheet.swift`** - Pre-written message templates

---

## 💬 AI Chat Feature

### Chat Interface
- **`Miya Health/Dashboard/DashboardNotifications.swift`** - Chat UI within notification detail view
  - Chat message display
  - Typing indicator animation
  - Context and history payload building

### Backend Chat Functions
- **`supabase/functions/miya_insight_chat/index.ts`** - Edge function for AI chat responses
  - GPT-4o integration
  - Context-aware responses
  - Conversation history management

---

## 🏃 ROOK Wearable Integration

### ROOK SDK Integration
- **`Miya Health/Services/RookService.swift`** - ROOK SDK configuration and user binding
- **`Miya Health/Services/RookAPIService.swift`** - ROOK API client wrapper
- **`Miya Health/ROOKDataAdapter.swift`** - Adapter for ROOK data structures
- **`Miya Health/ROOKDayToMiyaAdapter.swift`** - Converts ROOK daily summaries to Miya format
- **`Miya Health/ROOKWindowAggregator.swift`** - Aggregates ROOK data over time windows
- **`Miya Health/ROOKModels.swift`** - ROOK data models
- **`Miya Health/ROOKSummaryModels.swift`** - ROOK summary data structures
- **`Miya Health/ROOKAdapterManualTest.swift`** - Manual testing utilities

### ROOK Webhook Handler
- **`supabase/functions/rook/index.ts`** - Webhook handler for ROOK data
  - Sleep summary processing
  - Physical summary processing
  - Activity event processing
  - User ID mapping logic

---

## 📈 Vitality Scoring System

### Scoring Engine
- **`Miya Health/VitalityScoringEngine.swift`** - Main vitality scoring engine
- **`Miya Health/VitalityCalculator.swift`** - Vitality score calculation (sleep, movement, stress)
- **`Miya Health/ScoringSchema.swift`** - Age-specific scoring schema definitions
- **`Miya Health/ScoringSchemaExamples.swift`** - Schema examples and validation

### Vitality Display
- **`Miya Health/VitalityBreakdown.swift`** - Vitality score breakdown UI
- **`Miya Health/VitalityExplanation.swift`** - Vitality score explanation view

### Vitality Data Import
- **`Miya Health/VitalityImportView.swift`** - CSV import for testing
- **`Miya Health/VitalityJSONParser.swift`** - JSON parser for vitality data

### Backend Scoring Functions
- **`supabase/functions/rook/scoring/score.ts`** - Server-side scoring logic
- **`supabase/functions/rook/scoring/schema.ts`** - Scoring schema definitions
- **`supabase/functions/rook/scoring/recompute.ts`** - Recompute vitality scores
- **`supabase/functions/recompute_vitality_scores/index.ts`** - Edge function to recompute scores
- **`supabase/functions/rook_daily_recompute/index.ts`** - Daily vitality score recomputation

### Family Vitality
- **`Miya Health/FamilyVitalitySnapshot.swift`** - Family vitality snapshot models
- **`Miya Health/FamilyVitalityTrendEngine.swift`** - Family vitality trend analysis

---

## 👥 Family & Profile Features

### Profile Management
- **`Miya Health/ProfileView.swift`** - User profile view
- **`Miya Health/EditProfileView.swift`** - Edit profile form
- **`Miya Health/FamilyMemberProfileView.swift`** - Family member profile view

### Family Badges
- **`Miya Health/BadgeEngine.swift`** - Badge calculation engine (daily/weekly winners)
- **`Miya Health/FamilyBadgesComponents.swift`** - Badge display components

### Participants Picker
- **`Miya Health/ParticipantsPicker.swift`** - UI for selecting family members

---

## 🔔 Notifications & Alerts

### Pattern Detection
- **`supabase/functions/rook/patterns/engine.ts`** - Pattern detection engine
- **`supabase/functions/rook/patterns/evaluate.ts`** - Pattern evaluation logic
- **`supabase/functions/rook/patterns/episode.ts`** - Episode detection
- **`supabase/functions/rook/patterns/baseline.ts`** - Baseline calculation
- **`supabase/functions/rook/patterns/types.ts`** - Pattern type definitions

### Notification Processing
- **`supabase/functions/process_notifications/index.ts`** - Process and generate notifications
- **`supabase/functions/miya_insight/index.ts`** - Generate AI insights for alerts

### Message Generation
- **`supabase/functions/regenerate_message/index.ts`** - Regenerate notification messages

---

## ⚙️ Settings & Configuration

### Settings View
- **`Miya Health/SettingsView.swift`** - Settings screen with CSV import option

### Supabase Configuration
- **`Miya Health/SupabaseConfig.swift`** - Supabase client configuration

---

## 🔧 Services & Background Tasks

### Data Services
- **`Miya Health/Services/DataBackfillEngine.swift`** - Backfill missing vitality data
- **`Miya Health/Services/WeeklyVitalityScheduler.swift`** - Weekly vitality score scheduling

---

## 🧪 Testing & Debug Tools

### Debug Views
- **`Miya Health/Dashboard/DashboardDebugTools.swift`** - Debug tools for dashboard
  - DebugAddRecordView
  - DebugUploadPickerView
- **`Miya Health/DebugPatternAlertSimulatorView.swift`** - Simulate pattern alerts for testing

### Activity View
- **`Miya Health/ActivityView.swift`** - Activity indicator wrapper

---

## 📄 Documentation Files

### Implementation Guides
- **`IMPLEMENTATION_SUMMARY.md`** - Vitality testing implementation
- **`WHO_IMPLEMENTATION_STATUS.md`** - WHO risk implementation status
- **`CHAT_COMPLETE_IMPLEMENTATION.md`** - Chat feature implementation
- **`ROOK_ADAPTER_IMPLEMENTATION_COMPLETE.md`** - ROOK adapter implementation
- **`SCORING_ENGINE_COMPLETE.md`** - Scoring engine documentation
- **`DASHBOARD_REFACTORING_COMPLETE.md`** - Dashboard refactoring notes

### Flow Documentation
- **`INVITE_USER_FLOW_COMPLETE.md`** - Invite user flow documentation
- **`GUIDED_ONBOARDING_FIX.md`** - Guided onboarding fixes
- **`ROOK_TO_DASHBOARD_FLOW.md`** - ROOK data flow documentation
- **`ACTIVITY_EVENT_DATA_FLOW.md`** - Activity event data flow

### Quick References
- **`docs/ROOK_QUICK_REFERENCE.md`** - ROOK integration quick reference
- **`docs/ROOK_DATA_FLOW.md`** - ROOK data flow details
- **`docs/ROOK_TO_MIYA_MAPPING.md`** - ROOK to Miya data mapping

---

## 🗄️ Database Migrations

### SQL Migrations
- **`supabase/migrations/`** - All database migration files (28 files)
  - Schema definitions
  - Table creation
  - Function definitions
  - RLS policies

---

## 📊 Data Models

### Core Models (in various files)
- **`Miya Health/Miya.swift`** - Core data models
- **`Miya Health/Dashboard/DashboardModels.swift`** - Dashboard-specific models
- **`Miya Health/Dashboard/NotificationModels.swift`** - Notification models
- **`Miya Health/ROOKModels.swift`** - ROOK data models
- **`Miya Health/ROOKSummaryModels.swift`** - ROOK summary models

---

## 🎨 UI Components

### Shared Components
- **`Miya Health/ContentView.swift`** (CircularProgressView) - Circular progress indicator
- **`Miya Health/DashboardBaseComponents.swift`** - Base dashboard components
- **`Miya Health/Dashboard/DashboardExtensions.swift`** - Dashboard UI extensions

---

## 📝 Summary by Feature Category

### Authentication & Onboarding
- Login, invite codes, account creation
- Super admin onboarding (9 steps)
- Guided setup flow (admin-filled data)
- Self setup flow (user-filled data)

### Dashboard & UI
- Main dashboard with vitality cards
- Family member views
- Notifications and alerts
- Sidebar and settings

### Wearable Integration
- ROOK SDK integration
- Data adapters and aggregators
- Webhook handlers
- User ID mapping

### Scoring & Analytics
- Vitality scoring engine
- Risk calculator (WHO)
- Family vitality trends
- Badge system

### AI & Chat
- AI chat interface
- Pattern detection
- Insight generation
- Message templates

### Data Management
- Data fetching and caching
- Backfill engine
- Weekly scheduling
- CSV/JSON import

---

## 🔍 Quick File Lookup

**Looking for a specific feature? Use this guide:**

- **Login/Auth** → `AuthManager.swift`, `ContentView.swift` (LoginView)
- **Onboarding** → `ContentView.swift` (various View structs), `OnboardingManager.swift`
- **Dashboard** → `DashboardView.swift`, `Dashboard/` folder
- **ROOK Integration** → `Services/RookService.swift`, `ROOK*.swift` files
- **Vitality Scoring** → `VitalityScoringEngine.swift`, `VitalityCalculator.swift`
- **Chat** → `Dashboard/DashboardNotifications.swift`, `supabase/functions/miya_insight_chat/`
- **Notifications** → `Dashboard/Notification*.swift`, `supabase/functions/process_notifications/`
- **Profile** → `ProfileView.swift`, `EditProfileView.swift`
- **Settings** → `SettingsView.swift`, `Dashboard/DashboardSidebar.swift`
