import SwiftUI
import UIKit
import Foundation
import Supabase
import RookSDK

// AUDIT REPORT (guided onboarding status-driven admin dashboard)
// - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
// - State integrity: Admin "Guided setup" UI reads only from `FamilyMemberRecord.guidedSetupStatus` (canonical DB field)
//   and maps status -> label/CTA with no inferred booleans.
// - DB correctness: Card is fed by `DataManager.fetchFamilyMembers(familyId:)` (fresh query) and filters `onboardingType == "Guided Setup"`.
// - CTA correctness:
//    pending_acceptance -> Resend invite (share sheet; reuses existing invite code; no DB mutation)
//    accepted_awaiting_data -> Start guided setup (routes to GuidedHealthDataEntryFlow)
//    data_complete_pending_review -> Remind member (share sheet; reuses existing invite code; no DB mutation)
//    reviewed_complete -> View profile (routes to ProfileView placeholder)
// - Edge cases: null guided_setup_status is treated as pending_acceptance.
// - Known limitations: Profile routing is a placeholder (ProfileView is not yet driven by real member data in this dashboard).

// MARK: - DASHBOARD VIEW

struct DashboardView: View {
    let familyName: String
    
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    @State internal var selectedFactor: VitalityFactor? = nil
    @State internal var familyMembers: [FamilyMemberScore] = []
    @State internal var resolvedFamilyName: String = ""
    @State internal var vitalityFactors: [VitalityFactor] = []
    
    /// Canonical family member records (includes `guided_setup_status`).
    /// Used for admin status mapping UI; no inference from UI flags.
    @State internal var familyMemberRecords: [FamilyMemberRecord] = []
    
    /// Refresh ID to force family members strip to update
    @State internal var familyMembersRefreshID = UUID()
    
    /// IDs of dismissed guided members (don't show in card)
    @State internal var dismissedGuidedMemberIds: Set<String> = []
    
    
    /// Missing wearable notifications (3 days, 7 days)
    @State internal var missingWearableNotifications: [MissingWearableNotification] = []
    @State internal var selectedMissingWearableNotification: MissingWearableNotification? = nil
    @State internal var dismissedMissingWearableIds: Set<String> = []

    /// Current authenticated user ID (loaded async, used for role checks)
    @State internal var currentUserIdString: String? = nil
    
    // Burger + share state
    @State internal var showSidebar: Bool = false
    @State internal var isShareSheetPresented: Bool = false
    @State internal var shareText: String = ""
    
    // Notifications overlay state
    @State internal var showNotifications: Bool = false
    @State internal var showAllNotifications: Bool = false

    // Family vitality (in-memory only; no UI yet)
    @State internal var familyVitalityScore: Int? = nil
    @State internal var familyVitalityProgressScore: Int? = nil
    @State internal var isLoadingFamilyVitality: Bool = false
    @State internal var familyVitalityErrorMessage: String? = nil
    @State internal var familySnapshot: FamilyVitalitySnapshot? = nil
    @State internal var familyVitalityMembersWithData: Int? = nil
    @State internal var familyVitalityMembersTotal: Int? = nil
    @State internal var trendInsights: [TrendInsight] = []
    @State internal var trendCoverage: TrendCoverageStatus? = nil
    @State internal var isComputingTrendInsights: Bool = false
    @State internal var serverPatternAlerts: [FamilyNotificationItem] = []
    @State internal var selectedFamilyNotification: FamilyNotificationItem? = nil
    @State internal var dataBackfillStatus: DataBackfillStatus? = nil
    
    // Vitality sync state
    @State internal var isCheckingVitality: Bool = false
    @State internal var isWearableSyncing: Bool = false
    @State internal var wearableSyncStatus: String? = nil
    @State internal var lastVitalityCheck: Date? = nil
    
    // Pillar data tracking
    @State internal var sleepDays: Int = 0
    @State internal var stepDays: Int = 0
    @State internal var stressSignalDays: Int = 0
    @State internal var isDataInsufficient: Bool = false
    
