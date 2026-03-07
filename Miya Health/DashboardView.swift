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

struct MemberPillarNavigation: Identifiable, Hashable {
    let id = UUID()
    let member: FamilyMemberScore
    let pillar: PillarType
    let familyId: String

    static func == (lhs: MemberPillarNavigation, rhs: MemberPillarNavigation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DashboardView: View {
    let familyName: String
    
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    @State internal var selectedFactor: VitalityFactor? = nil
    @State internal var memberPillarNavigation: MemberPillarNavigation? = nil
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
    
    // Chat with Miya sheet
    @State internal var isArloChatPresented: Bool = false
    
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
    @State internal var showBackfillDetailSheet: Bool = false
    @State internal var activeMemberChallenge: ActiveChallenge? = nil
    @State internal var showChallengeInviteSheet: Bool = false
    @State internal var pendingChallengeInvite: (challengeId: String, pillar: VitalityPillar, senderName: String)? = nil
    
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
        struct MemberSyncDetail: Identifiable {
            let id: String   // userId
            let name: String
            let userId: String
            let lastSyncDate: Date?
            let hasBackfill: Bool
        }
        let affectedMemberCount: Int
        let oldestSourceDays: Int
        let pillarsAffected: [String]
        let memberSyncDetails: [MemberSyncDetail]
    }
    
    // Family badges (Daily computed; Weekly persisted)
    @State internal var dailyBadgeWinners: [BadgeEngine.Winner] = []
    @State internal var weeklyBadgeWinners: [BadgeEngine.Winner] = []
    @State internal var isComputingBadges: Bool = false

    // Bell (personal + challenge) notifications
    @State internal var bellNotifications: [BellNotification] = []
    @State internal var weeklyBadgeWeekStart: String? = nil
    @State internal var weeklyBadgeWeekEnd: String? = nil
    @State internal var selectedBadge: BadgeEngine.Winner? = nil
    /// When non-nil, weekly Champions save failed; show banner with message and Try again (BUG-024).
    @State internal var badgeSaveError: String? = nil
    
    // Superadmin-only: present Invite Member flow from sidebar reliably (single source of truth at Dashboard root)
    @State internal var isInviteMemberSheetPresented: Bool = false
    @State internal var showFamilyChallenges: Bool = false
    
    // Loading states (avoid flashing placeholders while data is still loading)
    @State internal var isLoadingFamilyMembers: Bool = false
    @State internal var isShowingDebugUpload: Bool = false
    @State internal var isShowingDebugAddRecord: Bool = false
    
    internal var displayedNotifications: [FamilyNotificationItem] {
        // Server pattern alerts come directly from the DB — they don't require a local snapshot
        // or trend computation. Show them as soon as they are loaded.
        if !serverPatternAlerts.isEmpty {
            return filterByCurrentUser(serverPatternAlerts)
        }
        
        // Trend/fallback notifications require a full family snapshot and finished trend insight
        // computation. Block until all local state is ready to avoid flickering empty states.
        guard let snapshot = familySnapshot,
              familyVitalityScore != nil,
              !isComputingTrendInsights else {
            return []
        }
        
        // Build base family notifications (trend + fallback), filtering out celebrate-only items.
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
        
        return filterByCurrentUser(trendNotifications)
    }
    
    /// Exclude notifications about the logged-in user from the family notifications feed.
    /// Personal drifts are surfaced via the bell / personal notification channels instead.
    private func filterByCurrentUser(_ items: [FamilyNotificationItem]) -> [FamilyNotificationItem] {
        guard let currentUserId = currentUserIdString?.lowercased(), !currentUserId.isEmpty else {
            return items
        }
        return items.filter { item in
            if let memberId = item.memberUserId?.lowercased() {
                return memberId != currentUserId
            }
            return true
        }
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()  // Use actual onboarding background
            
            VStack(spacing: 0) {
                dashboardTopBar
                
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
            VitalityFactorDetailSheet(
                factor: factor,
                dataManager: dataManager,
                onMemberTapped: { member, pillar in
                    guard let fid = dataManager.currentFamilyId else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        memberPillarNavigation = MemberPillarNavigation(
                            member: member,
                            pillar: pillar,
                            familyId: fid
                        )
                    }
                }
            )
        }
        .navigationDestination(item: $memberPillarNavigation) { nav in
            FamilyMemberProfileView(
                memberUserId: nav.member.userId ?? "",
                memberName: nav.member.name,
                familyId: nav.familyId,
                isCurrentUser: nav.member.isMe,
                initialPillar: nav.pillar
            )
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
            // Always use the latest version from serverPatternAlerts so care state
            // updates (e.g. "Following up" after challenge sent) are reflected live.
            let liveItem = serverPatternAlerts.first(where: { $0.id == item.id }) ?? item
            familyNotificationSheet(liveItem)
        }
        .sheet(isPresented: $showFamilyChallenges) {
            FamilyChallengesView()
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showChallengeInviteSheet) {
            if let invite = pendingChallengeInvite {
                ChallengeInviteSheet(
                    challengeId: invite.challengeId,
                    pillar: invite.pillar,
                    senderName: invite.senderName,
                    dataManager: dataManager
                )
                .onDisappear {
                    pendingChallengeInvite = nil
                    Task { await loadActiveMemberChallenge() }
                }
            }
        }
        .sheet(isPresented: $showAllNotifications) {
            allNotificationsSheet
        }
        .sheet(item: $selectedMissingWearableNotification) { notification in
            missingWearableSheet(notification)
        }
        .sheet(isPresented: $isArloChatPresented) {
            arloChatSheet
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

// MARK: - Miya Chat Sheet

    @ViewBuilder
    internal var arloChatSheet: some View {
        // `dataManager.currentFamilyId` is a String? in this project.
        // ArloChatView expects a UUID.
        if let familyIdString = dataManager.currentFamilyId,
           let familyId = UUID(uuidString: familyIdString) {

            ArloChatView(
                familyId: familyId,
                firstName: currentUserFirstNameForGreeting(),
                openingLine: arloVitalityBand(for: familyVitalityScore).sentence
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)

                Text("Couldn’t open Miya")
                    .font(.system(size: 16, weight: .semibold))

                Text("Family ID is missing or invalid. Please refresh the dashboard and try again.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    
    @MainActor
    internal func presentArloChat() async {
        // If vitality isn't loaded yet, try to load it before presenting chat.
        if familyVitalityScore == nil {
            await loadFamilyVitality()
        }
        isArloChatPresented = true
    }
    
    internal func familyNotificationSheet(_ item: FamilyNotificationItem) -> some View {
        FamilyNotificationDetailSheet(
            item: item,
            onStartRecommendedChallenge: {
                let success = await startRecommendedChallenge(for: item)
                if success {
                    // Refresh the notification card immediately so "Following up" appears
                    // without waiting for the sheet to fully dismiss.
                    await loadServerPatternAlerts()
                }
                return success
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
                snoozeMissingWearableNotification(id: notification.id, forDays: 3)
                selectedMissingWearableNotification = nil
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
    // MARK: - Miya Chat (General)
    
    /// Option A thresholds for the family vitality band.
    /// >= 75: strong, 55–74: steady, < 55: needs support.
    internal func arloVitalityBand(for score: Int?) -> ArloVitalityBand {
        guard let score else { return .unknown }
        if score >= 75 { return .strong }
        if score >= 55 { return .steady }
        return .needsSupport
    }
    
    internal enum ArloVitalityBand {
        case strong
        case steady
        case needsSupport
        case unknown
        
        var sentence: String {
            switch self {
            case .strong:
                return "your family’s Vitality looks strong overall right now"
            case .steady:
                return "your family’s Vitality looks fairly steady right now, with a bit of room to improve"
            case .needsSupport:
                return "your family’s Vitality could use a bit of support right now"
            case .unknown:
                return "things look generally on track for your family right now"
            }
        }
    }
    
    /// Best-effort first-name extraction without relying on unknown model fields.
    /// Uses Mirror so this compiles even if the model changes.
    internal func currentUserFirstNameForGreeting() -> String {
        if let me = familyMembers.first(where: { $0.isMe }) {
            if let name = extractFirstNameUsingMirror(me) {
                return name
            }
        }
        return "there"
    }
    
    internal func extractFirstNameUsingMirror(_ value: Any) -> String? {
        let mirror = Mirror(reflecting: value)

        // Prefer common keys, but we won't assume the model has them.
        let preferredKeys: Set<String> = ["firstName", "firstname", "name", "fullName", "displayName"]

        for child in mirror.children {
            guard let label = child.label else { continue }
            guard preferredKeys.contains(label) else { continue }

            if let stringValue = child.value as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                return trimmed.components(separatedBy: .whitespaces).first
            }
        }

        return nil
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
                notificationCount: bellNotifications.count,
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
                    
                    if showNotifications {
                        Task {
                            await loadBellNotifications()
                        }
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
                NotificationPanel(
                    notifications: bellNotifications,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showNotifications = false
                        }
                    },
                    onTap: { notification in
                        handleBellNotificationTap(notification)
                    },
                    onDismissNotification: { notification in
                        dismissBellNotification(notification)
                    }
                )
                .transition(
                    SwiftUI.AnyTransition
                        .move(edge: SwiftUI.Edge.top)
                        .combined(with: SwiftUI.AnyTransition.opacity)
                )
                .zIndex(2)
            }
        }

        // MARK: - Bell Notifications Helpers
        
        internal func loadBellNotifications() async {
            do {
                let items = try await dataManager.fetchBellNotifications(limit: 25)
                await MainActor.run {
                    bellNotifications = items
                }
            } catch {
                print("❌ DashboardView: Failed to load bell notifications: \(error.localizedDescription)")
            }
        }
        
        internal func handleBellNotificationTap(_ notification: BellNotification) {
            switch notification.kind {
            case .personalTrend(let pillar, _, _):
                // Reuse existing navigation to focus the selected pillar for the logged-in user.
                selectedFactor = vitalityFactors.first(where: { factor in
                    switch pillar {
                    case .sleep:
                        return factor.name.lowercased() == "sleep"
                    case .movement:
                        return factor.name.lowercased() == "activity"
                    case .stress:
                        return factor.name.lowercased() == "recovery"
                    }
                })
                // For now we simply close the bell; the user can explore their own dashboard details.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
                
            case .patternAlert(_, _, _, let alertStateId):
                if let id = alertStateId,
                   let item = serverPatternAlerts.first(where: { $0.id == id }) {
                    selectedFamilyNotification = item
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
                
            case .challengeInvite(let isForSelf, let pillar, let challengeId, let adminUserId):
                if isForSelf {
                    let senderName = resolveInviterDisplayName(adminUserId: adminUserId) ?? "your family"
                    pendingChallengeInvite = (challengeId, pillar, senderName)
                    showChallengeInviteSheet = true
                } else {
                    showFamilyChallenges = true
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
                
            case .careOutcome(let alertStateId, _):
                if let id = alertStateId,
                   let item = serverPatternAlerts.first(where: { $0.id == id }) {
                    selectedFamilyNotification = item
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
                
            case .challengeInviteExpired:
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
                
            case .challengeDaily, .challengeCompleted:
                showFamilyChallenges = true
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showNotifications = false
                }
            }
        }
        
        internal func dismissBellNotification(_ notification: BellNotification) {
            // Local-only dismiss for now; backend \"read\" tracking can be added later.
            withAnimation(.easeInOut(duration: 0.15)) {
                bellNotifications.removeAll { $0.id == notification.id }
            }
        }
        
        /// Resolve display name for challenge inviter from the admin_user_id in the notification payload.
        private func resolveInviterDisplayName(adminUserId: String?) -> String? {
            guard let adminId = adminUserId?.lowercased() else { return nil }
            return familyMembers.first { $0.userId?.lowercased() == adminId }?.name.components(separatedBy: " ").first
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
                    },
                    onFamilyChallenges: {
                        showFamilyChallenges = true
                        showSidebar = false
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .leading))
            }
            .zIndex(1)
        }
        
        // MARK: - CHAT WITH MIYA CARD
        
        // MARK: - CHAT WITH MIYA (PRIMARY CTA)
        
        struct ChatWithArloCard: View {
            var onTap: () -> Void
            
            var body: some View {
                // ✅ IMPORTANT:
                // Replace ONLY the wrapper below with whatever you already had:
                // - If you used NavigationLink, keep the same destination.
                // - If you used Button, keep the same action.
                //
                // EXAMPLE BUTTON WRAPPER (replace with your existing action):
                Button {
                    // KEEP YOUR EXISTING ACTION EXACTLY
                    // e.g. open AI chat sheet / navigate to Miya chat
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
                        Text("Chat with Miya")
                            .font(DashboardDesign.title2Font)
                            .foregroundColor(DashboardDesign.primaryTextColor)
                        
                        Text("Your Miya health coach")
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
                    familyMembersSection
                    guidedSetupSection
                    missingWearableSection
                    familyVitalitySection
                    notificationsSection
                    if let challenge = activeMemberChallenge {
                        MyChallengeView(challenge: challenge)
                    }
                    ChatWithArloCard(onTap: {
                        Task { await presentArloChat() }
                    })
                    dataGuidanceBannerSection
                    badgeSaveErrorBanner
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
                Button {
                    showBackfillDetailSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Some data estimated from \(status.oldestSourceDays)d ago")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextPrimary)
                            Text("\(status.affectedMemberCount) member\(status.affectedMemberCount == 1 ? "" : "s") affected — tap to see details")
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation { dataBackfillStatus = nil }
                        } label: {
                            Text("Dismiss")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DashboardDesign.cardPadding)
                .padding(.top, 8)
                .sheet(isPresented: $showBackfillDetailSheet) {
                    BackfillDetailSheet(status: status)
                }
            }
        }
        
        @ViewBuilder
        internal var badgeSaveErrorBanner: some View {
            if let message = badgeSaveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text("Champions couldn't be saved. \(message)")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextPrimary)
                    Spacer()
                    Button("Try again") {
                        Task { await computeFamilyBadgesIfNeeded() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                    Button("Dismiss") {
                        withAnimation {
                            badgeSaveError = nil
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
                    FamilyMembersStrip(members: familyMembers, familyId: dataManager.currentFamilyId, currentUserAvatarURL: onboardingManager.avatarURL)
                        .id(familyMembersRefreshID)
                }
            }
            .padding(.top, 8)
        }

        // MARK: - Last Synced Status Row

        @ViewBuilder
        internal var lastSyncedStatusRow: some View {
            let lastSync = UserDefaults.standard.object(forKey: "rook_last_foreground_sync") as? Date
            let hoursSince = lastSync.map { Date().timeIntervalSince($0) / 3600 } ?? Double.infinity

            HStack(spacing: 6) {
                if isWearableSyncing {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                    Text("Syncing health data…")
                        .font(DashboardDesign.captionFont)
                        .foregroundColor(DashboardDesign.tertiaryTextColor)
                } else if let date = lastSync {
                    Image(systemName: hoursSince < 6 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(hoursSince < 6 ? .green.opacity(0.65) : .orange.opacity(0.75))
                    Text("Synced \(relativeSyncLabel(date))")
                        .font(DashboardDesign.captionFont)
                        .foregroundColor(DashboardDesign.tertiaryTextColor)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.75))
                    Text("Health data not yet synced")
                        .font(DashboardDesign.captionFont)
                        .foregroundColor(DashboardDesign.tertiaryTextColor)
                }

                Spacer()

                if !isWearableSyncing && hoursSince > 6 {
                    Button {
                        Task { await checkAndUpdateCurrentUserVitality() }
                    } label: {
                        Text("Sync now")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.miyaPrimary)
                    }
                    .disabled(isCheckingVitality)
                }
            }
            .padding(.top, -8)
        }

        private func relativeSyncLabel(_ date: Date) -> String {
            let seconds = Date().timeIntervalSince(date)
            let minutes = Int(seconds / 60)
            let hours = Int(seconds / 3600)
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes)m ago" }
            if hours < 24 { return "\(hours)h ago" }
            let days = hours / 24
            return "\(days)d ago"
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
                    },
                    onSnooze: { item, days in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            serverPatternAlerts.removeAll { $0.id == item.id }
                        }
                        Task { await snoozeNotification(item, days: days) }
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
                    progressScore: familyVitalityProgressScore,
                    onFactorTapped: { tappedFactor in
                        selectedFactor = tappedFactor
                    },
                    onFamilyChallenges: {
                        showFamilyChallenges = true
                    }
                )
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
                isLoading: isComputingBadges,
                onBadgeTapped: { selectedBadge = $0 }
            )
        }
        