    struct DataBackfillStatus {
        let affectedMemberCount: Int
        let oldestSourceDays: Int
        let pillarsAffected: [String] // ["Activity", "Sleep"]
    }
    
    // Family badges (Daily computed; Weekly persisted)
    @State internal var dailyBadgeWinners: [BadgeEngine.Winner] = []
    @State internal var weeklyBadgeWinners: [BadgeEngine.Winner] = []
    @State internal var weeklyBadgeWeekStart: String? = nil
    @State internal var weeklyBadgeWeekEnd: String? = nil
    @State internal var selectedBadge: BadgeEngine.Winner? = nil

    // Superadmin-only: present Invite Member flow from sidebar reliably (single source of truth at Dashboard root)
    @State internal var isInviteMemberSheetPresented: Bool = false

    // Loading states (avoid flashing placeholders while data is still loading)
    @State internal var isLoadingFamilyMembers: Bool = false
    @State internal var isShowingDebugUpload: Bool = false
    @State internal var isShowingDebugAddRecord: Bool = false
    
    internal var displayedNotifications: [FamilyNotificationItem] {
        guard let snapshot = familySnapshot,
              familyVitalityScore != nil,
              !isComputingTrendInsights else {
            return []
        }
        
        let trendNotifications = FamilyNotificationItem.build(
            snapshot: snapshot,
            trendInsights: trendInsights,
            trendCoverage: trendCoverage,
            factors: vitalityFactors,
            members: familyMembers
        ).filter { item in
            if case .trend(let insight) = item.kind {
                return insight.severity != .celebrate
            }
            return true
        }
        
        return serverPatternAlerts.isEmpty ? trendNotifications : serverPatternAlerts
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()  // Use actual onboarding background
            
            VStack(spacing: 0) {
                dashboardTopBar
                
                manualRefreshRow
                
                mainScrollContent
            }
            
            // NOTIFICATIONS OVERLAY
            if showNotifications {
                notificationsOverlay
            }
            
            // SIDEBAR OVERLAY + MENU
            if showSidebar {
                sidebarOverlay
            }
        } // 👈 END OF ZSTACK

        // Attach sheets to the whole dashboard view
        .sheet(item: $selectedFactor) { factor in
            VitalityFactorDetailSheet(factor: factor, dataManager: dataManager)
        }
        .sheet(item: $selectedBadge) { winner in
            BadgeDetailSheet(winner: winner)
        }
        .sheet(isPresented: $isInviteMemberSheetPresented) {
            inviteMemberSheet
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ActivityView(activityItems: [shareText])
        }
        .sheet(item: $selectedFamilyNotification) { item in
            familyNotificationSheet(item)
        }
        .sheet(isPresented: $showAllNotifications) {
            allNotificationsSheet
        }
        .sheet(item: $selectedMissingWearableNotification) { notification in
            missingWearableSheet(notification)
        }
        .onChange(of: selectedFamilyNotification?.id) { _, newId in
            // When the notification detail sheet is dismissed, refetch server pattern alerts
            // so we can show the correct server-style list (with AI) if it was empty before.
            if newId == nil {
                Task { await loadServerPatternAlerts() }
            }
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugUpload) {
            NavigationStack {
                DebugUploadPickerView(members: familyMembers, onboardingManager: onboardingManager, dataManager: dataManager)
            }
        }
        .onChange(of: isShowingDebugUpload) { _, isPresented in
            handleDebugUploadDismiss(isPresented)
        }
        .sheet(isPresented: $isShowingDebugAddRecord) {
            NavigationStack {
                DebugAddRecordView(members: familyMembers, dataManager: dataManager)
            }
        }
        #endif
        .onChange(of: isShowingDebugAddRecord) { _, isPresented in
            handleDebugAddRecordDismiss(isPresented)
        }
        .task {
            await onDashboardAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                if shouldCheckVitality() {
                    await checkAndUpdateCurrentUserVitality()
                }
            }
        }
    } // 👈 END OF `var body: some View`

    // MARK: - Extracted Sheet Views (for compiler performance)
    
    internal var inviteMemberSheet: some View {
        NavigationStack {
            FamilyMembersInviteView(isPresentedFromDashboard: true)
                .environmentObject(onboardingManager)
                .environmentObject(dataManager)
        }
    }
    
    internal func familyNotificationSheet(_ item: FamilyNotificationItem) -> some View {
        FamilyNotificationDetailSheet(
            item: item,
            onStartRecommendedChallenge: {
                // Challenge feature removed
            },
            dataManager: dataManager
        )
    }
    
    internal func missingWearableSheet(_ notification: MissingWearableNotification) -> some View {
        MissingWearableDetailSheet(
            notification: notification,
            onDismiss: {
                dismissMissingWearableNotification(id: notification.id)
                selectedMissingWearableNotification = nil
            },
            onSendMessage: { [self] message, platform in
                if platform == .whatsapp {
                    openWhatsApp(with: message)
                } else {
                    openMessages(with: message)
                }
            }
        )
    }
    
    internal var allNotificationsSheet: some View {
        AllNotificationsView(
            notifications: displayedNotifications,
            onTap: { [self] notification in
                showAllNotifications = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedFamilyNotification = notification
                }
            },
            onSnooze: { [self] notification, days in
                showAllNotifications = false
                Task {
                    await snoozeNotification(notification, days: days)
                }
            }
        )
    }

    // MARK: - Helper Functions
    
    internal func handleDebugUploadDismiss(_ isPresented: Bool) {
        guard !isPresented else { return }
        Task {
            #if DEBUG
            print("DEBUG_UPLOAD: sheet dismissed → refreshing family + trends")
            #endif
            await refreshFamilyVitalitySnapshotsIfPossible()
            await loadFamilyMembers()
            await loadServerPatternAlerts()
            await loadFamilyVitality()
            familyMembersRefreshID = UUID()
            await computeAndStoreFamilySnapshot()
            await computeTrendInsights()
            await computeFamilyBadgesIfNeeded()
        }
    }
    
    internal func handleDebugAddRecordDismiss(_ isPresented: Bool) {
        guard !isPresented else { return }
        Task {
            #if DEBUG
            print("DEBUG_ADD_RECORD: sheet dismissed → refreshing family + trends")
            #endif
            await refreshFamilyVitalitySnapshotsIfPossible()
            await loadFamilyMembers()
            await loadServerPatternAlerts()
            await loadFamilyVitality()
            familyMembersRefreshID = UUID()
            await computeAndStoreFamilySnapshot()
            await computeTrendInsights()
            await computeFamilyBadgesIfNeeded()
        }
    }

    internal var dashboardTopBar: some View {
        DashboardTopBar(
            familyName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
            onShareTapped: {
                // 1) Build the share text
                prepareShareText()
                // 2) Show the native share sheet
                isShareSheetPresented = true
            },
            onMenuTapped: {
                // Open sidebar
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSidebar = true
                }
            },
            onNotificationsTapped: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications.toggle()
                }
            }
        )
    }

    internal var manualRefreshRow: some View {
        HStack {
            Spacer()
            Button {
                Task {
                    await checkAndUpdateCurrentUserVitality()
                }
            } label: {
                Image(systemName: isWearableSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .foregroundColor(.miyaPrimary)
                    .rotationEffect(.degrees(isWearableSyncing ? 360 : 0))
                    .animation(isWearableSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isWearableSyncing)
                    .font(.system(size: 16))
            }
            .disabled(isWearableSyncing || isCheckingVitality)
            .padding(.trailing, 16)
            .padding(.top, 4)
        }
    }

    internal var notificationsOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        showNotifications = false
                    }
                }

            // Notification panel
            NotificationPanel(onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
            })
            .transition(
                SwiftUI.AnyTransition
                    .move(edge: SwiftUI.Edge.top)
                    .combined(with: SwiftUI.AnyTransition.opacity)
            )
            .zIndex(2)
        }
    }

    internal var sidebarOverlay: some View {
        ZStack {
            // darkened background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar = false
                    }
                }

            // Sidebar pinned to the LEFT
            SidebarMenu(
                isVisible: $showSidebar,
                isInviteMemberSheetPresented: $isInviteMemberSheetPresented,
                familyMemberRecords: familyMemberRecords,
                currentUserId: currentUserIdString,
                familyDisplayName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
                onReloadMembers: {
                    Task { await loadFamilyMembers() }
                },
                onUpdateResolvedFamilyName: { newName in
                    resolvedFamilyName = newName
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .leading))
        }
        .zIndex(1)
    }