        @ViewBuilder
        internal var personalVitalitySection: some View {
            if let me = familyMembers.first(where: { $0.isMe }) {
                PersonalVitalityCard(currentUser: me, factors: vitalityFactors, avatarURL: onboardingManager.avatarURL)
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

// MARK: - Backfill Detail Sheet

private struct BackfillDetailSheet: View {
    let status: DashboardView.DataBackfillStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("When wearable data is missing for a day, Miya estimates using the most recent reading (up to 3 days old). Reach out to members who haven't synced recently and ask them to open the app or check their wearable connection.")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .listRowBackground(Color.miyaCreamBg)
                        .padding(.vertical, 4)
                }

                Section("Family members") {
                    ForEach(status.memberSyncDetails) { detail in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.miyaSurfaceGrey)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(detail.name.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.miyaTextPrimary)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(detail.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)

                                if let date = detail.lastSyncDate {
                                    let daysAgo = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                                    Text(daysAgo == 0 ? "Synced today" : "Last synced \(daysAgo) day\(daysAgo == 1 ? "" : "s") ago")
                                        .font(.system(size: 13))
                                        .foregroundColor(daysAgo <= 1 ? .miyaTextSecondary : (daysAgo <= 3 ? .orange : .miyaTerracotta))
                                } else {
                                    Text("No wearable data yet")
                                        .font(.system(size: 13))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                            }

                            Spacer()

                            if detail.hasBackfill {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13))
                                    .foregroundColor(.orange)
                            } else if detail.lastSyncDate != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.green.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Data Sync Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