// MARK: - CHAT WITH ARLO CARD
    
// MARK: - CHAT WITH ARLO (PRIMARY CTA)
    
    struct ChatWithArloCard: View {
        // IMPORTANT: keep your existing navigation/tap behavior.
        // If your previous ChatWithArloCard had environment objects / routing state,
        // keep them here and keep the action/destination exactly the same.

        // Keep same action - just change UI to primary button
        var onTap: () -> Void = {
            print("Open full chat with Arlo")
            // later: navigate to full chat screen
        }
        
        var body: some View {
            // ✅ IMPORTANT:
            // Replace ONLY the wrapper below with whatever you already had:
            // - If you used NavigationLink, keep the same destination.
            // - If you used Button, keep the same action.
            //
            // EXAMPLE BUTTON WRAPPER (replace with your existing action):
            Button {
                // KEEP YOUR EXISTING ACTION EXACTLY
                // e.g. open AI chat sheet / navigate to Arlo chat
                onTap()
            } label: {
                chatCTAContent
            }
            .buttonStyle(.plain)
        }

        internal var chatCTAContent: some View {
            HStack(spacing: 16) {
                    ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DashboardDesign.buttonTint.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.75), lineWidth: 0.9)
                        )
                        .frame(width: 54, height: 54)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                        Text("Chat with Arlo")
                        .font(DashboardDesign.title2Font)
                        .foregroundColor(DashboardDesign.primaryTextColor)

                        Text("Your AI health coach")
                        .font(DashboardDesign.subheadlineFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.65), lineWidth: 0.8)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            .background(DashboardDesign.glassCardBackground(tint: Color.white))
        }
    }
    
// MARK: - FAMILY VITALITY CARD


        // MARK: - Family semicircle vitality gauge

        struct FamilySemiCircleGauge: View {
            let score: Int        // e.g. 78
            let label: String     // e.g. "Good week"

            internal var progress: Double {
                max(0, min(Double(score) / 100.0, 1.0))
            }

            var body: some View {
                VStack(spacing: -24) {

                    // Oura-style arc + centre heart
                    ZStack {
                        // Background arc (full semicircle)
                        ArcShape(progress: 1.0)
                            .stroke(
                                Color(red: 0.90, green: 0.90, blue: 0.92),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )

                        // Active gradient arc
                        ArcShape(progress: progress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.8, blue: 0.75),
                                        Color(red: 0.15, green: 0.55, blue: 1.0),
                                        Color(red: 0.5, green: 0.3, blue: 1.0)
                                    ]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 15, lineCap: .round)
                            )

                        // Centre heart icon
                        Circle()
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                            .overlay(
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.miyaPrimary)
                            )
                            .offset(y: -18)   // moves it up into the arc
                    }
                    .frame(height: 110)

                    // Text stack under the arc
                    VStack(spacing: 2) {
                        Text("Family vitality")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)

                        Text("\(score)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)

                        Text(label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.top, -4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        // MARK: - Traffic Light Helpers
        
        internal func statusBand(for percent: Int) -> Int {
            switch percent {
            case ..<40: return 0
            case 40..<70: return 1
            default: return 2
            }
        }
        
        internal func bandColor(for index: Int) -> Color {
            switch index {
            case 0: return Color.red.opacity(0.9)
            case 1: return Color.yellow.opacity(0.9)
            default: return Color.green.opacity(0.9)
            }
        }
        
        internal func trafficProgressBar(for percent: Int) -> some View {
            let clamped = max(0, min(percent, 100))
            let band = statusBand(for: clamped)
            let fill = bandColor(for: band)

            let totalWidth: CGFloat = 64
            let height: CGFloat = 7
            let corner: CGFloat = height / 2

            // Show a small “dot” for tiny non-zero values so 1–5% isn’t invisible.
            let rawFillWidth = totalWidth * (CGFloat(clamped) / 100.0)
            let fillWidth = (clamped == 0) ? 0 : max(rawFillWidth, height)

            return ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color(red: 0.82, green: 0.82, blue: 0.84))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(Color(red: 0.78, green: 0.78, blue: 0.80), lineWidth: 0.5)
                    )

                RoundedRectangle(cornerRadius: corner)
                    .fill(fill)
                    .frame(width: fillWidth)
                    .animation(.easeInOut(duration: 0.2), value: clamped)
            }
            .frame(width: totalWidth, height: height, alignment: .leading)
            .clipped()
            .fixedSize()
        }
}

// MARK: - PERSONAL VITALITY CARD

// MARK: - DashboardView Content Extensions
extension DashboardView {
    internal var mainScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardDesign.sectionSpacing) {
                dataBackfillBanner
                debugButtonsRow
                familyMembersSection
                guidedSetupSection
                notificationsSection
                missingWearableSection
                ChatWithArloCard()
                familyVitalitySection
                dataGuidanceBannerSection
                badgesSection
                personalVitalitySection
                Spacer(minLength: DashboardDesign.sectionSpacing)
            }
            .padding(EdgeInsets(
                top: DashboardDesign.internalSpacing,
                leading: DashboardDesign.cardPadding,
                bottom: DashboardDesign.sectionSpacing,
                trailing: DashboardDesign.cardPadding
            ))
        }
        .refreshable {
            await onPullToRefresh()
        }
    }

    @ViewBuilder
    internal var dataBackfillBanner: some View {
        if let status = dataBackfillStatus {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("Some data estimated from \(status.oldestSourceDays)d ago (\(status.affectedMemberCount) member\(status.affectedMemberCount == 1 ? "" : "s"))")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Button("Dismiss") {
                    withAnimation {
                        dataBackfillStatus = nil
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.yellow.opacity(0.15))
            .cornerRadius(8)
            .padding(.horizontal, DashboardDesign.cardPadding)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    internal var debugButtonsRow: some View {
        #if DEBUG
        HStack(spacing: DashboardDesign.smallSpacing) {
            Button {
                isShowingDebugUpload = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                    Text("Upload data")
                        .font(DashboardDesign.tinyFont)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .cornerRadius(DashboardDesign.tinyCornerRadius)
            }

            Button {
                isShowingDebugAddRecord = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("Add record")
                        .font(DashboardDesign.tinyFont)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .cornerRadius(DashboardDesign.tinyCornerRadius)
            }
        }
        .padding(.bottom, DashboardDesign.tinySpacing)
        #else
        EmptyView()
        #endif
    }

    internal var familyMembersSection: some View {
        Group {
            if isLoadingFamilyMembers {
                DashboardInlineLoaderCard(title: "Family members")
            } else {
                FamilyMembersStrip(members: familyMembers, familyId: dataManager.currentFamilyId)
                    .id(familyMembersRefreshID)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    internal var guidedSetupSection: some View {
        if let uid = currentUserIdString,
           let myMembership = familyMemberRecords.first(where: { $0.userId?.uuidString == uid }),
           (myMembership.role == "admin" || myMembership.role == "superadmin") {
            let guidedMembers = familyMemberRecords.filter {
                $0.onboardingType == "Guided Setup" &&
                !dismissedGuidedMemberIds.contains($0.id.uuidString)
            }
            if !guidedMembers.isEmpty {
                GuidedSetupStatusCard(
                    members: guidedMembers,
                    familyName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
                    onDismiss: { memberId in
                        dismissedGuidedMemberIds.insert(memberId)
                        if let uid = currentUserIdString {
                            persistDismissedGuidedMembers(for: uid)
                        }
                    }
                ) { member, action in
                    handleGuidedStatusAction(member: member, action: action)
                }
            }
        }
    }

    @ViewBuilder
    internal var notificationsSection: some View {
        let notifications = displayedNotifications
        if !notifications.isEmpty {
            FamilyNotificationsCard(
                items: notifications,
                onTap: { item in
                    selectedFamilyNotification = item
                },
                onSeeAll: {
                    showAllNotifications = true
                }
            )
        }
    }

    @ViewBuilder
    internal var missingWearableSection: some View {
        if !missingWearableNotifications.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wearable Sync Alerts")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(spacing: 10) {
                    ForEach(missingWearableNotifications) { notification in
                        Button {
                            selectedMissingWearableNotification = notification
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    (notification.severity == .critical ? Color.red : Color.orange).opacity(0.25),
                                                    (notification.severity == .critical ? Color.red : Color.orange).opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)

                                    Text(notification.memberInitials)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(notification.severity == .critical ? Color.red : Color.orange)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notification.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(DashboardDesign.primaryTextColor)
                                        .lineLimit(1)

                                    Text(notification.body)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(DashboardDesign.secondaryTextColor)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.5))
                            }
                            .padding(16)
                            .background(DashboardDesign.glassCardBackground(tint: Color.white))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    internal var familyVitalitySection: some View {
        if isLoadingFamilyVitality {
            FamilyVitalityLoadingCard()
        } else if let score = familyVitalityScore {
            FamilyVitalityCard(
                score: score,
                label: vitalityLabel(for: score),
                factors: vitalityFactors,
                includedMembersText: {
                    if let withData = familyVitalityMembersWithData, let total = familyVitalityMembersTotal {
                        return "Included members: \(withData)/\(total)"
                    }
                    return nil
                }(),
                progressScore: familyVitalityProgressScore
            ) { tappedFactor in
                selectedFactor = tappedFactor
            }
        } else {
            FamilyVitalityPlaceholderCard()
        }
    }

    @ViewBuilder
    internal var dataGuidanceBannerSection: some View {
        if (familyVitalityScore == nil || isDataInsufficient) && isWearableSyncing {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)

                    Text(isWearableSyncing ? "Syncing Your Data" : "Building Your Baseline")
                        .font(.system(size: 14, weight: .semibold))
                }

                if let status = wearableSyncStatus {
                    Text(status)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                if sleepDays > 0 || stepDays > 0 || stressSignalDays > 0 {
                    HStack(spacing: 16) {
                        PillarStatusIndicator(name: "Sleep", current: sleepDays, target: 3)
                        PillarStatusIndicator(name: "Movement", current: stepDays, target: 3)
                        PillarStatusIndicator(name: "Recovery", current: stressSignalDays, target: 2)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
        }
    }

    internal var badgesSection: some View {
        FamilyBadgesCard(
            daily: dailyBadgeWinners,
            weekly: weeklyBadgeWinners,
            weekStart: weeklyBadgeWeekStart,
            weekEnd: weeklyBadgeWeekEnd,
            onBadgeTapped: { selectedBadge = $0 }
        )
    }

    @ViewBuilder
    internal var personalVitalitySection: some View {
        if let me = familyMembers.first(where: { $0.isMe }) {
            PersonalVitalityCard(currentUser: me, factors: vitalityFactors)
        }
    }
}



// MARK: - FAMILY VITALITY INSIGHTS CARD (Premium Redesign)

// MARK: - Family Notifications (lightweight, drill-in)
// NOTE: Notification components have been extracted to Dashboard/DashboardNotifications.swift

// MARK: - Insight Components
// NOTE: Insight components have been extracted to Dashboard/DashboardInsights.swift

// MARK: - Loading Step Row Helper View

// MARK: - Pillar Status Indicator


#Preview {
    NavigationStack {
        DashboardView(familyName: "The Kempton Family")
            .environmentObject(AuthManager())
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
    }
}